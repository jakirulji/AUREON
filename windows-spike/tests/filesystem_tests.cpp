#include "aureon/filesystem.hpp"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <string>

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

    const auto all = aureon::filesystem::enumerate(root);
    assert(all.size() == 3);
    assert(all.front().is_directory);
    assert(all.front().name == L"Nested Folder");

    const auto visible = aureon::filesystem::enumerate(
        root, aureon::filesystem::EnumerateOptions{false, false});
    assert(visible.size() == 2);

    const auto nested = aureon::filesystem::enumerate(root / "Nested Folder");
    assert(nested.size() == 1);
    assert(nested.front().name == L"nested.bin");
    assert(nested.front().size_bytes == 5);

    fs::remove_all(root, ec);
    return 0;
}
