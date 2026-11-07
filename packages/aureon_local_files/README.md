# AUREON Local Files Plugin

Provides a user-selected local folder browser on Android (Storage Access Framework) and Windows (native filesystem).

Current supported operations:
- Pick and persist a user-authorized folder root.
- List child entries and metadata; open files with the platform's associated viewer.
- Create a folder and rename a selected file or folder.
- Reject names containing path separators, reject out-of-root Windows paths, and refuse name collisions rather than silently overwriting.
- Android requests persistable read/write access through the system picker; individual document providers may reject rename or folder creation, which is surfaced as unsupported.

No delete, copy, move, cloud transfer, or automatic cleanup operation is exposed yet. A failed or unsupported operation leaves the existing item untouched.