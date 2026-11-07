#include "aureon/filesystem.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace {
bool require(bool condition, const char* message) {
    if (!condition) std::cerr << "FAIL: " << message << '\n';
    return condition;
}
}

int main() {
    namespace fs = std::filesystem;
    const auto root = fs::temp_directory_path() / "aureon-native-fs-test";
    std::error_code ec;
    fs::remove_all(root, ec);
    fs::create_directories(root / "Nested Folder");

    {
        std::ofstream file(root / "hello.txt", std::ios::binary);
        file << "AUREON";
    }
    {
        std::ofstream file(root / "Nested Folder" / "nested.bin", std::ios::binary);
        file << "12345";
    }
    {
        std::ofstream file(root / ".hidden", std::ios::binary);
        file << "hidden";
    }

    bool ok = true;
    const auto all = aureon::filesystem::enumerate(root);
    ok &= require(all.size() == 3, "enumerates all three entries");
    ok &= require(!all.empty() && all.front().is_directory,
                  "directories sort before files");
    ok &= require(!all.empty() && all.front().name == L"Nested Folder",
                  "preserves directory name");

    const auto visible = aureon::filesystem::enumerate(
        root, aureon::filesystem::EnumerateOptions{false, false});
    ok &= require(visible.size() == 2, "hidden entries can be excluded");

    const auto nested = aureon::filesystem::enumerate(root / "Nested Folder");
    ok &= require(nested.size() == 1, "enumerates nested directory");
    ok &= require(!nested.empty() && nested.front().name == L"nested.bin",
                  "preserves nested file name");
    ok &= require(!nested.empty() && nested.front().size_bytes == 5,
                  "reads file size");

    fs::remove_all(root, ec);
    return ok ? 0 : 1;
}
