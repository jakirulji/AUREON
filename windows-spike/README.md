# AUREON Windows Native Filesystem Spike

This is an A0 native foundation, not a complete file manager and not a Cloud Files API provider.

## Included

- C++20 filesystem enumeration using wide-character paths.
- Directory-first deterministic ordering and file metadata.
- Explicit hidden-entry and directory-symlink options.
- Safe same-volume rename and move operations that refuse destination overwrite.
- Regular-file copy through a temporary sibling followed by rename; source is preserved and existing destinations are not overwritten.
- Move rejects symlink sources and moving a directory into itself.
- Cross-volume move does not silently fall back to copy-and-delete; it fails safely.
- Temporary-directory tests cover enumeration, rename, move, copy, overwrite rejection and traversal-name rejection.

## Deliberately not included yet

- Delete/recycle-bin integration (must use the Windows shell's undo-capable operation path, never raw permanent deletion for normal UI actions).
- ACL/security descriptor editing and full Windows error-code mapping.
- Cloud Files API sync-root registration, hydration or dehydration.
- Shell extensions, Explorer replacement or default-app hijacking.

Keep Windows Explorer available. The next native increment should add an undo-capable recycle-bin adapter and a disposable-user-profile Cloud Files API integration harness.

## Build

Requires Visual Studio 2022 C++ tools and CMake 3.25+.

```powershell
cmake -S windows-spike -B windows-spike/build -A x64
cmake --build windows-spike/build --config Release
ctest --test-dir windows-spike/build -C Release --output-on-failure
```
