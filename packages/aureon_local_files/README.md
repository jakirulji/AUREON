# AUREON Local Files Plugin

Native, read-only folder selection and directory enumeration for the first local-files vertical slice.

## Android

- Uses the system Storage Access Framework folder picker (ACTION_OPEN_DOCUMENT_TREE).
- Requests and persists read-only URI permission; no broad storage permission is requested.
- Enumerates child documents through DocumentsContract, preserving provider document IDs for nested navigation.
- Handles revoked grants and provider listing failures as explicit errors.

## Windows

- Uses the native Windows folder picker (IFileDialog).
- Enumerates directory entries with std::filesystem, uses UTF-8 at the Flutter boundary, and does not follow directory symlinks.
- Canonicalizes the selected root and requested parent before listing to prevent traversal outside the user-selected root.

## Current boundary

This plugin only picks folders and lists metadata. It does not open, modify, rename, move, copy, delete, upload or download files. Folder selection metadata is currently held in the running UI state; durable root bookmarks and permission-recovery UX are a later step. Native platform behavior still requires CI compilation and physical-device/desktop smoke testing.
