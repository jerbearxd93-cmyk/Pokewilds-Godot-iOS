# iOS port — what changed and what still needs a Mac

Branch: `ios-port`. Base: `main` (PokeWilds 0.9.3, Godot **4.7.2.stable Standard**,
renderer **GL Compatibility**, landscape, 320x180 design canvas).

Nothing in this branch has been compiled or run: this work was done without a
Godot editor, Xcode or an iOS device. Every change below is a source change plus
the reasoning behind it. The "Test on your Mac" section is the part that turns
this into a verified port.

Android and desktop behaviour is meant to be unchanged. The only intentional
shared changes are the QUIT GAME row (mobile only) and GAME FILES becoming
Android-only in the touch panel.

---

## 1. What was wrong for iOS

| # | Problem | Where |
|---|---|---|
| 1 | No iOS export preset at all | `project/export_presets.cfg` |
| 2 | Touch pad never appears: visibility, edit mode and safe-area polling were gated on `OS.has_feature("android")` | `scripts/touch_controls.gd` |
| 3 | No safe-area insets on iOS: notch / Dynamic Island / home indicator were never subtracted, so controls sat under them | `scripts/touch_controls.gd` |
| 4 | Touch settings panel unreachable: `_is_android_touch_runtime()` decided it, and iOS was not in it | `scripts/main.gd` |
| 5 | No way to quit or save-and-quit: the quit prompt is only reachable from Escape, `NOTIFICATION_WM_GO_BACK_REQUEST`, the Android back bridge or `KEY_BACK` | `scripts/main.gd` |
| 6 | Control edit mode could not be left: exits were Android Back / cancel / escape only, and the hint read "ANDROID BACK SAVES" | `scripts/touch_controls.gd` |
| 7 | LAN multiplayer silently blocked: iOS 14+ needs `NSLocalNetworkUsageDescription`, and broadcast lobby discovery additionally needs Apple's multicast entitlement | export preset, `scripts/coop_network.gd` |
| 8 | Save helpers bypassed the live data root (`user://saves`, `user://world_cache` hard-coded) while saves are written through `game_data_paths.path()`. On Android external storage those helpers pointed at the wrong folder | `scripts/game_files.gd` |
| 9 | GAME FILES panel offered on every platform, but it needs the Android shared-folder bridge | `scripts/main.gd`, `scripts/game_files_menu.gd` |

Not iOS-specific, found while reading: `game_files.export_all/export_save/import_save`
are currently unreferenced dead code (`game_options.gd` only uses `copy_file` and
`write_bytes`). They are fixed anyway so they cannot mislead later.

Harmless on iOS, no action taken: `[android]` project settings, gradle keys,
`config/quit_on_go_back`, `screen/immersive_mode`. Every `JavaClassWrapper` and
`AndroidRuntime` call was already guarded by an OS check.

---

## 2. What changed

### `project/export_presets.cfg` — new iOS preset (`preset.1`)

- Same `include_filter` / `exclude_filter` as the Android preset, so mods, data
  and `lobby_server.txt` are exported identically.
- `application/bundle_identifier="com.pokewilds.godot"` (same identifier as the
  Android package — change it if that identifier is not yours).
- `application/app_store_team_id` is a **placeholder**. Export fails until you
  put your 10-character Team ID in.
- `application/export_project_only=true`: the export writes
  `project/build/ios/Pokewilds/` (an Xcode project) and does not call
  `xcodebuild`. This is deliberate — a fresh Mac has no signing profile yet, so
  this always succeeds and you build/run from Xcode. Clear the checkbox in
  Project > Export > iOS to have Godot produce the `.ipa`/XCArchive itself.
- `application/min_ios_version="13.0"`, `targeted_device_family=2` (iPhone and
  iPad), `architectures/arm64=true`, `capabilities/access_wifi=true`,
  `short_version`/`version` `0.9.3` (mirrors the Android 0.9.3 / code 93).
- `application/additional_plist_content` adds
  `NSLocalNetworkUsageDescription`, so multiplayer can prompt for Local Network
  access instead of being blocked silently.

### `scripts/touch_controls.gd`

- `android_runtime` → **`touch_runtime`**, set from `OS.has_feature("mobile")`.
  Android and iOS now both get the pad, the settings panel, edit mode and the
  safe-area poll; desktop still gets none of it.
- `_refresh_display_layout()` uses `touch_runtime` instead of
  `OS.has_feature("android")`, so `DisplayServer.get_display_safe_area()` is
  applied on iOS too. `safe_rect_in_canvas()` already falls back to the full
  canvas if a platform reports an empty safe area.
- Edit mode can be left by tapping the hint on any platform without Back, and
  the hint text changes to `DRAG CONTROLS - TAP HERE TO SAVE` off Android.
  (Tapping the "Controls" glyph still works on every platform.)

### `scripts/main.gd`

- `_is_android_touch_runtime()` → **`_is_touch_runtime()`** (6 call sites) and
  now keyed on `OS.has_feature("mobile")` plus `touch_controls.touch_runtime`,
  so iOS gets the touch panel, the `touch_config` action and the pad-driven
  menu paths.
- New **QUIT GAME** row in the touch panel (visible on mobile only), wired to
  `_quit_from_touch_config()` → `_close_touch_config()` + `_open_quit_prompt()`.
  This is the only route to the quit/save-before-quit prompt on iOS, which has
  no system Back. The row and the prompt use the same wording on every platform:
  `QUIT GAME`, `QUIT GAME?`, `SAVE BEFORE QUIT?`.
- iOS never reaches `get_tree().quit()`: `_handle_quit_prompt_input()` hands
  over to **`_return_to_title_screen()`**, which ends any co-op session, unpauses
  the tree, restores input processing and replaces the scene with
  `res://scenes/main.tscn` — checked `change_scene_to_file`, then
  `reload_current_scene`, then a 5 second watchdog that reports to the dialogue
  box and the log if the swap never happened. On a device this exit has been
  observed to close the app cleanly, which is what the labels now describe.
- **GAME FILES** row is now visible only on Android (it needs the Android
  shared-folder bridge). The modding row and all settings rows are unchanged.
- `_prepare_swipe_cursor()` skips hidden rows, so the swipe cursor can never
  select a row a platform hides.

### `scripts/game_files.gd`

- All save and world-cache paths now go through
  `game_data_paths.path(...)` (`const DataPaths`) instead of the hard-coded
  `user://saves` / `user://world_cache`. Directory creation and renames use
  `ProjectSettings.globalize_path()` on both sides, which is what Android
  external storage needs.
- The scratch transfer file stays on `user://` on purpose: it must live in
  storage that is always writable before the shared folder is touched.

### `scripts/game_data_paths.gd`

- Comment only. iOS points the live root at the app's **Documents** folder
  (`OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)`), so saves show up under *On My
  iPhone* in the Files app; that needs `user_data/accessible_from_files_app` and
  `user_data/accessible_from_itunes_sharing` in the preset, both on.
- An unhelpful answer from the platform (empty, relative, or a folder that
  cannot be created) keeps the private `user://` root and `initialize()` pushes
  the reason. The first launch copies private saves over once and leaves a
  `.private-saves-migrated` marker, so it never overwrites later saves.

### `scripts/game_files_menu.gd`

- The "no folder bridge" status line now says GAME FILES is Android-only when
  running on iOS instead of pointing at the Android app from iOS.

### `BUILD.txt`, `.gitignore`

- New IOS section in `BUILD.txt` (requirements, preset, what is exported,
  multiplayer reality, save location).
- `.gitignore` ignores `*.ipa`, `*.xcarchive` and `build/ios/` (export output).

---

## 3. What cannot work on iOS as-is

1. **ONLINE multiplayer through ZeroTier.** `coop_network.embedded()` wraps the
   Android-only `PokeWildsZeroTier` Java class. iOS falls back to the LAN path
   (TCP 54555, `coop_join_code.gd`). Getting ZeroTier on iOS means porting
   libzt to an iOS framework and writing the equivalent bridge — a separate job,
   and libzt is BSL-1.1 (see `LICENSES/ZeroTier-libzt-BSL-1.1.txt`).
2. **Broadcast lobby discovery.** `coop_network.beacon_open()` sends to
   `255.255.255.255:54556`. On iOS that needs the
   `com.apple.developer.networking.multicast` entitlement, which Apple grants
   only on request. Until then use JOIN CODE / direct address, which is unicast
   and works with `NSLocalNetworkUsageDescription` alone.
3. **GAME FILES shared folder.** Android SAF only. On iOS saves stay in the app
   sandbox; there is no in-app copy-out yet (see follow-ups).
4. **QUIT GAME and App Review.** The row reads QUIT GAME on every platform and
   all platforms run the same exit flow, which on a device has been seen to
   terminate the app. Apple discourages programmatic termination (App Store
   Review Guideline 2.5.1), so review this before any store submission.
5. **JSON save compatibility.** Unchanged in principle (same `.json` + 
   `exact_v2_*.bin` caches), but iOS has never actually written a save. Verify
   it before trusting it.

---

## 4. Test on your Mac / device

Build first:

1. Godot 4.7.2 Standard + matching iOS export templates, Xcode installed,
   `xcode-select -p` pointing at `/Applications/Xcode.app`.
2. Open `project/project.godot`, let imports finish (`.godot` is regenerated).
3. Project > Export > iOS: fill in Team ID, keep/change the bundle id, export to
   `project/build/ios/Pokewilds`.
4. Open `Pokewilds.xcodeproj`, set your team under Signing & Capabilities, build
   to a device. For a quick check the iOS **simulator** also works — GL
   Compatibility is the one renderer it supports, which is what this project uses.

Then check, in this order:

- **Launch**: title screen, no blank screen, no script errors in the Godot log.
- **Touch pad**: it appears on the title screen and in game; the face buttons,
  D-pad, both sticks, L1/R1/L2/R2, START and SELECT all do what
  `project/POKEWILDS-BUTTON-MAP.md` says.
- **Safe areas**: on a notched iPhone in landscape, no control sits under the
  notch/island and none under the home indicator. Rotate: the pad must reflow
  within the safe rect (it polls every 0.5 s).
- **Touch panel**: tap the small Controls glyph (top centre) → panel opens and
  scrolls. TOUCH CONTROLS on/off, AUTO HIDE, OPACITY, SIZE, THEME, MOVE
  CONTROLS, RESET, MODDING, QUIT GAME, CLOSE all respond.
- **Edit mode**: MOVE CONTROLS → drag a button → tap the "DRAG CONTROLS" hint to
  save. Then check the layout persisted after an app restart.
- **QUIT GAME (iOS)**: panel → QUIT GAME → QUIT GAME? → SAVE BEFORE QUIT? → YES
  or NO ends the game and the app closes; a save made on the way out is found by
  LOAD on the next launch. No "TITLE SCREEN" or "SAVE BEFORE EXIT?" text should
  appear anywhere.
- **QUIT GAME (Android/desktop)**: unchanged; the prompt still exits the game.
- **Save/load**: new world → play → save → quit → relaunch → LOAD finds it.
  Then a second save and an in-game area transition.
- **Data paths**: with `user_data/accessible_from_files_app` and
  `accessible_from_itunes_sharing` on, *Files > On My iPhone > Pokewilds* shows
  `saves/`, `game.ini` and `world_cache/`. If it does not, the log says "The app
  Documents folder is unavailable" and everything stays under
  `Library/Application Support` (Xcode > Devices > Download Container).
- **Text entry**: WORLD NAME and PLAYER NAME open the iOS keyboard, accept
  input, and close on confirm without leaving the menu stuck.
- **Background/foreground**: home button mid-game, return — no stuck buttons,
  no reset save, the world resumes.
- **Controller** (if you have one): pair a DualShock/DualSense/Xbox pad; the pad
  should be detected and, with AUTO HIDE on, the touch pad should hide.
- **Multiplayer on LAN**: host on iPhone, join by JOIN CODE from Android/PC (and
  the reverse). Expect the Local Network permission prompt on first use; decline
  it once to confirm the game reports no lobby instead of hanging.
- **Android regression**: build the Android preset as before. Confirm the touch
  pad, safe area, GAME FILES (still visible, still opens and syncs), back
  button → quit prompt, modding, and touch edit mode (still saved by Back).
- **Desktop regression**: F5 in the editor. No touch pad, no touch panel; touch
  panel from OPTIONS shows MODDING but not GAME FILES or QUIT GAME.

---

## 5. Follow-ups worth doing on a Mac

1. **Save export on iOS.** Mirrors the Android story: write the `.pwsave`
   bundle to `Documents/` and set `user_data/accessible_from_files_app` so it
   can be pulled off the device with the Files app. `game_files.export_save()`
   already builds a portable bundle; it needs a destination picked on iOS.
2. **Multicast entitlement** request, so lobby discovery works instead of
   JOIN CODE only.
3. **iPad multitasking.** Orientation is sensor-landscape from
   `display/window/handheld/orientation`. Check whether the generated
   `Info.plist` sets `UIRequiresFullScreen`; without it, iPad split view may ask
   for portrait sizes the UI does not handle.
4. **libzt for iOS**, if ZeroTier ONLINE play is wanted on iPhone (large).
5. Consider `entitlements/increased_memory_limit` for older devices once real
   memory use is measured on a device.
