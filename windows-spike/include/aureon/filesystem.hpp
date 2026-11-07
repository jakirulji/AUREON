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
    io_error,
};

struct OperationResult {
    bool success{};
    OperationError error{OperationError::none};
    std::filesystem::path resulting_path;
};

std::vector<Entry> enumerate(const std::filesystem::path& directory,
                             const EnumerateOptions& options = {});

// Rename within the same parent directory. The destination is never overwritten.
OperationResult rename_entry(const std::filesystem::path& source,
                             const std::wstring& new_name);

// Move into an existing directory. Cross-volume moves fail safely; no copy/delete fallback.
OperationResult move_entry(const std::filesystem::path& source,
                           const std::filesystem::path& destination_directory);

// Copy a regular file through a temporary sibling and atomic rename where supported.
// Source is preserved and existing destinations are never overwritten.
OperationResult copy_file_safely(const std::filesystem::path& source,
                                 const std::filesystem::path& destination);

}  // namespace aureon::filesystem
