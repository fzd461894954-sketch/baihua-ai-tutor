# Accessibility Privacy

## What the permission is for

白话 AI uses macOS Accessibility access to read text that the current external
application already exposes in its focused window. STEP 2B is the on-demand
snapshot foundation; STEP 2C adds a separately started live watch for one locked
external process. STEP 2D adds local normalization, revision, and semantic
stability processing after a snapshot; it requests no additional permission.

The permission is not requested at app launch. When permission is missing, the
user must click **Allow reading the current AI window**, read the product
explanation, and click **Continue** before the macOS prompt is requested.

## When a read occurs

A STEP 2B read occurs only when the user clicks **Read Current Window** in
Accessibility Debug. STEP 2C stays off until the user clicks **开始实时跟随**.
Once started, its event-driven observer may request bounded snapshots for its
one locked target PID, subject to a 0.9-second minimum interval, a 0.6-second
trailing check, and one-reader singleflight. There is no timer-based polling,
automatic start, or automatic retarget on an application switch.

The target is STEP 2A's `lastExternalApplication`, not 白话 AI itself. The reader
rejects its own bundle identifier or process identifier and rejects a stale or
terminated target process. A live session records the target PID at start;
switching to Safari, Chrome, or any other app pauses it rather than monitoring
that new app. A target process exit, permission loss, or same-bundle PID
replacement safely stops the session.

## What is read

From the target's focused window, the reader requests only:

- window title, role, and subrole;
- Accessibility role, subrole, title, value, description, help, and children;
- normalized text nodes, node/role counts, truncation state, and duration.

Traversal is bounded by depth, node, character, per-element messaging, and
overall request limits. Secure/password elements and their descendants are
skipped before their values or children are requested.

## What is not done

STEP 2B/2C do not click, type, focus, select, scroll, move, resize, or otherwise
control another application. STEP 2C uses `AXObserver` only to observe the
locked application's root notifications; its callback records lightweight event
metadata and never performs a full text traversal. Neither step uses
ScreenCaptureKit, screenshots, Vision OCR, camera, or Photos. Neither classifies
a message as user or AI content or sends text to Tutor, TTS, or an AI API.
The Semantic Buffer detects only stability boundaries and does not summarize or
interpret content.

## Storage, network, clipboard, and logs

The snapshot exists only in memory and disappears when the app exits. STEP 2C
keeps only the latest body and its current revision metadata in memory; neither
step writes the body to UserDefaults, a database, JSON, or a file, and neither
uploads it. No snapshot history is retained or persisted.

STEP 2D keeps one current normalized baseline, one latest revision, and one
bounded pending Semantic Buffer. Emitted `SemanticChunk` bodies are delivered as
events and are not archived by the Context layer. Stop and other session-clearing
exits cancel the pending task and remove all pending semantic text.

OSLog contains only safe metadata: bundle identifier activation events,
snapshot node/character counts, truncation, duration, permission boolean,
target PID/bundle, observer creation/registration result codes, or a stable
error name. It never logs snapshot body text or the content fingerprint.

Debug builds display at most the first 3,000 characters. A live body stays hidden
until **查看最新 Snapshot** is clicked; copying a capped manual debug snapshot
requires a separate explicit button click. No automatic clipboard write occurs.
Semantic Buffer Debug also hides its pending body until **查看当前 Buffer** is
clicked and never offers previously emitted chunks for display.

## Revoking access

The user can turn off 白话 AI under **System Settings → Privacy & Security →
Accessibility** at any time. The app refreshes trust state before a snapshot and
when a paused live session resumes. A detected loss moves Live Watch to
`permissionRequired`, unregisters its observer, and cancels its pending read.
