#include "aureon/filesystem.hpp"

#include <cstdlib>
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
    fs::create_directories(root / "Move Target");
    fs::create_directories(root / "Copy Target");

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
    ok &= require(all.size() == 5, "enumerates all five entries");
    ok &= require(!all.empty() && all.front().is_directory,
                  "directories sort before files");
    ok &= require(!all.empty() && all.front().name == L"Copy Target",
                  "sorts directory names deterministically");

    const auto visible = aureon::filesystem::enumerate(
        root, aureon::filesystem::EnumerateOptions{false, false});
    ok &= require(visible.size() == 4, "hidden entries can be excluded");

    const auto nested = aureon::filesystem::enumerate(root / "Nested Folder");
    ok &= require(nested.size() == 1, "enumerates nested directory");
    ok &= require(!nested.empty() && nested.front().name == L"nested.bin",
                  "preserves nested file name");
    ok &= require(!nested.empty() && nested.front().size_bytes == 5,
                  "reads file size");

    const auto renamed = aureon::filesystem::rename_entry(root / "hello.txt", L"renamed.txt");
    ok &= require(renamed.success, "renames a file");
    ok &= require(fs::exists(root / "renamed.txt"), "renamed file exists");
    ok &= require(
        aureon::filesystem::rename_entry(root / "renamed.txt", L"Nested Folder").error ==
            aureon::filesystem::OperationError::destination_exists,
        "refuses to overwrite an existing entry");
    ok &= require(
        aureon::filesystem::rename_entry(root / "renamed.txt", L"..\\escape").error ==
            aureon::filesystem::OperationError::destination_invalid,
        "rejects path traversal in a rename name");

    const auto moved = aureon::filesystem::move_entry(
        root / "renamed.txt", root / "Move Target");
    ok &= require(moved.success, "moves a file into an existing directory");
    ok &= require(fs::exists(root / "Move Target" / "renamed.txt"),
                  "moved file is present at destination");

    const auto copied = aureon::filesystem::copy_file_safely(
        root / "Move Target" / "renamed.txt", root / "Copy Target" / "copy.txt");
    ok &= require(copied.success, "copies a regular file");
    ok &= require(fs::exists(root / "Copy Target" / "copy.txt"),
                  "copied file exists");
    ok &= require(fs::exists(root / "Move Target" / "renamed.txt"),
                  "copy preserves original source");
    ok &= require(copied.sha256_hex.size() == 64,
                  "returns a 64-character SHA-256 digest");
    ok &= require(
        aureon::filesystem::copy_file_safely(
            root / "Move Target" / "renamed.txt", root / "Copy Target" / "copy.txt").error ==
            aureon::filesystem::OperationError::destination_exists,
        "copy refuses to overwrite an existing destination");

    ok &= require(
        aureon::filesystem::move_to_recycle_bin(root / "missing-for-recycle-test.txt").error ==
            aureon::filesystem::OperationError::source_missing,
        "recycle operation rejects a missing source without touching the shell");

    if (std::getenv("AUREON_RUN_CLOUDFILES_INTEGRATION") != nullptr) {
        const auto sync_root = root / "AUREON Cloud Root";
        fs::create_directories(sync_root);
        const auto registration = aureon::filesystem::register_sync_root(sync_root);
        ok &= require(registration.success, "registers an AUREON Cloud Files sync root");
        if (registration.success) {
            const auto unregistration =
                aureon::filesystem::unregister_sync_root(sync_root);
            ok &= require(unregistration.success, "unregisters the AUREON Cloud Files sync root");
        }
    }

    if (std::getenv("AUREON_RUN_RECYCLE_BIN_INTEGRATION") != nullptr) {
        const auto disposable = root / "disposable-recycle-test.txt";
        {
            std::ofstream file(disposable, std::ios::binary);
            file << "Disposable AUREON recycle-bin integration fixture";
        }
        const auto recycled = aureon::filesystem::move_to_recycle_bin(disposable);
        ok &= require(recycled.success, "moves a disposable test file to the recycle bin");
        ok &= require(!fs::exists(disposable),
                      "recycled test file is no longer at its original path");
    }

    fs::remove_all(root, ec);
    return ok ? 0 : 1;
}
