# Working on IntPortal

Read `README.md` for the layout and the run commands, and `CONTEXT.md` for the app's terms. This file holds what an agent needs on top of them.

## Before you change anything

- The SIS login belongs to the user. Never type, store or ask for their SIS password or Apple ID. They run live SIS checks and phone installs themselves.
- Only the user's own account is in scope.
- UI work follows `PRODUCT.md` and `DESIGN.md`, plus the direction contract at the top of `src/app.html`. LAR speaks in the app's copy; Isko never does.

## The loop for each change

1. Branch from `main`, or stack on the open branch when the change depends on it.
2. Write the failing test first where a cheap one exists: `crates/intportal-core` tests for logic, vitest (`src/lib/*.test.ts`) for pure TypeScript. Run it and see it fail for the right reason.
3. Make the change, then run:

   ```bash
   pnpm check && pnpm test
   cargo test -p intportal-core
   cargo clippy -p intportal --all-targets -- -D warnings
   ```

4. UI or native changes: run `scripts/sim.sh <simulator name or id>`, then check with screenshots (`xcrun simctl io <id> screenshot <file>`). Afterwards discard the project churn the Tauri CLI leaves: `git checkout -- src-tauri/gen/apple/intportal.xcodeproj/project.pbxproj`.
5. Run `scripts/disk.sh` and put the sizes in the PR. Write the PR in plain sentences: what changed for the student, how it works, the test evidence, and what was not checked.

## Merging

The user merges, or says to. Merge stacked PRs bottom-up. Before you delete a merged base branch, point the next PR at `main` with `gh pr edit <n> --base main`. Deleting the base first closes that PR instead of retargeting it.

## iOS specifics

- `src-tauri/gen/apple/project.yml` is the source of truth for Info.plist keys and entitlements. After editing it, run `cd src-tauri/gen/apple && APPLE_DEVELOPMENT_TEAM= INTPORTAL_APP_GROUP=false xcodegen generate`. Commit `project.yml` and `Info.plist`, not the pbxproj churn.
- The signing team never goes in git. `scripts/phone.sh` takes it from `APPLE_DEVELOPMENT_TEAM`.
- Swift plugin commands: a command named `sync_classes` runs the Swift method `syncClasses`. A plugin's rejection reaches JavaScript as an object with `message`, not a string.
- Desktop `cargo` builds never compile the Swift plugins. Only a simulator build proves them.
- Calendar on the simulator: `xcrun simctl privacy <id> grant calendar ph.intportal.app`.
- The store is SQLCipher-encrypted per student, with its key in the keychain. A build without encryption can't open an encrypted store; on a simulator, move `Library/Application Support/ph.intportal.app/account-*` aside.

## Storage

Keep one Cargo workspace. Never set `debug = false` for dependencies, because swift-rs then hides the plugins' `@_cdecl` symbols and the iOS link fails. Don't delete simulators or worktrees without asking.
