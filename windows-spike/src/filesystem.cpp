#include "aureon/filesystem.hpp"

#include <algorithm>
#include <system_error>

namespace aureon::filesystem {

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

}  // namespace aureon::filesystem
