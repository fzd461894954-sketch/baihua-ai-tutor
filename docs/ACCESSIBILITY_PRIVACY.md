# Accessibility Privacy

## What the permission is for

白话 AI uses macOS Accessibility access to read text that the current external
application already exposes in its focused window. This is STEP 2B's on-demand
debug foundation for validating whether visible text can be represented as a
structured snapshot.

The permission is not requested at app launch. When permission is missing, the
user must click **Allow reading the current AI window**, read the product
explanation, and click **Continue** before the macOS prompt is requested.

## When a read occurs

A read occurs only when the user clicks **Read Current Window** in Accessibility
Debug. There is no timer, background polling, live Accessibility observer, or
automatic read on an application switch.

The target is STEP 2A's `lastExternalApplication`, not 白话 AI itself. The reader
rejects its own bundle identifier or process identifier and rejects a stale or
terminated target process.

## What is read

From the target's focused window, the reader requests only:

- window title, role, and subrole;
- Accessibility role, subrole, title, value, description, help, and children;
- normalized text nodes, node/role counts, truncation state, and duration.

Traversal is bounded by depth, node, character, per-element messaging, and
overall request limits. Secure/password elements and their descendants are
skipped before their values or children are requested.

## What is not done

STEP 2B does not click, type, focus, select, scroll, move, resize, or otherwise
control another application. It does not use `AXObserver`, ScreenCaptureKit,
screenshots, Vision OCR, camera, or Photos. It does not classify a message as
user or AI content and does not send text to Tutor, TTS, or an AI API.

## Storage, network, clipboard, and logs

The snapshot exists only in memory and disappears when the app exits. STEP 2B
does not write the body to UserDefaults, a database, JSON, or a file, and does
not upload it.

OSLog contains only safe metadata: bundle identifier activation events,
snapshot node/character counts, truncation, duration, or a stable error name.
It never logs the snapshot body.

Debug builds display at most the first 3,000 characters. Copying that capped
debug snapshot to the clipboard requires an explicit second button click; no
automatic clipboard write occurs.

## Revoking access

The user can turn off 白话 AI under **System Settings → Privacy & Security →
Accessibility** at any time. The app refreshes trust state when it becomes
active and returns a friendly `permissionRequired` result when access is absent.
