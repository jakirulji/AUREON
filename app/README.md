# AUREON App Preview

This directory contains the first cross-platform Flutter UI shell. Android and Windows platform folders are generated in CI so this source remains a shared Flutter layer.

## Current scope

- Responsive AUREON navigation and dark visual system.
- Storage overview, recent-file layout and prototype status notice.
- CI creates a debug Android APK and a Windows release bundle for visual review.

## Important limitation

This is a UI preview only. File rows and storage cards are explicitly sample data. No real filesystem browsing, SAF access, Windows filesystem adapter connection, cloud OAuth, uploads, downloads or sync are wired into this UI yet. Do not use it to manage real files.

## Local build

Generate the platform scaffolding, then run flutter pub get, flutter test, flutter build apk --debug or flutter build windows --release.
