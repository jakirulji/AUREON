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

std::vector<Entry> enumerate(const std::filesystem::path& directory,
                             const EnumerateOptions& options = {});

}  // namespace aureon::filesystem
