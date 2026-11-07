# AUREON for Windows — File Manager Specification

**Status:** Accepted product direction; specification baseline, not implemented
**Product role:** Preferred everyday Windows file manager and unified local/cloud workspace
**UI framework:** Flutter Windows desktop
**Native integration:** C++ with Win32/WinRT and supported Windows shell/Cloud Files APIs

## 1. Product decision

AUREON for Windows is not just a cloud-drive sync utility. It is intended to be the user's primary day-to-day file-management application, with the familiarity and task coverage of Windows File Explorer plus unified cloud accounts.

The interface should feel immediately familiar to Explorer users. A user should be able to perform routine local-file tasks without opening File Explorer, while also browsing and managing cloud-backed files from the same workspace.

**Important Windows boundary:** Windows does not provide a universal, supported switch that lets an ordinary third-party app replace every File Explorer surface. AUREON must not patch, kill or replace `explorer.exe`, hijack protected shell behavior or promise that Win+E and every OS surface can be redirected. AUREON can become the preferred user-launched file manager through supported associations and entry points; Windows Explorer remains available for desktop, taskbar and system compatibility.

## 2. Core layout

The default window uses an Explorer-familiar layout:

- **Top command area:** Back, Forward, Up, Refresh, New, Cut, Copy, Paste, Rename, Share, Delete and View controls, with context-sensitive availability.
- **Address/navigation bar:** Editable path/address field with breadcrumb navigation, path autocomplete and clear location identity.
- **Tabs:** Multiple locations in one window, tab restore, duplicate tab, close others and drag files between tabs.
- **Navigation pane:** Home, Quick Access/Favourites, Recent, Desktop, Downloads, Documents, Pictures, Music, Videos, This PC, drives, network locations, AUREON cloud accounts and pinned folders.
- **Main file surface:** Details, list, icons/grid and compact views; selectable columns; sort/group; multi-select; keyboard focus and accessible row semantics.
- **Optional preview/details pane:** File preview when supported, metadata, size, modified time, availability, provider/account and sync/verification state.
- **Status bar:** Item count, selection count/size, local/cloud status, transfer state and available disk space where relevant.

Layout panes must be resizable and their visibility remembered per user. Support high-DPI scaling, light/dark themes, keyboard-only navigation, screen readers and Windows text scaling.

## 3. Explorer-grade interactions

- Keyboard shortcuts for navigation, selection, copy/move, rename, delete, new folder, search, tabs and view changes. Use familiar Windows conventions where they do not conflict with system-reserved shortcuts.
- Context menus for files, folders, drives, cloud accounts and empty space; menu actions must reflect actual capabilities and permissions.
- Drag-and-drop within a folder, between tabs, between local and cloud locations, and to/from compatible applications. Clearly distinguish copy, move, upload, download and link operations.
- Clipboard integration for file copy/paste and path copy. Support safe cut/paste semantics and cancellation.
- Search by name and supported metadata, with location scope, filters and incremental results. Content search is a later capability and must respect E2E encryption limitations.
- File/folder properties, size calculation, timestamps, attributes, sharing state and actual provider/account details.
- Preview handlers only for supported and safe formats; never execute content just to preview it.
- Undo where the underlying operation can be reversed safely. For irreversible cloud deletion or remote changes, require clear confirmation and use recoverable trash where the provider supports it.
- Conflict handling for name collisions, changed remote versions, locked files and permission failures; show explicit choices rather than silently overwriting.

## 4. Local filesystem behavior

Use native Windows APIs for local filesystem operations rather than emulating a filesystem in Flutter. Cover:

- Drive and volume discovery, removable drives, UNC/network paths and mapped drives where accessible.
- Long paths, Unicode names, case behavior, reparse points and symbolic links with loop protection.
- File copy/move/rename/delete with progress, cancellation and collision handling.
- Recycle Bin behavior for ordinary local deletion; permanent deletion must be explicit.
- ACL/permission errors, read-only files, locked files, sharing violations and elevation boundaries.
- File associations, Open With and launch behavior using Windows-supported mechanisms.
- Atomic or recoverable operations where available; preserve data on interruption.

AUREON must never silently elevate privileges or bypass filesystem permissions.

## 5. Cloud workspace and Cloud Files integration

- Represent connected cloud accounts and their folders in the same navigation and search model as local locations, while clearly distinguishing cloud, local cache and hydrated content.
- Use Microsoft Cloud Files API for supported sync-root registration, placeholder files/directories, on-demand hydration, dehydration/free-up-space and pin/unpin behavior.
- Show per-item state: online-only, hydrating, available locally, pinned offline, uploading, downloading, verification pending, verified, conflict, unavailable or authentication required.
- Hydrate only on demand or by explicit pin/download policy; do not download the entire cloud inventory by default.
- Preserve provider folder hierarchy and native IDs. Derived AUREON categories are virtual views, not moves or renames.
- Respect provider-specific capabilities and quota policies. Do not pool accounts or shard files to evade quotas.
- AUREON transfer state and canonical location must reconcile with Cloud Files state; shell-visible placeholder metadata must not falsely claim a completed local file.

## 6. Data safety and deletion

The Windows client inherits AUREON's non-negotiable safety model:

- Upload success alone never authorizes source deletion.
- Never automatically delete local originals. Any cleanup must be separately enabled by the user, only after remote integrity verification and encryption/key-recovery checks, and only when Windows grants the required permission.
- Free-up-space/dehydration may remove only a verified local cloud cache/hydrated representation whose canonical remote object is confirmed. It must not remove unrelated local originals, staging files or the only known-good copy.
- A placeholder is not proof of a verified remote copy; retain explicit verification evidence.
- Interrupted transfers, offline state, expired credentials, provider quota exhaustion and conflicts preserve source data.
- Local Recycle Bin deletion and remote cloud deletion are separate operations with separate confirmation and undo/restore semantics.

## 7. Supported Windows integration strategy

Phase supported integrations rather than promising an unsafe total shell replacement:

1. AUREON app shortcut, Start menu entry and optional taskbar pin.
2. Optional launch at sign-in, off by default until user enables it.
3. File/folder associations only where Windows exposes a supported user-controlled association flow.
4. Open With, Send To and supported context-menu entry points.
5. Optional Explorer shell extension only after a separate stability, security, signing and Windows-version review.
6. Cloud Files sync-root registration for cloud placeholders and hydration.
7. Installer/uninstaller must register and clean up only AUREON-owned associations, context handlers and sync roots; never modify protected shell binaries or remove the Windows shell.

Do not promise a system-wide "default file manager" selector where Windows does not expose one. The product goal is that users can do their everyday file work in AUREON and launch it from their preferred entry points.

## 8. Shared architecture and parallel development

Shared contracts must be defined once and reused by Android and Windows:

- Stable file identity and version model.
- Provider account and capability model.
- Transfer Coordinator lifecycle and idempotency semantics.
- Encryption envelope and cross-platform test vectors.
- Canonical cloud location and reconciliation rules.
- No-auto-delete and verified-cleanup eligibility contract.
- Error taxonomy and sync/availability states.

Platform adapters remain native:
- Android: Kotlin, Room, SAF, DocumentsProvider and WorkManager.
- Windows: C++, Win32/WinRT, filesystem APIs and Cloud Files API.
- Shared UI/business contracts: Flutter/Dart where practical.

After shared contracts are frozen, Windows UI/native prototyping can proceed alongside Android work. Both platforms must pass shared contract tests plus their own OS-specific integration tests.

## 9. Windows acceptance criteria

- A user can navigate local drives, common folders, UNC locations and connected AUREON cloud accounts in one Explorer-familiar interface.
- Tabs, address/breadcrumb navigation, search, details/list/icon views, sort/group, context menus, preview and keyboard navigation work.
- Copy, move, rename, delete-to-Recycle-Bin, drag/drop and clipboard operations handle conflicts and interruption without silent data loss.
- Cloud placeholders hydrate on demand and expose correct offline/pinned/transfer/verification states.
- Free-up-space never removes a local original or unverified data.
- File/folder associations and shell entry points use supported Windows mechanisms and are user-controlled.
- AUREON works without disabling Windows Explorer or damaging desktop/taskbar/system surfaces.
- Installer, updater, signing, accessibility, performance and Windows-version compatibility pass release tests.

## 10. Deferred decisions

- Minimum supported Windows version and SDK baseline.
- Exact file-operation engine and long-path strategy.
- Shell extension scope and whether it is worth the stability cost.
- Whether a dedicated background sync service is needed.
- Installer/update/signing provider and release channel.
- Preview handler scope and supported formats.
- Default layout, theme and keyboard customization policy.
