This folder contains the generated change package for the AdGuard Home LuCI dashboard modifications.

Files included:
- CHANGELOG.md  : description of changes (bilingual)
- backup_and_pack.sh : on-router script to backup current files and apply uploaded files
- diff.patch : unified patch (if requested)

Usage:
1) Upload the contents of this folder to your router (e.g., using `scp`).
2) Run `sh backup_and_pack.sh` on router to backup and replace files.
3) If you want to compare upstream scripts manually, use a direct `curl` from the router or your workstation; this package no longer includes an automated fetch script.

