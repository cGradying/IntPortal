# Releasing

Each step ends in something you can check. A release goes public only when the owner says "publish".

1. **Checks.** `pnpm check && pnpm test && cargo test --workspace && cargo clippy -p intportal --all-targets -- -D warnings`, then the three lints: `node scripts/commands-check.mjs`, `node scripts/style-lint.mjs`, `node scripts/tap-targets.mjs`. CI runs the same on the release PR.
2. **Version.** `scripts/version.sh 0.4.0` sets it in every file that carries it.
3. **Changelog.** Turn `## Unreleased` in `CHANGELOG.md` into `## 0.4.0 (date)`, with one line per change a student notices and a "Known gaps" list. Open a `release/0.4.0` PR and merge it on green CI.
4. **Phone check.** On main: `scripts/emu.sh` on the emulator, and `APPLE_DEVELOPMENT_TEAM=<team> scripts/phone.sh` on the owner's iPhone. A free Apple team's install stops opening after 7 days; run it again to renew.
5. **Build and draft.** Write the release notes to a file, then `scripts/release.sh notes.md`. It builds the signed Android APK and bundle (the key lives in `~/.config/intportal`, see [android.md](android.md)) and the unsigned iPhone app, and makes a **draft** release with:
   - `IntPortal-<version>.apk` and `IntPortal.apk`, the same file. The website links `releases/latest/download/IntPortal.apk`, so it always gets the newest.
   - `IntPortal-<version>.aab`, for a store later.
   - `IntPortal-<version>-unsigned.ipa` and `IntPortal-unsigned.ipa`, for AltStore or SideStore.
   The script prints each file's SHA-256 for the notes.
6. **Desktop.** Actions › Desktop › Run workflow with `release` set to the tag (`android-v<version>`). It adds the dmg, msi, AppImage and deb to the draft.
7. **Publish.** Only on the owner's "publish": `gh release edit android-v<version> --draft=false`. A full release (not a pre-release) is what `releases/latest` and the website pick up.
8. **After.** Install the APK from the release page on a phone over the old version, and check that it keeps the data. Close the release's issues.

The unsigned iPhone app can also be built in CI without a Mac: run the iOS workflow by hand (Actions › iOS › Run workflow) and take the `intportal-unsigned-ipa` artifact.
