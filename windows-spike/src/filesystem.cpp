#include "aureon/filesystem.hpp"

#include <algorithm>
#include <system_error>

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
    return OperationResult{false, error, {}};
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
    return OperationResult{true, OperationError::none, destination};
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
    return OperationResult{true, OperationError::none, destination};
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

    const bool copied = std::filesystem::copy_file(
        source, temporary, std::filesystem::copy_options::none, ec);
    if (ec || !copied) {
        std::error_code cleanup_error;
        std::filesystem::remove(temporary, cleanup_error);
        return failure(ec ? map_error(ec) : OperationError::io_error);
    }

    std::filesystem::rename(temporary, destination, ec);
    if (ec) {
        std::error_code cleanup_error;
        std::filesystem::remove(temporary, cleanup_error);
        return failure(map_error(ec));
    }
    return OperationResult{true, OperationError::none, destination};
}

}  // namespace aureon::filesystem
