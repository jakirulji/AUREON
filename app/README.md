# AUREON App

This directory contains the shared Flutter application layer. Android and Windows host projects are generated in CI while platform integration is being developed.

## Current scope

- Responsive AUREON navigation and dark visual system.
- Local folder browsing through Android Storage Access Framework (SAF) and the Windows native folder picker.
- Selected folder bookmarks persist across launches. Android's persisted SAF read grant remains the authority to access the folder.
- In-folder name search, sorting by name/size/modified time/file type, hidden-entry filtering, file size and modified-time metadata.
- File open hand-off to the Android system viewer or Windows' default associated application; Windows validates root containment.
- Verified same-root file copy, safe parent-folder move, and Trash/restore flows. Android uses provider-native Trash when supported or an AUREON-managed folder; Windows uses the Recycle Bin. No silent permanent-delete fallback.
- AUREON Master Account email/password authentication via Firebase Identity Toolkit REST; email verification, saved refresh-token restoration, token refresh, password reauthentication and local sign-out. Passwords and ID tokens are not persisted.
- AUREON Master Accounts use the single official Firebase project configured in the app; users do not create or enter backend profiles.
- Cloudflare credential-vault sync/recovery uses the shared AUREON Worker/D1 service. The Worker derives the owner UID from a verified Firebase ID token and scopes vault, challenge, cooldown and audit records to that UID.
- In-app Google Drive OAuth owner guide explains the one-time AUREON Google Cloud setup, Android/Windows client registrations, PKCE, scope/verification requirements and how encrypted provider credentials are intended to be stored under each user's isolated account scope in the shared AUREON backend.
- Storage overview and recent-file cards still contain sample data.

## Validation

The app validation workflow runs Flutter dependency resolution, static analysis, widget tests and platform compilation for Android and Windows. It does **not** upload or retain APK/EXE artifacts. Final installable builds will be produced once the agreed implementation scope is complete.

## Important limitations

The Files screen supports verified copy, safe parent moves and Trash/restore, but not yet file-content preview inside AUREON. Provider OAuth account connection, authorization callback/token exchange, shared-backend provider-token synchronization, provider file upload/download and cross-provider sync are not implemented yet. The OAuth guide is documentation only. The separate central backend-recovery registry and Recovery-Key-based backend-profile restore flow are also not implemented; current vault recovery restores an existing vault from the shared AUREON Worker; backend discovery is not required. Android may report that no compatible viewer is installed for a particular file type. Storage overview and recent-file cards still use sample data. AUREON is not yet a finished replacement for Windows File Explorer.

## Local validation

Generate the desired platform scaffolding, then run:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug` or `flutter build windows --release` when platform compilation is needed.
\n## Owner configuration\n\nSee [Firebase and Cloudflare owner setup](../docs/OWNER-SETUP-FIREBASE-CLOUDFLARE.md) for the Spark/Workers/D1 setup and compile-time configuration.\n