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
- Windows Shell `IFileOperation` adapter explicitly requests `FOFX_RECYCLEONDELETE`. If the recycle operation fails, the adapter returns an error and never falls back to permanent deletion.
- Windows CI includes a disposable-file recycle-bin integration check on the ephemeral hosted runner.

## Deliberately not included yet

- ACL/security descriptor editing and full Windows error-code mapping.
- Cloud Files API sync-root registration, hydration or dehydration.
- Shell extensions, Explorer replacement or default-app hijacking.

Keep Windows Explorer available. Next native work should add a disposable-user-profile Cloud Files API integration harness and shell-compatible status/hydration behavior.

## Build

Requires Visual Studio 2022 C++ tools and CMake 3.25+.

```powershell
cmake -S windows-spike -B windows-spike/build -A x64
cmake --build windows-spike/build --config Release
ctest --test-dir windows-spike/build -C Release --output-on-failure
```
