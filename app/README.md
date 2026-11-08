# AUREON App

This directory contains the shared Flutter application layer. Android and Windows host projects are generated in CI while platform integration is being developed.

## Current scope

- Responsive AUREON navigation and dark visual system.
- Local folder browsing through Android Storage Access Framework (SAF) and the Windows native folder picker.
- Selected folder bookmarks persist across launches. Android's persisted SAF read grant remains the authority to access the folder.
- In-folder name search, sorting by name/size/modified time/file type, hidden-entry filtering, file size and modified-time metadata.
- File open hand-off to the Android system viewer or Windows' default associated application; Windows validates root containment.
- Verified same-root file copy, safe parent-folder move, and Trash/restore flows. Android uses provider-native Trash when supported or an AUREON-managed folder; Windows uses the Recycle Bin. No silent permanent-delete fallback.
- AUREON Master Account email/password authentication via Firebase Identity Toolkit REST; secure refresh-token persistence, automatic cold-start restoration, token refresh, password reauthentication and local sign-out. Passwords and ID tokens are not persisted.
- Shared Discovery Registry client and local public backend-profile cache. New devices resolve the user's Firebase/Worker config by Account Recovery ID. Firebase issuer + UID binding is checked after interactive login and after cold-start session restoration.
- If Registry verification is temporarily unavailable, the in-memory session is locked while the rotated refresh token is retained for a later retry. A definitive account-binding mismatch signs the device out.
- Registered Account Recovery IDs can be copied or displayed as QR codes. The QR contains only the locator; the new device must still authenticate with the matching Firebase Master Account. Android can scan the QR directly from the new-device setup screen; Windows and unsupported platforms can enter the Account Recovery ID manually. Deep-link import is not implemented.
- Cloudflare credential-vault sync/recovery UI connected to the HTTPS client. It requires compile-time Firebase and Worker URL configuration plus a deployed Worker/D1 database.
- Storage overview and recent-file cards still contain sample data.

## Validation

The app validation workflow runs Flutter dependency resolution, static analysis, widget tests and platform compilation for Android and Windows. It does **not** upload or retain APK/EXE artifacts. Final installable builds will be produced once the agreed implementation scope is complete. Firebase auth, encrypted vault sync idempotency and stale-remote protection are exercised with fake transports in CI; no production Firebase or Cloudflare endpoint is contacted.

The shared Registry Worker source is in `../backend/discovery-registry`. It still requires owner-controlled Cloudflare D1 + Rate Limiting binding configuration and deployment; adding code to GitHub does not deploy it.

## Important limitations

The Files screen supports verified copy, safe parent moves and Trash/restore, but not yet file-content preview inside AUREON. Provider OAuth account connection, provider file upload/download and cross-provider sync are not implemented yet. Android may report that no compatible viewer is installed for a particular file type. Storage overview and recent-file cards still use sample data. AUREON is not yet a finished replacement for Windows File Explorer.

## Local validation

Generate the desired platform scaffolding, then run:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug` or `flutter build windows --release` when platform compilation is needed.

## Owner configuration

See [Firebase and Cloudflare owner setup](../docs/OWNER-SETUP-FIREBASE-CLOUDFLARE.md) for the Spark/Workers/D1 setup and compile-time configuration.
