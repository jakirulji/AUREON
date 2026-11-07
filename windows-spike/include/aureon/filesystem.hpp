#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace aureon::filesystem {

struct Entry {
    std::filesystem::path path;
    std::wstring name;
    bool is_directory{};
    bool is_symlink{};
    std::uintmax_t size_bytes{};
    std::int64_t modified_time_ticks{};
};

struct EnumerateOptions {
    bool include_hidden{true};
    bool follow_directory_symlinks{false};
};

enum class OperationError {
    none,
    source_missing,
    destination_invalid,
    destination_exists,
    unsafe_source_type,
    permission_denied,
    integrity_mismatch,
    hash_unavailable,
    recycle_bin_unavailable,
    operation_aborted,
    io_error,
};

struct OperationResult {
    bool success{};
    OperationError error{OperationError::none};
    std::filesystem::path resulting_path;
    std::string sha256_hex;
};

std::vector<Entry> enumerate(const std::filesystem::path& directory,
                             const EnumerateOptions& options = {});

OperationResult rename_entry(const std::filesystem::path& source,
                             const std::wstring& new_name);

OperationResult move_entry(const std::filesystem::path& source,
                           const std::filesystem::path& destination_directory);

OperationResult copy_file_safely(const std::filesystem::path& source,
                                 const std::filesystem::path& destination);

// Uses the Windows shell's undo-capable recycle operation. If recycling fails,
// the function reports failure and never falls back to permanent deletion.
OperationResult move_to_recycle_bin(const std::filesystem::path& source);

}  // namespace aureon::filesystem
