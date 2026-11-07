# AUREON Local Files Plugin

Provides a user-selected local folder browser on Android (Storage Access Framework) and Windows (native filesystem).

Supported operations:
- Pick and persist a user-authorized folder root.
- List child entries and metadata; open files with the platform's associated viewer.
- Create folders and rename selected files or folders.
- Copy regular files within the selected root, refusing existing destination names.
- Move files or folders one level to the parent folder using the platform's native move operation; destination collisions are rejected and each move requires user confirmation.
- Windows can move selected files/folders to the system Recycle Bin through IFileOperation with FOFX_RECYCLEONDELETE; source/root validation and explicit UI confirmation are required.
- Android moves supported SAF documents into a hidden `.AUREON Trash` folder inside the user-selected root using `DocumentsContract.moveDocument`; it never substitutes a copy/delete sequence. The Files screen hides this reserved folder and exposes a Trash view with Restore and separately confirmed permanent deletion. Original parent metadata is stored locally by AUREON.
- Verify file copies with SHA-256 before finalizing. Android streams to a temporary SAF document and reads it back; Windows hashes source before/after and the temporary destination using BCrypt.
- Reject out-of-root Windows paths, symbolic links for copy, and invalid leaf names.
- Surface unsupported SAF provider operations instead of silently falling back.

Copy never removes or changes the source. Failed copies remove only the temporary object created by that operation where the provider permits. Directory copy and cloud transfer are not implemented yet. Android SAF providers do not expose a universal Trash API. AUREON therefore uses a reserved in-root Trash folder and native provider move when supported; if the provider cannot create or move into it, the operation fails without deleting the source. Permanent deletion is a separate explicit user action. Windows explicitly requests recycle semantics; if the system cannot confirm recycling, AUREON reports failure and never falls back to permanent deletion.
