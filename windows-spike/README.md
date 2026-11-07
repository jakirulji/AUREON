# AUREON Windows Native Filesystem Spike

This is the first Windows-native foundation, not a complete file manager and not a Cloud Files API provider.

## Included

- C++20 filesystem enumeration using wide-character paths.
- Directory-first deterministic ordering.
- File size and last-write metadata where available.
- Explicit hidden-entry and directory-symlink options.
- Permission-denied entries are skipped without aborting the entire listing.
- Temporary-directory tests for nested folders, file sizes and hidden entries.

## Deliberately not included yet

- File mutation, rename, move, delete or recycle-bin operations.
- ACL/security descriptor editing.
- Reparse-point traversal by default.
- Cloud Files API sync-root registration, hydration or dehydration.
- Shell extensions, Explorer replacement or default-app hijacking.

The next Windows increment should add safe metadata/property operations and path/error mapping, then a disposable-user-profile Cloud Files API integration harness. Keep Windows Explorer available.

## Build

Requires Visual Studio 2022 C++ tools and CMake 3.25+.

```powershell
cmake -S windows-spike -B windows-spike/build -A x64
cmake --build windows-spike/build --config Release
ctest --test-dir windows-spike/build -C Release --output-on-failure
```
