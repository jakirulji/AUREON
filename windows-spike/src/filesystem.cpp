#include "aureon/filesystem.hpp"

#include <Windows.h>
#include <bcrypt.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <algorithm>
#include <array>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <system_error>
#include <vector>

#ifndef FOFX_RECYCLEONDELETE
#define FOFX_RECYCLEONDELETE 0x00080000
#endif

namespace aureon::filesystem {
namespace {

bool entry_exists(const std::filesystem::path& path) {
    std::error_code ec;
    const auto status = std::filesystem::symlink_status(path, ec);
    return !ec && status.type() != std::filesystem::file_type::not_found;
}

OperationError map_error(const std::error_code& ec) {
    if (ec == std::errc::permission_denied) return OperationError::permission_denied;
    return OperationError::io_error;
}

bool is_within(const std::filesystem::path& child,
               const std::filesystem::path& parent) {
    auto child_it = child.begin();
    for (auto parent_it = parent.begin(); parent_it != parent.end();
         ++parent_it, ++child_it) {
        if (child_it == child.end() || *child_it != *parent_it) return false;
    }
    return true;
}

OperationResult failure(OperationError error) {
    return OperationResult{false, error, {}, {}};
}

bool sha256_file(const std::filesystem::path& path,
                 std::array<unsigned char, 32>& digest) {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD object_size = 0;
    DWORD bytes_written = 0;
    std::vector<unsigned char> hash_object;

    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0)
        != 0) {
        return false;
    }
    if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                          reinterpret_cast<PUCHAR>(&object_size),
                          sizeof(object_size), &bytes_written, 0) != 0) {
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return false;
    }

    hash_object.resize(object_size);
    if (BCryptCreateHash(algorithm, &hash, hash_object.data(), object_size,
                         nullptr, 0, 0) != 0) {
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return false;
    }

    std::ifstream input(path, std::ios::binary);
    bool success = false;
    if (input) {
        std::array<char, 64 * 1024> buffer{};
        bool read_ok = true;
        while (input) {
            input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
            const auto count = input.gcount();
            if (count > 0 &&
                BCryptHashData(hash, reinterpret_cast<PUCHAR>(buffer.data()),
                               static_cast<ULONG>(count), 0) != 0) {
                read_ok = false;
                break;
            }
        }
        read_ok = read_ok && input.eof();
        success = read_ok &&
            BCryptFinishHash(hash, digest.data(),
                             static_cast<ULONG>(digest.size()), 0) == 0;
    }

    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return success;
}

std::string to_hex(const std::array<unsigned char, 32>& digest) {
    std::ostringstream output;
    output << std::hex << std::setfill('0');
    for (const auto byte : digest) {
        output << std::setw(2) << static_cast<unsigned int>(byte);
    }
    return output.str();
}

}  // namespace

std::vector<Entry> enumerate(const std::filesystem::path& directory,
                             const EnumerateOptions& options) {
    std::vector<Entry> entries;
    std::error_code ec;
    std::filesystem::directory_iterator it(
        directory, std::filesystem::directory_options::skip_permission_denied, ec);
    const std::filesystem::directory_iterator end;

    for (; !ec && it != end; it.increment(ec)) {
        const auto& item = *it;
        const auto name = item.path().filename().wstring();
        if (!options.include_hidden && !name.empty() && name.front() == L'.') {
            continue;
        }

        Entry entry;
        entry.path = item.path();
        entry.name = name;

        const auto symlink_status = item.symlink_status(ec);
        if (ec) {
            ec.clear();
            continue;
        }
        entry.is_symlink = std::filesystem::is_symlink(symlink_status);

        auto status = symlink_status;
        if (entry.is_symlink && options.follow_directory_symlinks) {
            status = item.status(ec);
            if (ec) {
                ec.clear();
                continue;
            }
        }
        entry.is_directory = std::filesystem::is_directory(status);

        if (!entry.is_directory && !entry.is_symlink) {
            entry.size_bytes = item.file_size(ec);
            if (ec) {
                ec.clear();
                entry.size_bytes = 0;
            }
        }

        const auto modified = item.last_write_time(ec);
        if (!ec) {
            entry.modified_time_ticks = modified.time_since_epoch().count();
        } else {
            ec.clear();
        }
        entries.push_back(std::move(entry));
    }

    std::sort(entries.begin(), entries.end(),
              [](const Entry& a, const Entry& b) {
                  if (a.is_directory != b.is_directory) return a.is_directory;
                  return a.name < b.name;
              });
    return entries;
}

OperationResult rename_entry(const std::filesystem::path& source,
                             const std::wstring& new_name) {
    if (new_name.empty() || new_name == L"." || new_name == L".." ||
        new_name.find_first_of(L"/\\:") != std::wstring::npos) {
        return failure(OperationError::destination_invalid);
    }
    if (!entry_exists(source)) return failure(OperationError::source_missing);

    const auto destination = source.parent_path() / new_name;
    if (entry_exists(destination)) return failure(OperationError::destination_exists);

    std::error_code ec;
    std::filesystem::rename(source, destination, ec);
    if (ec) return failure(map_error(ec));
    return OperationResult{true, OperationError::none, destination, {}};
}

OperationResult move_entry(const std::filesystem::path& source,
                           const std::filesystem::path& destination_directory) {
    if (!entry_exists(source)) return failure(OperationError::source_missing);

    std::error_code ec;
    const auto source_status = std::filesystem::symlink_status(source, ec);
    if (ec) return failure(map_error(ec));
    if (std::filesystem::is_symlink(source_status)) {
        return failure(OperationError::unsafe_source_type);
    }

    const auto destination_status = std::filesystem::status(destination_directory, ec);
    if (ec || !std::filesystem::is_directory(destination_status)) {
        return failure(OperationError::destination_invalid);
    }

    const auto source_absolute = std::filesystem::weakly_canonical(source, ec);
    if (ec) return failure(map_error(ec));
    const auto destination_absolute =
        std::filesystem::weakly_canonical(destination_directory, ec);
    if (ec) return failure(map_error(ec));

    if (std::filesystem::is_directory(source_status) &&
        is_within(destination_absolute, source_absolute)) {
        return failure(OperationError::destination_invalid);
    }

    const auto destination = destination_absolute / source.filename();
    if (entry_exists(destination)) return failure(OperationError::destination_exists);

    std::filesystem::rename(source, destination, ec);
    if (ec) return failure(map_error(ec));
    return OperationResult{true, OperationError::none, destination, {}};
}

OperationResult copy_file_safely(const std::filesystem::path& source,
                                 const std::filesystem::path& destination) {
    if (!entry_exists(source)) return failure(OperationError::source_missing);

    std::error_code ec;
    const auto source_status = std::filesystem::symlink_status(source, ec);
    if (ec) return failure(map_error(ec));
    if (!std::filesystem::is_regular_file(source_status)) {
        return failure(OperationError::unsafe_source_type);
    }

    const auto parent_status = std::filesystem::status(destination.parent_path(), ec);
    if (ec || !std::filesystem::is_directory(parent_status)) {
        return failure(OperationError::destination_invalid);
    }
    if (entry_exists(destination)) return failure(OperationError::destination_exists);

    auto temporary = destination;
    temporary += L".aureon-partial";
    if (entry_exists(temporary)) return failure(OperationError::destination_exists);

    std::array<unsigned char, 32> source_before{};
    if (!sha256_file(source, source_before)) {
        return failure(OperationError::hash_unavailable);
    }

    const bool copied = std::filesystem::copy_file(
        source, temporary, std::filesystem::copy_options::none, ec);
    if (ec || !copied) {
        std::error_code cleanup_error;
        std::filesystem::remove(temporary, cleanup_error);
        return failure(ec ? map_error(ec) : OperationError::io_error);
    }

    std::array<unsigned char, 32> source_after{};
    std::array<unsigned char, 32> destination_hash{};
    const bool source_hash_ok = sha256_file(source, source_after);
    const bool destination_hash_ok = sha256_file(temporary, destination_hash);
    if (!source_hash_ok || !destination_hash_ok) {
        std::error_code cleanup_error;
        std::filesystem::remove(temporary, cleanup_error);
        return failure(OperationError::hash_unavailable);
    }
    if (source_before != source_after || source_after != destination_hash) {
        std::error_code cleanup_error;
        std::filesystem::remove(temporary, cleanup_error);
        return failure(OperationError::integrity_mismatch);
    }

    std::filesystem::rename(temporary, destination, ec);
    if (ec) {
        std::error_code cleanup_error;
        std::filesystem::remove(temporary, cleanup_error);
        return failure(map_error(ec));
    }
    return OperationResult{true, OperationError::none, destination,
                           to_hex(destination_hash)};
}

OperationResult move_to_recycle_bin(const std::filesystem::path& source) {
    if (!entry_exists(source)) return failure(OperationError::source_missing);

    std::error_code path_error;
    const auto absolute_source = std::filesystem::absolute(source, path_error);
    if (path_error) return failure(map_error(path_error));

    const HRESULT init_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool uninitialize_com = init_result == S_OK || init_result == S_FALSE;
    if (FAILED(init_result) && init_result != RPC_E_CHANGED_MODE) {
        return failure(OperationError::recycle_bin_unavailable);
    }

    IFileOperation* file_operation = nullptr;
    IShellItem* shell_item = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&file_operation));
    if (SUCCEEDED(hr)) {
        hr = SHCreateItemFromParsingName(absolute_source.c_str(), nullptr,
                                         IID_PPV_ARGS(&shell_item));
    }
    if (SUCCEEDED(hr)) {
        // FOFX_RECYCLEONDELETE explicitly requests recycling. No permanent-delete fallback.
        hr = file_operation->SetOperationFlags(FOF_NOCONFIRMATION |
                                               FOFX_RECYCLEONDELETE);
    }
    if (SUCCEEDED(hr)) {
        hr = file_operation->DeleteItem(shell_item, nullptr);
    }
    if (SUCCEEDED(hr)) {
        hr = file_operation->PerformOperations();
    }

    BOOL aborted = FALSE;
    if (SUCCEEDED(hr)) {
        const HRESULT aborted_result = file_operation->GetAnyOperationsAborted(&aborted);
        if (FAILED(aborted_result)) hr = aborted_result;
    }

    if (shell_item != nullptr) shell_item->Release();
    if (file_operation != nullptr) file_operation->Release();
    if (uninitialize_com) CoUninitialize();

    if (aborted) return failure(OperationError::operation_aborted);
    if (FAILED(hr)) return failure(OperationError::recycle_bin_unavailable);
    if (entry_exists(source)) return failure(OperationError::recycle_bin_unavailable);

    return OperationResult{true, OperationError::none, {}, {}};
}

}  // namespace aureon::filesystem
