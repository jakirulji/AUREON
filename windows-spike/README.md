# AUREON Windows Native Filesystem Spike

This is an A0 native foundation, not a complete file manager and not a Cloud Files API provider.

## Included

- C++20 filesystem enumeration using wide-character paths.
- Directory-first deterministic ordering and file metadata.
- Explicit hidden-entry and directory-symlink options.
- Safe same-volume rename and move operations that refuse destination overwrite.
- Regular-file copy through a temporary sibling; source is preserved and existing destinations are not overwritten.
- Copy integrity check using Windows CNG SHA-256: hash source before copy, hash it again after copy, hash the temporary destination, and promote only if all digests match.
- A source that changes while being copied causes the temporary destination to be discarded; the original is never deleted.
- Tests cover enumeration, rename, move, copy, overwrite rejection, traversal-name rejection and SHA-256 digest output.

## Deliberately not included yet

- Delete/recycle-bin integration (normal UI deletion must use the Windows shell's undo-capable operation path, never raw permanent deletion).
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
