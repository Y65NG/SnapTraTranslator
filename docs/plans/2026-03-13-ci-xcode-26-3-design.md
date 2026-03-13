# CI Xcode 26.3 Alignment Design

**Goal:** Make the GitHub Actions release build use the same Xcode major version as local development so SwiftUI and AppKit default control styling matches more closely between CI-built DMG installs and local Xcode runs.

## Problem

- The release workflow currently pins CI to `Xcode 16.2`.
- Local development is running with `Xcode 26.3`.
- The settings window uses native `TabView`, `Picker(.menu)`, `Toggle(.switch)`, and `NSWindow` presentation, so visual styling depends on the linked SDK and runtime compatibility behavior rather than app-specific styling code.
- This creates visible control-style differences between the DMG produced by CI and the app launched directly from Xcode.

## Product Decision

Align the release workflow to `Xcode 26.3` while keeping the runner on `macos-15`.

## Scope

- Update the release workflow to select `/Applications/Xcode_26.3.app`.
- Add an explicit version check step so build logs record the effective Xcode version.
- Keep the rest of the packaging, signing, and notarization flow unchanged.

## Non-Goals

- Do not change the app UI code.
- Do not migrate the workflow to `macos-26` in this change.
- Do not remove explicit Xcode selection and rely on the runner default.

## Options Considered

### 1. Recommended: Keep `macos-15`, switch to `Xcode 26.3`

- Smallest possible change.
- Matches the local Xcode toolchain that is currently used for development.
- Preserves the existing runner family and avoids unrelated CI changes.

### 2. Move both runner and Xcode to macOS 26

- Potentially even closer to the local machine environment.
- Increases the change surface and operational risk for the release workflow.
- Not required to solve the immediate styling mismatch.

### 3. Follow the runner default Xcode

- Lowest maintenance.
- Removes reproducibility from release builds.
- Risks future visual or build behavior changing without a repository diff.

## Recommended Approach

Modify only the release workflow:

1. keep `runs-on: macos-15`
2. change the explicit `xcode-select` target from `Xcode_16.2.app` to `Xcode_26.3.app`
3. log `xcodebuild -version` after selection

This keeps the release build deterministic while aligning it with the local development toolchain.

## Verification

- Run the release workflow and confirm the log shows `Xcode 26.3`.
- Build a DMG from CI and compare the settings window against a local Xcode 26.3 run.
- Confirm signing and notarization continue to work unchanged.

## Risks

- `macos-15` runner image contents can change over time, so the workflow still depends on GitHub-hosted runner availability for `Xcode 26.3`.
- A newer Xcode can surface unrelated compile warnings or behavioral changes in future builds.
- Matching Xcode reduces UI differences, but it does not guarantee identical runtime state such as TCC permission records or `UserDefaults` containers.
