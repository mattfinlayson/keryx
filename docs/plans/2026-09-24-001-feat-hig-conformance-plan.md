---
title: "feat: HIG conformance and visual state for Keryx interfaces"
type: feat
status: completed
date: 2026-09-24
origin: docs/brainstorms/2026-09-24-hig-conformance-requirements.md
---

# HIG Conformance and Visual State for Keryx Interfaces

## Summary

Bring the menubar icon, menu, Settings window, and notifications into HIG conformance and add visual state — SF Symbol template icon with unread badge, menu item icons, a last-file preview, notification click-to-open, sectioned Settings, and a release-bundle app icon. All presentation work stays in the macOS shell; the only core change is a testable latest-entry accessor.

---

## Problem Frame

Keryx renders its menubar icon as emoji text, its settings as an ungrouped control stack, and its notifications as dead-ends on click (see origin: docs/brainstorms/2026-09-24-hig-conformance-requirements.md, Problem Frame). This plan resolves those gaps at the implementation level while preserving the brainstorm's architecture decision: native NSMenu, no popover.

---

## Requirements

- R1. Menubar icon is a monochrome template image (SF Symbol tray family), tinted automatically by the system; no emoji.
- R2. Unread count is visual state on/beside the icon, not text concatenation after an emoji.
- R3. Menu items carry SF Symbol icons (used sparingly); unseen marker moves from text prefix to an accent-colored symbol in the item's image slot.
- R4. Menu shows a last-activity preview: newest file name + relative timestamp, refreshed on state change.
- R5. Menu includes an About item (app name + version).
- R6. Clicking a notification opens the file through the existing opener-resolution chain (extension rule → `*` rule → env override → OS default) and marks it read.
- R7. Multi-file notifications open the most recent file on click; the rest stay unread.
- R8. Settings grouped into labeled sections (Inbox, Visibility, Opening files, General) with a consistent label column; fixed size and live-apply preserved.
- R9. Opener-rule trash buttons have per-rule accessibility labels ("Remove rule for md").
- R10. Settings footer shows app name and version.
- R11. Release bundle includes a generated app icon.

**Origin actors:** A1 (knowledge worker), A2 (screen-reader user)
**Origin flows:** F1 (new file arrives → user engages), F2 (user checks the menubar)
**Origin acceptance examples:** AE1 (covers R1, R2), AE2 (covers R6, R7), AE3 (covers R4), AE4 (covers R8, R9), AE5 (covers R5)

---

## Scope Boundaries

- No popover or custom-view replacement of the menu (origin decision).
- No multiple inboxes, folder trees, or file-content previews in the menu.
- No settings tabs/toolbar — sections within the single window.
- No notarization work (tracked in issue #1).
- No hand-designed icon art — generated glyph only.
- No refactor of the Settings window's programmatic stack-view layout mechanism — sections are added within it.

---

## Context & Research

### Relevant Code and Patterns

- `Sources/KeryxApp/main.swift` — `AppDelegate.render()` rebuilds the menu on every state change; the icon, menu items, preview, and About item all land here.
- `Sources/KeryxApp/UserNotifier.swift` — already owns `UNUserNotificationCenter`; tap handling extends this class with the delegate protocol it already conforms to.
- `Sources/KeryxApp/LaunchAtLogin.swift` / `SettingsWindow.swift` — established pattern for small macOS-only app-shell units guarded by `#if os(macOS)`.
- `Sources/KeryxKit/InboxState.swift` — entries are kept sorted newest-first; the latest entry is the first entry.
- `.github/workflows/release.yml` — package step already assembles `Keryx.app` and runs on a macOS runner with AppKit available; icon generation slots into that step.
- `Package.swift` — macOS 15+ platform minimum, so all SF Symbols used (tray, tray.full, gear, folder, power, doc.badge, xmark) are guaranteed present.

### External References

- Bjango, "Designing macOS menu bar extras" — 22pt working area, 16×16pt icon weight, template-image rules, opacity conventions.
- Apple HIG: The menu bar / menu bar extras; NSStatusItem documentation (button with image + title).

---

## Key Technical Decisions

- **Badge via symbol swap + attributed count text** (origin R2 deferred question): the status-bar button combines a template-image SF Symbol (switching `tray` → `tray.full` when unread > 0) with the count in monospaced-digit system font, hidden at zero. This is Apple's own status-item pattern and avoids a custom accessory view / manual drawing. Rationale: implementable, testable by eye on the Mac, no image assets.
- **Relative time formatted in the shell** (`RelativeDateTimeFormatter`), not core: formatting is presentation; core only exposes which entry is latest. Rationale: keeps KeryxKit UI-free and the test surface locale-independent.
- **App icon generated on the release runner**: a small AppKit script draws the tray glyph at required sizes, assembles the .icns with system tooling, and the bundle step references it. Rationale: deterministic, no binary blobs in the repo, runner already has AppKit.
- **About as alert panel**: name + version in a standard NSAlert. Rationale: cheapest native-idiomatic surface for a menubar utility; a dedicated window is unwarranted ceremony.
- **Notification tap handling extends the existing notifier**: the delegate method already conformed to (`willPresent`) is joined by `didReceive`; the response payload carries the file path, and handling routes through the controller's existing `open(_:)` plus the opener-resolution chain. Rationale: single ownership of notification behavior; no new component.

---

## Open Questions

### Resolved During Planning

- Badge treatment (origin deferred): symbol swap + attributed count text (see Key Technical Decisions).
- .icns packaging (origin deferred): generated on the release runner via AppKit script + system tooling (see Key Technical Decisions).

### Deferred to Implementation

- Cold-start notification behavior (origin deferred): whether a click that *launches* the not-yet-running bundled app reliably delivers the response with its payload. Mitigation designed in (delegate configured during app launch, payload read defensively); actual behavior verified manually on the Mac during work.
- Exact badge optical weight/count styling: tuned by eye against system items on a real Mac (HIG guidance is qualitative here).

---

## Implementation Units

- U1. **Core: latest-entry accessor on InboxState**

**Goal:** Expose the most recent entry so the shell can render the last-activity preview.

**Requirements:** R4

**Dependencies:** None

**Files:**
- Modify: `Sources/KeryxKit/InboxState.swift`
- Test: `Tests/KeryxKitTests/InboxStateTests.swift`

**Approach:**
- Entries are maintained sorted newest-first, so the accessor returns the first entry (nil when empty).

**Execution note:** Implement test-first (TDD on Linux, like the rest of KeryxKit).

**Patterns to follow:**
- Existing computed accessors on `InboxState` (`badgeCount`).

**Test scenarios:**
- Happy path: state with entries → accessor returns the newest entry.
- Happy path: after `insert` of a newer file → accessor now returns that file.
- Edge case: empty state → accessor returns nil.
- Edge case: after `sync` removes the newest file → accessor falls back to the next-newest.

**Verification:**
- `swift test` on Linux passes with the new scenarios; existing 36 tests unaffected.

---

- U2. **Menubar icon and unread badge**

**Goal:** Replace the emoji-text icon with a template-image SF Symbol and visual unread count.

**Requirements:** R1, R2

**Dependencies:** None

**Files:**
- Modify: `Sources/KeryxApp/main.swift`

**Approach:**
- `render()` sets the button's template image from SF Symbols (`tray` when all read, `tray.full` when unread > 0) and applies the count as attributed text (monospaced-digit system font) next to the image; empty at zero. Icon becomes nil-only when a symbol lookup fails (defensive fallback to current behavior is not acceptable — fail visibly in CI review, not silently).

**Patterns to follow:**
- The existing `render()` single-point-of-update pattern.

**Test scenarios:**
- Test expectation: none — pure AppKit presentation; macOS CI compiles it, manual Mac check per origin AE1.

**Verification:**
- macOS CI release build compiles; on the Mac: icon is monochrome and tinted in light/dark menu bar; count appears/disappears with unread state (AE1).

---

- U3. **Menu polish: symbols, preview, About, empty state**

**Goal:** Native-feeling menu: SF Symbol icons on action items, accent-symbol unseen markers, last-activity preview line, About item.

**Requirements:** R3, R4, R5; origin AE3, AE5

**Dependencies:** U1 (preview data), U2 (same file/render pattern)

**Files:**
- Modify: `Sources/KeryxApp/main.swift`

**Approach:**
- Action items (Mark All Read, Settings…, Open Inbox Folder, Quit) get small SF Symbol images via the menu item `image` slot.
- File rows: unseen files get an accent-colored small circle symbol in the image slot instead of the text prefix; title is the bare filename.
- A disabled preview item sits above the file list: latest entry name + relative time from the system relative-date formatter, formatted at render time.
- About item opens a standard alert with name + version from the app bundle (falls back to the CFBundle version used by the release packager).
- "Open Inbox Folder" stays enabled when the inbox is empty.

**Patterns to follow:**
- `render()` rebuild pattern; `InboxState.latestEntry` from U1.

**Test scenarios:**
- Test expectation: none — presentation + bundle metadata; AE3/AE5 verified manually (AE3's data path is covered by U1 tests).

**Verification:**
- macOS CI compiles; on the Mac: symbols render in menu, preview tracks newest file and refreshes on open (AE3), About shows name + version (AE5).

---

- U4. **Notification tap-to-open**

**Goal:** Clicking a notification opens the file and marks it read; multi-file notifications open the newest.

**Requirements:** R6, R7; origin AE2, flow F1

**Dependencies:** None (extends existing notifier)

**Files:**
- Modify: `Sources/KeryxApp/UserNotifier.swift`
- Modify: `Sources/KeryxApp/main.swift`

**Approach:**
- Each notification request payload carries the referenced file paths (newest first for batch notifications).
- The notifier gains a callback into the controller: on `didReceive response`, resolve the newest path in the payload through the opener-resolution chain (same lookup the menu's open action uses), open it, mark the corresponding entry read via the controller, and refresh.
- Delegate is configured during app launch (not lazily) so clicks that cold-start the app are still delivered; payload parsing is defensive (missing/unopenable path → no-op, notification stays actionable via the menu).

**Patterns to follow:**
- `UserNotifier` existing structure; opener-resolution chain in `AppDelegate.openFile` (extract a shared resolve-and-open helper rather than duplicating it).

**Test scenarios:**
- Test expectation: none — AppKit/UserNotifications interaction; verified manually on the Mac (AE2). The shared resolve-and-open helper keeps this logic in one place for future core extraction.

**Verification:**
- macOS CI compiles; on the Mac: single-file notification click opens the file and decrements the badge; batch notification click opens the newest file only (AE2); menu click path still behaves identically (regression).

---

- U5. **Settings window polish: sections, accessibility, footer**

**Goal:** Grouped, labeled, accessible Settings that reads like a native preference pane.

**Requirements:** R8, R9, R10; origin AE4

**Dependencies:** None

**Files:**
- Modify: `Sources/KeryxApp/SettingsWindow.swift`

**Approach:**
- Section headers (Inbox, Visibility, Opening files, General) as small secondary-color labels between existing control groups; consistent leading label-column width for the inbox/age rows.
- Rule trash buttons get `accessibilityLabel` "Remove rule for \<ext\>".
- Footer label at the window bottom: "Keryx \<version\>" from the bundle.

**Patterns to follow:**
- Existing programmatic stack-view layout and live-apply flow.

**Test scenarios:**
- Test expectation: none — layout/a11y metadata; AE4 verified with VoiceOver on the Mac.

**Verification:**
- macOS CI compiles; on the Mac: sections are visually grouped, VoiceOver announces per-rule labels (AE4), footer shows version.

---

- U6. **App icon in release packaging**

**Goal:** The packaged `Keryx.app` carries a generated app icon.

**Requirements:** R11

**Dependencies:** None (release workflow only)

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `Scripts/make-icon.swift` (iconset generator run on the macOS runner)

**Approach:**
- The packaging step invokes the Swift script (runs on the macOS runner with AppKit): draws a simple tray glyph in Keryx-recognizable style at the iconset sizes, writes the iconset, converts to .icns with system tooling, adds it to `Contents/Resources`, and references it from the bundle metadata (icon file + icon name keys).

**Test scenarios:**
- Test expectation: none — build packaging; verified by the release run producing a bundle whose Resources contain the .icns (checked via the release artifact listing) and visually when installed.

**Verification:**
- Release workflow run succeeds; downloaded bundle contains the icon and macOS shows it (Quick Look / Get Info on the .app).

---

- U7. **README + release**

**Goal:** Document the new surfaces; ship as v0.5.0.

**Requirements:** All (rollout)

**Dependencies:** U1–U6

**Files:**
- Modify: `README.md`

**Approach:**
- Update the macOS/runtime section: icon/badge behavior, notification tap-to-open, settings sections. Tag `v0.5.0` to trigger the release pipeline; verify the packaged bundle contains the icon.

**Test scenarios:**
- Test expectation: none — documentation and release choreography.

**Verification:**
- Release v0.5.0 published with the app-icon-carrying bundle; README matches shipped behavior.

---

## System-Wide Impact

- **Interaction graph:** `AppDelegate.render()` is the single update point for icon + menu — every requirement here flows through it; U2–U3 must not fragment state updates into new ad-hoc paths.
- **Error propagation:** Notification tap handling must not throw into the UI thread — unopenable/missing payload paths no-op (with menu as the fallback channel); alert on login-item failures already sets the precedent.
- **State lifecycle risks:** The preview and badge derive from controller state; they must update on the same `onChange` hop to main that the menu uses — no second refresh path. `didReceive` handling mutates controller state from the notification delegate queue; route through the same main-thread hop as `onChange` consumers.
- **API surface parity:** The opener-resolution chain must remain single-source after extraction (menu action and notification action share one helper) — divergent resolution between menu and notifications would be a parity bug.
- **Integration coverage:** U1's accessor is covered by unit tests; U4's controller interaction is the cross-layer seam covered only manually on the Mac (acknowledged limitation, same as prior releases).
- **Unchanged invariants:** Settings persistence format, `KERYX_INBOX`/`KERYX_OPEN_APP` env behavior, watcher architecture, and all KeryxKit state semantics are untouched.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Cold-start notification response not delivered (origin deferred question) | Delegate configured at launch; defensive payload parsing; manual Mac verification in U4; menu remains the fallback path |
| Icon generation fails on runner, blocking releases | Script is self-contained AppKit drawing with no network; release step hard-fails visibly rather than shipping an iconless bundle |
| Badge styling looks wrong next to system items | Tuned manually on the Mac in U2; HIG weight guidance qualitative — accept iteration |
| SF Symbol name drift | All symbols pinned to long-stable names available since macOS 11–13; platform minimum is 15 |

---

## Documentation / Operational Notes

- README macOS section updated (U7); release notes for v0.5.0 generated automatically by the pipeline.

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-09-24-hig-conformance-requirements.md](../brainstorms/2026-09-24-hig-conformance-requirements.md)
- Related code: `Sources/KeryxApp/main.swift`, `Sources/KeryxApp/UserNotifier.swift`, `Sources/KeryxApp/SettingsWindow.swift`, `Sources/KeryxKit/InboxState.swift`, `.github/workflows/release.yml`
- Related issues: #1 (notarization — unaffected)
- External docs: https://bjango.com/articles/designingmenubarextras/ ; https://developer.apple.com/design/human-interface-guidelines/the-menu-bar