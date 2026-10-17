# PRD: Purrlo, a menu bar app that keeps a Bluetooth speaker connected

Oct 17, 2026 · @ovi

## 1. Overview

Build a free, open-source, notarized macOS menu bar app that keeps a chosen Bluetooth speaker connected and streaming, so an Amazon Echo stops repeating its "Now connected to…" announcement.

**Problem.** An Echo used as a Bluetooth speaker announces "Now connected to \[device name\]" on every reconnect. Amazon staff have confirmed this cannot be disabled. A Mac reconnects often: macOS closes idle audio streams after a few seconds, and sleep, wake and lid close drop the link.

**Solution.** Remove every reason for the link to drop while the user wants it: stream an inaudible signal so it never goes idle, keep the Mac awake while the speaker is connected (lid open or closed), and handle the remaining sleep cases with one controlled reconnect.

**Name:** Purrlo (chosen 17 October 2026; candidates in the appendix). Bundle IDs: io.github.\<owner>.purrlo and io.github.\<owner>.purrlo.helper. Product name and icon must not use "Echo" or "Alexa" (Amazon trademarks); the README may say "works with Amazon Echo".

**Decisions made**

| Topic                | Decision                                                                        |
| -------------------- | ------------------------------------------------------------------------------- |
| Form factor          | Native Swift menu bar app, no runtime dependencies                              |
| Minimum macOS        | 14 Sonoma; Apple Silicon and Intel                                              |
| Distribution         | GitHub Releases (signed, notarized DMG) and a Homebrew tap; Sparkle auto-update |
| Signing              | Apple Developer Program, $99 per year                                           |
| Prevent sleep        | Always on while the speaker is connected, on battery and on power               |
| Lid closed           | Supported in v1 through a privileged helper                                     |
| Sleep handling       | Disconnect before sleep; reconnect once after unlock                            |
| Update feed and site | GitHub Pages; a .dev domain may come later                                      |
| License              | MIT                                                                             |

**Reading this PRD.** It is written for an implementing model or engineer. MUST, SHOULD and MAY follow RFC 2119. Requirement IDs (FR-x, NFR-x, E2E-x) are referenced in tests and commits.

## 2. Background and prior art

Five things drop the link; v1 handles four of them and fully eliminates the first two.

| Cause                                                       | How v1 handles it                                                        | Residual risk                                |
| ----------------------------------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------- |
| macOS closes an idle output stream after a few seconds      | Continuous inaudible stream to the target (FR-3)                         | None expected                                |
| Idle system sleep                                           | Power assertion while the target is connected (FR-9)                     | None                                         |
| Lid closed                                                  | Privileged helper disables sleep while the target is connected (FR-10)   | Heat and battery; guarded by safety cut-offs |
| Manual sleep, low battery, or sleep after a cut-off         | Disconnect before sleep, one reconnect after unlock (FR-11, FR-12)       | One announcement                             |
| Radio interference, distance, another device takes the Echo | Not handled                                                              | Documented in README                         |

**Findings the design relies on**

- **The announcement cannot be turned off.** Amazon staff say so repeatedly on Amazon's forums. Brief Mode, Do Not Disturb, Announcements off and notification volume do not reliably remove it.
- **Stream continuously, never "ping".** Tools that play a sound every few minutes are too slow, because macOS closes the stream after seconds.
- **Signal level.** CoreAudio keeps the stream open whatever the samples contain. Whether Echo firmware treats digital zeros differently is unproven, so default to a 30 Hz sine at amplitude 0.001 (about −60 dBFS) and offer pure silence as an option.
- **Screen saver, display sleep and screen lock do not drop the link.** Only system sleep does.
- **Wired alternative.** Echo 4th gen, Echo Studio and Echo Plus 2nd gen have a 3.5 mm line-in, which avoids Bluetooth entirely. The README mentions it.

**Prior art** (study for ideas; take no dependency)

| Project                                                                         | What it does                                                                           | Lesson for us                                                      |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| [subhande/speaker-awake](https://github.com/subhande/speaker-awake)             | Swift menu bar app; AVAudioEngine plays a −120 dBFS sine continuously; launch at login | Closest to our idea; no release binary, follows the default output |
| [eamq/mac-audio-keepalive](https://github.com/eamq/mac-audio-keepalive)         | Rust launchd daemon streaming zeros to the default output; near-zero CPU               | Zeros are enough for macOS; continuous stream is cheap             |
| [yuriykis/bluetooth-keepalive](https://github.com/yuriykis/bluetooth-keepalive) | Go CLI; plays a sound every 5 minutes                                                  | Periodic pings are too slow for macOS                              |
| [samprits5/BTAwakeMac](https://github.com/samprits5/BTAwakeMac)                 | AppleScript; 1 s silent MP3 every 5 minutes                                            | Same weakness                                                      |
| [MendyLanda/mac-blue-keep-alive](https://github.com/MendyLanda)                 | Script that reconnects a device every few minutes                                      | Reconnect loops cause announcements; avoid                         |
| [cdaringe/bluesnooze](https://github.com/cdaringe/bluesnooze)                   | Turns Bluetooth off on sleep, on at wake                                               | Basis for disconnect-before-sleep                                  |
| [clanceyz/KeepSpeekerAwake](https://github.com/clanceyz/KeepSpeekerAwake)       | Windows; audible-band bursts so codecs do not drop silence                             | Why we default to a tone, not zeros                                |

None of these targets one device by UID, handles sleep and lid close, or ships a notarized build.

## 3. Goals, non-goals and success metrics

Success means a whole working day, lid open or closed, with zero announcements after the first connect.

**Goals**

- G1. Keep one chosen Bluetooth output connected and streaming for as long as the user leaves it connected.
- G2. Keep the Mac awake while that speaker is connected, including with the lid closed, with safety cut-offs.
- G3. When sleep does happen, avoid background reconnects and limit the return to one reconnect.
- G4. Install like any Mac app: download or `brew install`, open, pick the speaker; no Terminal, no warnings.
- G5. Fully automated, reproducible build, test and release pipeline on GitHub.

**Non-goals (v1)**

- Disabling the Echo's announcement itself or using Alexa cloud APIs.
- Pairing devices or reconnecting in loops.
- Routing, mixing or processing the user's audio.
- Several target speakers at once.
- Mac App Store, Windows, Linux, iOS.

**Users**

- The owner, on several Macs (laptops and desktops).
- Friends and the public installing from GitHub or Homebrew, with no Terminal skills assumed.

**Success metrics**

| ID   | Metric                                                             | Target          | Measured by      |
| ---- | ------------------------------------------------------------------ | --------------- | ---------------- |
| SM-1 | Announcements caused by the Mac during an 8-hour session, lid open | 0               | E2E-H1           |
| SM-2 | Same, lid closed on power and on battery above the cut-off         | 0               | E2E-H2           |
| SM-3 | Announcements during an overnight sleep                            | 0               | E2E-H3           |
| SM-4 | Average CPU while streaming, Apple Silicon                         | under 1%        | E2E-P1           |
| SM-5 | Resident memory                                                    | under 30 MB     | E2E-P1           |
| SM-6 | Time from download to streaming for a new user                     | under 2 minutes | Manual           |
| SM-7 | Releases needing manual build steps                                | 0               | Release pipeline |

## 4. Functional requirements

All MUST items are in scope for v1.0 except FR-13, which its M1 spike dropped (§11, 17 October 2026).

| ID    | Priority    | Requirement                                                                                                                                                                                                                                                                                                                                                                                   |
| ----- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-1  | MUST        | List audio output devices, Bluetooth first, and let the user pick one target                                                                                                                                                                                                                                                                                                                  |
| FR-2  | MUST        | Persist the target by CoreAudio device UID, never by name or AudioObjectID; show the current name                                                                                                                                                                                                                                                                                             |
| FR-3  | MUST        | While enabled and the target is present, stream continuously to the target only, independent of the system default output; start within 2 s of the target appearing, stop within 1 s of it disappearing                                                                                                                                                                                       |
| FR-4  | SHOULD      | Signal setting: Inaudible tone (default; 30 Hz, amplitude 0.001) or Silence                                                                                                                                                                                                                                                                                                                   |
| FR-5  | MUST        | Never pair a device. Never connect automatically except the single post-unlock reconnect in FR-12. No retry loops                                                                                                                                                                                                                                                                             |
| FR-6  | MUST        | Master toggle "Keep alive", persisted across launches                                                                                                                                                                                                                                                                                                                                         |
| FR-7  | MUST        | Launch at Login toggle (SMAppService), offered during first run                                                                                                                                                                                                                                                                                                                               |
| FR-8  | MUST        | Status text and icon for each state: Off, Waiting, Streaming, Suspended, Error; status text also says whether sleep is blocked and why                                                                                                                                                                                                                                                        |
| FR-9  | MUST        | While the target is connected, prevent idle system sleep on any power source. Display sleep and screen lock stay allowed. Toggle, default on                                                                                                                                                                                                                                                  |
| FR-10 | MUST        | "Stay awake with lid closed" toggle, default off. When on and the target is connected, the helper (§6) disables system sleep so closing the lid keeps the link. Cut-offs that restore normal sleep at once: battery at or below the threshold (default 20%, range 10–50%), thermal state serious or critical, target disconnected, app quit or crashed, "Sleep Now" chosen, toggle turned off |
| FR-11 | MUST        | Disconnect before sleep, default on: when the system is about to sleep for any reason, stop the stream and disconnect the target, so background wakes (Power Nap, dark wake) cannot reconnect it                                                                                                                                                                                              |
| FR-12 | MUST        | Reconnect after unlock, default on: after the next full wake and screen unlock, reconnect the target once if the app disconnected it; one retry after 10 s; then Waiting                                                                                                                                                                                                                      |
| FR-13 | Dropped     | Dropped after E2E-H4 (§11): the announcement ignores the Mac-side volume. Was: quiet reconnect, default on if shipped: before the FR-11 disconnect, save the target's output volume and set it to 0; restore it 3 s after the reconnect. Remove the feature if the M1 spike shows the announcement ignores this volume                                                                                                                                                       |
| FR-14 | MUST        | "Sleep Now" menu item: clears FR-10, runs FR-11 and sleeps the Mac                                                                                                                                                                                                                                                                                                                            |
| FR-15 | SHOULD      | User notification when a cut-off ends lid-closed mode (for example "Battery at 20%: your Mac can sleep again")                                                                                                                                                                                                                                                                                |
| FR-16 | MUST        | Sparkle 2 updates: check daily, with a "Check for Updates…" item and an opt-out                                                                                                                                                                                                                                                                                                               |
| FR-17 | MUST        | Help (sleep limits, line-in tip, FAQ link), About (version, license, GitHub), Copy Diagnostics, Quit                                                                                                                                                                                                                                                                                          |
| FR-18 | MUST        | First run: explain what the app does in one screen, pick the speaker, offer Launch at Login, and state the battery cost of FR-9 and FR-10                                                                                                                                                                                                                                                     |
| FR-19 | MAY         | Global shortcut to toggle Keep alive                                                                                                                                                                                                                                                                                                                                                          |

**Menu layout** (top to bottom)

1. Status line, for example "Streaming to Echo Dot · Sleep blocked" (not clickable)
2. Keep alive ✓
3. Speaker ▸ output devices, ✓ on the target
4. Signal ▸ Inaudible tone / Silence
5. Sleep ▸ Prevent idle sleep ✓ · Stay awake with lid closed · Battery cut-off ▸ 10–50% · Disconnect before sleep ✓ · Reconnect after unlock ✓
6. Sleep Now
7. Launch at Login ✓
8. Check for Updates…, Help, Copy Diagnostics, About, Quit

Turning on lid-closed mode the first time triggers the helper approval flow (§6) with a plain explanation of what it changes and the battery and heat cost.

## 5. Sleep, wake and lid-closed behavior

One state machine (`AppState`) owns all decisions; the UI only reads it, and every transition is logged and observable by the E2E harness (§8).

**States**

| State     | Meaning                         | Stream  | Idle-sleep assertion      | Lid-closed sleep block                |
| --------- | ------------------------------- | ------- | ------------------------- | ------------------------------------- |
| Off       | Keep alive disabled             | Stopped | Released                  | Cleared                               |
| Waiting   | Enabled, target not present     | Stopped | Released                  | Cleared                               |
| Streaming | Target present, stream running  | Running | Held (FR-9)               | Set if FR-10 on and no cut-off active |
| Suspended | System going to sleep or asleep | Stopped | Released                  | Cleared                               |
| Error     | 3 failed engine restarts        | Stopped | Held while target present | Cleared                               |

**Transitions**

| From               | Event                      | To        | Side effects                                                                            |
| ------------------ | -------------------------- | --------- | --------------------------------------------------------------------------------------- |
| Off                | User enables               | Waiting   | None                                                                                    |
| Waiting            | Target appears             | Streaming | Start engine; hold assertion; set lid block if allowed                                  |
| Streaming          | Target disappears          | Waiting   | Stop engine; release assertion; clear lid block                                         |
| Streaming          | Cut-off (battery, thermal) | Streaming | Clear lid block; notify (FR-15); idle assertion stays                                   |
| Streaming, Waiting | System will sleep          | Suspended | FR-11 disconnect, then allow sleep (max 5 s)                                            |
| Suspended          | Full wake                  | Suspended | Wait for unlock                                                                         |
| Suspended          | Unlock                     | Waiting   | FR-12 reconnect once if the app disconnected the target                                 |
| Streaming          | Engine fails 3 times       | Error     | Notify; retry on device change or user action                                           |
| Any                | User disables              | Off       | Release everything                                                                      |

**Sleep sequence** (FR-11)

1. `IORegisterForSystemPower` receives `kIOMessageSystemWillSleep`.
2. Stop the engine.
3. Close the target's Bluetooth connection (`IOBluetoothDevice.closeConnection`); record `disconnectedByApp = true`.
4. Clear the lid-closed block and release the assertion; call `IOAllowPowerChange`. Steps 2–4 must finish within 5 s or sleep is allowed anyway.

**Wake sequence** (FR-12)

1. Ignore dark wakes; act on `NSWorkspace.didWakeNotification` (full wake) only.
2. Wait for unlock: `com.apple.screenIsUnlocked` distributed notification, or, if no password is required, the session becoming active.
3. If `disconnectedByApp`, call `openConnection` once; on failure retry once after 10 s, then go to Waiting.
4. If the user connected the target, or another device took it, before step 3, skip the reconnect.

**Lid-closed mode** (FR-10)

- Implemented by setting the system "sleep disabled" flag (the setting behind `pmset disablesleep`), which needs root, so it runs in the privileged helper (§6).
- The block is set only in Streaming and is cleared on any exit from Streaming and on every cut-off.
- Fail-safe: the helper clears the flag when the app's XPC connection drops, on its own start-up, and if it has not received a heartbeat from the app for 60 s.
- Battery and thermal state are read by the app every 30 s and on change notifications (`IOPSNotificationCreateRunLoopSource`, `ProcessInfo.thermalStateDidChangeNotification`).
- While the flag is set, Apple menu > Sleep does not sleep the Mac; the README and first-run text say to use the app's "Sleep Now" instead.

## 6. Technical design

Three shipped targets plus a test-only CLI, all in Swift, with Sparkle as the only third-party dependency.

**Stack**

- Swift 6 with strict concurrency; SwiftUI `MenuBarExtra`; macOS 14+; universal binary (arm64, x86_64).
- `LSUIElement = YES`; Hardened Runtime; App Sandbox off (the helper and IOBluetooth need it off).
- Permissions: Bluetooth (`NSBluetoothAlwaysUsageDescription`, first used by FR-11); admin approval for the helper (FR-10). No microphone.
- Dependencies via Swift Package Manager: Sparkle 2 only.

**Targets**

| Target          | Kind                                  | Ships                      | Purpose                                              |
| --------------- | ------------------------------------- | -------------------------- | ---------------------------------------------------- |
| `App`           | Menu bar app                          | Yes                        | UI, `AppState`, wiring                               |
| `KeepAliveCore` | Swift package library                 | Yes (linked)               | All logic behind protocols; unit-testable without UI |
| `SleepHelper`   | launchd daemon, `SMAppService.daemon` | Yes, inside the app bundle | Sets and clears the sleep-disabled flag as root      |
| `kactl`         | CLI                                   | E2E builds only            | Drives and inspects a running E2E build (§8)         |

**Modules in `KeepAliveCore`**

| Module                | Responsibility                                                                | Key APIs                                                                                                                                                                            |
| --------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DeviceMonitor`       | Output device list, target presence, renames, sample-rate changes             | `kAudioHardwarePropertyDevices`, `kAudioDevicePropertyDeviceUID`, `kAudioDevicePropertyTransportType`, `kAudioDevicePropertyDeviceIsAlive`, `kAudioDevicePropertyNominalSampleRate` |
| `KeepAliveEngine`     | One AUHAL output unit bound to the target                                     | `kAudioUnitSubType_HALOutput`, `kAudioOutputUnitProperty_CurrentDevice`                                                                                                             |
| `SignalGenerator`     | Fills Float32 buffers: phase-continuous sine or zeros; no allocation or locks | Pure Swift                                                                                                                                                                          |
| `PowerManager`        | Idle-sleep assertion (FR-9)                                                   | `IOPMAssertionCreateWithName`, `kIOPMAssertionTypePreventUserIdleSystemSleep`                                                                                                       |
| `SleepCoordinator`    | Will-sleep and wake handling, unlock detection                                | `IORegisterForSystemPower`, `IOAllowPowerChange`, `NSWorkspace` notifications, `com.apple.screenIsUnlocked`                                                                         |
| `BluetoothController` | Disconnect and single reconnect of the target                                 | `IOBluetoothDevice` (`closeConnection`, `openConnection`)                                                                                                                           |
| `PowerSourceMonitor`  | Battery percentage, AC state, thermal state                                   | `IOPSCopyPowerSourcesInfo`, `ProcessInfo.thermalState`                                                                                                                              |
| `HelperClient`        | XPC client to `SleepHelper`; heartbeat every 20 s                             | `NSXPCConnection`                                                                                                                                                                   |
| `Settings`            | Persisted preferences                                                         | `UserDefaults`                                                                                                                                                                      |
| `AppState`            | The state machine of §5                                                       | Main actor                                                                                                                                                                          |

**Audio**

- AUHAL rather than `AVAudioEngine`: it binds to a non-default device and never follows default-output changes.
- Format: Float32, non-interleaved, the device's channel count and nominal sample rate.
- Restart the unit on sample-rate change (Bluetooth switches to hands-free when a mic is used) and when the target's `AudioObjectID` changes.
- Engine errors: retry after 1, 2, 5, 10, 30 s while the target is present; Error state after 3 consecutive failures.

**Devices**

- Bluetooth outputs: transport type `Bluetooth` or `BluetoothLE`; listed first, others after a separator.
- Map a CoreAudio UID to its `IOBluetoothDevice` by the Bluetooth address embedded in the UID; fall back to matching the paired device name; if neither matches, disable FR-11 and FR-12 for that device and say so in the menu.
- All CoreAudio listeners run on one private serial queue and hop to the main actor.

**Privileged helper (`SleepHelper`)**

- Registered with `SMAppService.daemon(plistName:)`; plist in `Contents/Library/LaunchDaemons`. First enable shows the system approval in System Settings > General > Login Items; the app opens that pane and explains why.
- XPC Mach service with three methods only: `setSleepDisabled(Bool)`, `heartbeat()`, `status()`.
- Accepts connections only from the app, enforced with `NSXPCConnection.setCodeSigningRequirement` (team ID and bundle ID).
- Sets the flag with `IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey)`; falls back to `/usr/bin/pmset -a disablesleep 0|1`.
- Fail-safe rules from §5: clear on start-up, on client disconnect, and after 60 s without heartbeat.
- Help menu offers "Remove Helper" (`unregister()` after clearing the flag).

**Test hooks (E2E builds only)**

- Compiled only with the `E2E_HOOKS` flag in the `E2E` build configuration; Release builds MUST NOT contain them (checked in CI, §8).
- The app listens on a Unix socket in its Application Support folder and speaks newline-delimited JSON with `kactl`.
- Commands: `status`, `devices`, `set-target <uid>`, `set <setting> <value>`, `simulate will-sleep|did-wake|unlock|battery <pct>|thermal <state>|helper-crash`, `transitions` (ordered log since launch), `metrics` (CPU, memory, render callback timing).
- Launch arguments `--fake-bluetooth` and `--fake-helper` swap in recording fakes so CI can verify calls without hardware or root approval.

## 7. Edge cases and non-functional requirements

Every case below ends in a defined state, and none may start a Bluetooth connection other than FR-12.

| ID    | Case                                               | Expected behavior                                                            |
| ----- | -------------------------------------------------- | ---------------------------------------------------------------------------- |
| EC-1  | Target absent at launch                            | Waiting; no errors, no retries                                               |
| EC-2  | Two devices with the same name                     | Distinguished by UID; menu adds a short UID suffix                           |
| EC-3  | Target renamed                                     | Still matched by UID; new name shown                                         |
| EC-4  | User plays audio to the target                     | Streams mix; tone stays inaudible                                            |
| EC-5  | Default output switched elsewhere                  | Stream continues to the target only                                          |
| EC-6  | Hands-free profile (mic in use)                    | Sample-rate change; engine restarts at the new rate                          |
| EC-7  | Bluetooth turned off                               | Target disappears; Waiting; lid block cleared                                |
| EC-8  | Screen saver, display sleep, screen lock           | No change; keeps streaming                                                   |
| EC-9  | Fast user switching away                           | Stream stops; resumes when the session is active again                       |
| EC-10 | Power Nap or dark wake at night                    | Target stays disconnected; no announcement                                   |
| EC-11 | Another device takes the Echo while the Mac sleeps | FR-12 reconnect fails, one retry, then Waiting                               |
| EC-12 | Dropped with FR-13 (was: app quits with volume at 0) | Not applicable; the app no longer changes the volume                       |
| EC-13 | App quits or crashes with the lid block set        | Helper clears the flag within 60 s (immediately on connection drop)          |
| EC-14 | Helper not approved or removed                     | FR-10 shows "Needs approval" and links to Login Items; everything else works |
| EC-15 | Battery reaches the cut-off with the lid closed    | Flag cleared; Mac sleeps normally; FR-11 runs                                |
| EC-16 | Thermal state serious or critical                  | Flag cleared until the state returns to nominal or fair for 5 minutes        |
| EC-17 | Two Macs paired to one Echo                        | Only one can be connected; the other stays Waiting                           |
| EC-18 | Device UID has no Bluetooth address                | FR-11 and FR-12 disabled for it; streaming still works                       |

**Non-functional requirements**

| ID     | Requirement                                                                                                                                              |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| NFR-1  | CPU under 1% averaged over 10 minutes while streaming on Apple Silicon; under 3% on Intel                                                                |
| NFR-2  | Resident memory under 30 MB; no growth over 24 hours                                                                                                     |
| NFR-3  | No allocation, locks or Objective-C messaging on the audio render thread                                                                                 |
| NFR-4  | Runs 7 days without restart                                                                                                                              |
| NFR-5  | No network traffic except Sparkle (which can be turned off); no analytics                                                                                |
| NFR-6  | Helper exposes only the three XPC methods and accepts only the signed app                                                                                |
| NFR-7  | VoiceOver labels on all menu items; state never shown by icon alone                                                                                      |
| NFR-8  | English UI; all strings in a String Catalog                                                                                                              |
| NFR-9  | `os.Logger` with subsystem = bundle ID; Copy Diagnostics collects the last 30 minutes, settings and state log, with no personal data except device names |
| NFR-10 | Release builds contain no test hooks                                                                                                                     |

## 8. Test strategy and end-to-end tests

Every requirement has an automated check in CI, using a virtual audio device and recording fakes; a scripted hardware suite with a real Echo covers what CI cannot, and its report is attached to each release.

**Test levels**

| Level             | Tool                                          | Runs                      | Covers                                                                                                               |
| ----------------- | --------------------------------------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| L1 Unit           | Swift Testing (`swift test`)                  | Every PR                  | `SignalGenerator`; every row of the §5 transition table as a table-driven test; cut-off rules; UID parsing; settings |
| L2 Integration    | Swift Testing on a macOS runner               | Every PR                  | `KeepAliveEngine` and `DeviceMonitor` against a virtual device                                                       |
| L3 E2E            | Shell scripts + `kactl` against the E2E build | Every PR                  | Whole app behavior, scenarios E2E-1 to E2E-14                                                                        |
| L4 Release checks | Shell scripts on the final DMG                | Every tag                 | E2E-15                                                                                                               |
| L5 Soak           | E2E build, 6 hours                            | Nightly                   | E2E-16                                                                                                               |
| L6 Hardware       | `scripts/e2e/hardware.sh` with a real Echo    | Before each minor release | E2E-H1 to E2E-H5                                                                                                     |

Coverage gate: 85% line coverage for `KeepAliveCore`; CI fails below it.

**CI test environment**

- `scripts/e2e/setup-ci.sh` installs the open-source [BlackHole](https://github.com/ExistentialAudio/BlackHole) virtual audio driver (`brew install --cask blackhole-2ch`), restarts `coreaudiod`, and checks the device exists.
- `kactl vdev create --name "E2E Speaker" --uid e2e-speaker` creates an aggregate device on top of BlackHole (`AudioHardwareCreateAggregateDevice`); `kactl vdev destroy` removes it. This simulates the speaker appearing and disappearing.
- `kactl record --device BlackHole --seconds N --out file.wav` captures what the app actually sends, through BlackHole's loopback.
- The app runs with `--fake-bluetooth --fake-helper`, so Bluetooth and helper calls are recorded, not executed. E2E-12 uses the real helper.
- Each script prints TAP output; `scripts/e2e/run-all.sh` collects JUnit XML, the app log and the transitions log as CI artifacts.

**Signal assertion** (shared helper `scripts/e2e/lib/assert_signal.py`)

- Tone mode: dominant frequency 30 Hz ± 1 Hz; RMS within ±20% of 0.000707; no run of zero samples longer than 20 ms.
- Silence mode: all samples zero and the target reports `kAudioDevicePropertyDeviceIsRunningSomewhere = 1`.

**Automated scenarios**

| ID     | Script                    | Steps                                                                                       | Pass when                                                                                                                                                                                                                 |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| E2E-1  | `01_launch_waiting.sh`    | Launch with no target present                                                               | State Waiting; no assertion from the app in `pmset -g assertions`                                                                                                                                                         |
| E2E-2  | `02_target_appears.sh`    | Create the virtual device, select it                                                        | Streaming within 2 s; signal assertion passes; assertion `PreventUserIdleSystemSleep` held by the app                                                                                                                     |
| E2E-3  | `03_default_output.sh`    | Switch the default output to another device                                                 | Target still streaming; the other device not driven by the app                                                                                                                                                            |
| E2E-4  | `04_target_disappears.sh` | Destroy the virtual device                                                                  | Waiting within 1 s; assertion released; fake helper got `setSleepDisabled(false)`                                                                                                                                         |
| E2E-5  | `05_persistence.sh`       | Quit and relaunch                                                                           | Same target by UID; Streaming within 2 s                                                                                                                                                                                  |
| E2E-6  | `06_sample_rate.sh`       | Change BlackHole from 48 kHz to 44.1 kHz                                                    | One engine restart in the log; signal assertion passes                                                                                                                                                                    |
| E2E-7  | `07_will_sleep.sh`        | `kactl simulate will-sleep`                                                                 | Log order: `closeConnection` once, helper flag cleared, assertion released, Suspended; finished in under 5 s                                                                                                              |
| E2E-8  | `08_dark_wake.sh`         | `simulate did-wake`, no unlock, wait 30 s                                                   | No `openConnection` call                                                                                                                                                                                                  |
| E2E-9  | `09_unlock_reconnect.sh`  | `simulate unlock`, then recreate the device                                                 | `openConnection` exactly once; Streaming                                                                                                                                                                                  |
| E2E-10 | `10_reconnect_fails.sh`   | Fake `openConnection` fails                                                                 | One retry at 10 s ± 1 s; then Waiting; no further calls for 60 s                                                                                                                                                          |
| E2E-11 | `11_lid_mode_cutoffs.sh`  | Enable lid mode; `simulate battery 19`; restore; `simulate thermal serious`; destroy device | `setSleepDisabled(true)` only while Streaming and above cut-off; `false` on each cut-off; notification posted                                                                                                             |
| E2E-12 | `12_helper_failsafe.sh`   | Load the real helper with `sudo launchctl bootstrap`; enable lid mode; `kill -9` the app    | `pmset -g` shows `SleepDisabled 1`, then `0` within 2 s; restarting the helper also leaves `0`                                                                                                                            |
| E2E-13 | `13_never_connects.sh`    | Run E2E-1 to E2E-11 and count fake Bluetooth calls                                          | `openConnection` only in E2E-9 and E2E-10                                                                                                                                                                                 |
| E2E-14 | `14_performance.sh`       | Stream for 10 minutes; `kactl metrics`                                                      | NFR-1 and NFR-2 met; render callback p99 under 25% of the buffer period                                                                                                                                                   |
| E2E-15 | `15_release_artifact.sh`  | Mount the DMG                                                                               | `codesign --verify --deep --strict`, `spctl -a -vv` accepted, `stapler validate`, `lipo -archs` shows arm64 and x86_64, `LSUIElement` true, helper plist present, no `E2E_HOOKS` symbols or `kactl` strings in the binary |
| E2E-16 | `16_soak.sh`              | 6 hours streaming with device churn every 10 minutes                                        | No crash; `leaks` reports 0; memory growth under 2 MB                                                                                                                                                                     |

**Hardware suite** (`scripts/e2e/hardware.sh`, owner's Mac with a real Echo)

The script guides the tester step by step, reads state from the app, asks yes or no questions where only a human can hear, and writes `e2e-report-<version>-<mac>.json`, which the owner uploads to the GitHub Release with `gh release upload`.

| ID     | Scenario                                                               | Pass when                                                                     |
| ------ | ---------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| E2E-H1 | 8 hours, lid open, Mac idle                                            | 0 unplanned disconnects in the state log; tester heard no announcement        |
| E2E-H2 | 2 hours lid closed on power, then 2 hours on battery above the cut-off | 0 disconnects; flag cleared at the cut-off                                    |
| E2E-H3 | Overnight sleep with Power Nap on                                      | No reconnect before unlock; one reconnect after unlock                        |
| E2E-H4 | FR-13 spike: reconnect with the Mac-side volume at 0, then at 50%      | Tester reports the announcement quieter or silent at 0; result decides FR-13  |
| E2E-H5 | Install the release DMG on a Mac that never had the app                | Opens with no warning; helper approval flow works; streaming within 2 minutes |

## 9. Repository, CI/CD and release

Merging the release PR is the only manual step; tagging, signing, notarization, publishing, the update feed and the Homebrew cask are automated.

**Repository layout** (public, MIT)

```
/
├── project.yml                 # XcodeGen spec; .xcodeproj is generated, not committed
├── App/                        # SwiftUI menu, AppState wiring
├── SleepHelper/                # privileged launchd daemon + its plist
├── Tools/kactl/                # E2E control CLI (E2E configuration only)
├── Packages/KeepAliveCore/     # Sources/, Tests/ (unit + integration)
├── Resources/                  # Assets, Info.plist, entitlements, Localizable.xcstrings
├── scripts/
│   ├── build.sh  sign.sh  notarize.sh  make-dmg.sh  appcast.sh
│   └── e2e/                    # setup-ci.sh, run-all.sh, NN_*.sh, hardware.sh, lib/
├── docs/                       # GitHub Pages site: landing page, appcast.xml, FAQ
├── .github/
│   ├── workflows/              # ci, nightly, release-please, release, pages, cask
│   ├── ISSUE_TEMPLATE/         # bug report asks for macOS, Mac model, speaker, diagnostics
│   ├── pull_request_template.md
│   └── dependabot.yml
├── Makefile                    # make test | e2e | e2e-hardware | release-local
└── README.md  CHANGELOG.md  LICENSE  CONTRIBUTING.md  CODE_OF_CONDUCT.md  SECURITY.md
```

**Conventions**

- Semantic Versioning; tag `vX.Y.Z` sets `CFBundleShortVersionString`; the CI run number sets `CFBundleVersion`.
- Conventional Commits; release notes and CHANGELOG generated by release-please.
- `main` protected: PRs only, all CI jobs green, linear history.
- Bundle ID `io.github.<owner>.<app>`; helper `io.github.<owner>.<app>.helper`.

**Workflows**

| Workflow             | Trigger                              | Jobs                                                                                                                                 |
| -------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `ci.yml`             | PR, push to `main`                   | Lint (SwiftLint, SwiftFormat); L1 + L2 with coverage gate; build E2E configuration; L3 E2E-1 to E2E-14; upload JUnit, logs, coverage |
| `nightly.yml`        | Daily schedule                       | L5 soak (E2E-16) on `main`                                                                                                           |
| `release-please.yml` | Push to `main`                       | Maintains the release PR; merging it creates the tag and a draft release                                                             |
| `release.yml`        | Tag `v*.*.*`                         | Steps below                                                                                                                          |
| `pages.yml`          | Push to `docs/` or release published | Deploys the GitHub Pages site and `appcast.xml`                                                                                      |
| `cask.yml`           | Release published                    | Bumps version and SHA-256 in the `homebrew-tap` repo                                                                                 |

**`release.yml` steps**

1. Check out the tag; run L1–L3 again.
2. Import the Developer ID Application certificate into a temporary keychain.
3. Archive the Release configuration (universal); export with Developer ID; sign the helper and app with Hardened Runtime and secure timestamp.
4. Build and sign the DMG.
5. Notarize with `xcrun notarytool submit --wait` (App Store Connect API key); fail on any status but Accepted and print the log.
6. Staple the app and the DMG.
7. Run E2E-15 on the stapled DMG.
8. Zip the app with `ditto`; sign it with Sparkle `sign_update`; regenerate `docs/appcast.xml`.
9. Create `SHA256SUMS` and a build provenance attestation (`actions/attest-build-provenance`).
10. Publish the release with DMG, zip, checksums and notes; trigger `pages.yml` and `cask.yml`.

**Pipeline security**

- Third-party actions pinned by commit SHA; Dependabot updates them.
- Default `permissions: contents: read`; write scopes only on the release job.
- Signing secrets only in the protected `release` environment; never available to forked PRs.
- Pin the Xcode version with `xcode-select`; cache Swift packages by `Package.resolved`.

**Update feed and domain**

The Sparkle feed URL is baked into each build, so the GitHub Pages URL (`https://<owner>.github.io/<repo>/appcast.xml`) must keep working forever. If a .dev domain comes later, add it as a custom domain on the same Pages site so the old URL redirects, rather than changing the feed URL in the app.

**Homebrew**

Start with a personal tap: `brew install --cask <owner>/tap/<app>`. Submit to the official homebrew-cask repository once the project meets its notability rules.

## 10. Apple Developer setup and secrets

The Apple Developer Program costs $99 per year; shipped releases keep working if it lapses, but new releases cannot be notarized.

**One-time setup (owner)**

- [ ] Enroll in the Apple Developer Program as an individual.
- [ ] Create a Developer ID Application certificate; export it with its private key as a password-protected `.p12`.
- [ ] Create an App Store Connect API key (Developer role) for `notarytool`; download the `.p8` (only possible once).
- [ ] Fix the bundle IDs (§9) once the name is chosen; they cannot change without breaking updates and the helper approval.
- [ ] Generate the Sparkle EdDSA key pair (`generate_keys`); put the public key in Info.plist.
- [ ] Create the `homebrew-tap` repository and a fine-grained token that can write only to it.
- [ ] Enable GitHub Pages from `docs/` via `pages.yml`.
- [ ] Create the `release` environment with the owner as required reviewer.
- [ ] Back up the `.p12`, `.p8` and Sparkle private key offline. Losing the Sparkle key ends auto-updates for existing users.

**Secrets in the `release` environment**

| Secret                         | Content                                    |
| ------------------------------ | ------------------------------------------ |
| `DEVELOPER_ID_CERT_P12_BASE64` | Base64 of the `.p12`                       |
| `DEVELOPER_ID_CERT_PASSWORD`   | Its password                               |
| `KEYCHAIN_PASSWORD`            | Random password for the temporary keychain |
| `APPLE_TEAM_ID`                | 10-character team ID                       |
| `ASC_API_KEY_ID`               | API key ID                                 |
| `ASC_API_ISSUER_ID`            | Issuer ID                                  |
| `ASC_API_KEY_P8_BASE64`        | Base64 of the `.p8`                        |
| `SPARKLE_ED_PRIVATE_KEY`       | Sparkle EdDSA private key                  |
| `HOMEBREW_TAP_TOKEN`           | Token for the tap repository               |

CI E2E builds are ad-hoc signed and need no secrets; in the E2E configuration the helper's code-signing requirement checks the bundle identifier only.

## 11. Milestones, acceptance and open questions

Four milestones, each ending with its tests green in CI; v1.0 ships when all four are done and the hardware suite passes.

| Milestone                   | Scope                                                                                                                    | Exit criteria                                                                                                    |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| M1 Core and spike           | `KeepAliveCore` (devices, engine, signal, power assertion, state machine); `kactl`; CI test environment; FR-1 to FR-9    | L1, L2 and E2E-1 to E2E-6 green; E2E-H4 run on a real Echo, result recorded, FR-13 kept or dropped               |
| M2 App and sleep handling   | Menu UI, first run, settings; `SleepCoordinator`, `BluetoothController`; FR-11, FR-12, FR-16 to FR-18                    | E2E-7 to E2E-10 and E2E-13 green; E2E-H3 passes                                                                  |
| M3 Lid-closed mode          | `SleepHelper`, `HelperClient`, cut-offs, approval flow; FR-10, FR-14, FR-15                                              | E2E-11 and E2E-12 green; E2E-H2 passes                                                                           |
| M4 Release and distribution | release-please, `release.yml`, notarization, Sparkle, Pages, cask, README and site                                       | A test tag produces a notarized release; E2E-14 to E2E-16 green; E2E-H5 passes; Sparkle updates v0.9.0 to v0.9.1 |

**v1.0 acceptance**

- [ ] Every MUST requirement implemented and mapped to at least one passing test ID.
- [ ] E2E-1 to E2E-16 green on the release commit.
- [ ] E2E-H1 to E2E-H5 pass; report attached to the release.
- [ ] README covers install, helper approval, sleep limits, battery and heat cost, Sleep Now, line-in alternative, uninstall, and "not affiliated with Amazon".
- [ ] Final name chosen and bundle IDs fixed.

**Open questions**

| Question                                                                | How it gets answered     | Default until then                                 |
| ----------------------------------------------------------------------- | ------------------------ | -------------------------------------------------- |
| Does macOS reconnect the Echo on its own after the app disconnected it? | E2E-H3                   | FR-12 reconnects after unlock                      |
| Does the Echo keep the link with pure zeros?                            | E2E-H1 in Silence mode   | Tone is the default                                |
| Does the announcement follow the Mac-side volume?                       | E2E-H4                   | Answered 17 October 2026: no. E2E-H4 on an Echo Studio (Mac16,12, macOS 27.0.1) heard the announcement at its usual loudness at Mac-side volume 0 and at 50%, and the volume stayed at 0 across the reconnect. FR-13 dropped |
| Will `kIOPMSleepDisabledKey` keep working on future macOS?              | Check on each macOS beta | `pmset disablesleep` fallback                      |
| Move the site and feed to a .dev domain?                                | Owner decision           | GitHub Pages; custom domain added on the same site |
| Final product name                                                      | Appendix                 | Purrlo (decided)                                   |

## Appendix: name candidates

Purrlo is the strongest candidate: both the .dev and .app domains are free and no app or product uses the name; Hushlo, Tethy and Mumly follow with a free .dev domain and no conflicts.

Checked on 17 October 2026: .dev and .app through the domain registry's RDAP service, GitHub account names on github.com, existing apps and products by web search. Names whose .dev domain is taken were not searched for conflicts. This is not a trademark search; check the EUIPO and USPTO databases before committing.

| Name       | Idea                    | .dev  | .app  | GitHub user           | Existing products found                                                                                          |
| ---------- | ----------------------- | ----- | ----- | --------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Purrlo** | A soft, constant purr   | Free  | Free  | Taken (empty account) | None                                                                                                             |
| **Hushlo** | Hushes the announcement | Free  | Taken | Taken (empty account) | None; "HushLoop" sleep app sounds alike                                                                          |
| **Tethy**  | Tethered to the speaker | Free  | Taken | Free                  | None                                                                                                             |
| **Mumly**  | Keeps the speaker mum   | Free  | Taken | Free                  | None; "Momly" pregnancy app sounds alike                                                                         |
| Humlo      | A quiet hum             | Free  | Taken | Taken (empty account) | None                                                                                                             |
| Hummo      | A quiet hum             | Free  | Taken | Taken (empty account) | None; "humm" payments app sounds alike                                                                           |
| Snugo      | A snug connection       | Free  | Taken | Taken                 | None                                                                                                             |
| Holdo      | Holds the link          | Free  | Free  | Taken                 | [holDO](https://mwm.ai/apps/holdo/6599853905) food-delivery app                                                  |
| Lullo      | Lulls it quiet          | Free  | Taken | Taken (empty account) | An [Android developer named Lullo](https://www.appbrain.com/dev/Lullo/)                                          |
| Stayo      | Stays connected         | Free  | Taken | Taken (empty account) | A company called [Stayo](https://www.autotouch.ai/prospecting/stayo)                                             |
| Hushy      | Hushes it               | Free  | Taken | Taken                 | [Hushy – Baby Sleep Sounds](https://apps.apple.com/us/app/hushy-baby-sleep-sounds/id1542791240) on the App Store |
| Clingo     | Clings to the speaker   | Free  | Taken | Taken                 | The [Clingo](https://potassco.org/clingo/c-api/current/) logic solver                                            |
| Keepy      | Keeps it alive          | Taken | Free  | Taken                 | Not checked                                                                                                      |
| Shushy     | Shushes it              | Taken | Taken | Taken                 | Not checked                                                                                                      |
| Purrly     | A soft purr             | Taken | Taken | Taken                 | Not checked                                                                                                      |
| Nudgy      | Nudges it awake         | Taken | Taken | Taken                 | Not checked                                                                                                      |
| Pairly     | Stays paired            | Taken | Taken | Taken                 | Not checked                                                                                                      |
| Bondo      | Bonded to it            | Taken | Taken | Taken                 | Not checked                                                                                                      |
| Linky      | Keeps the link          | Taken | Taken | Taken                 | Not checked                                                                                                      |
| Calmo      | Keeps it calm           | Taken | Taken | Taken                 | Not checked                                                                                                      |

A taken GitHub user name does not block the project: the repository can live at `github.com/<owner>/<name>`, and the Homebrew cask uses the app name.
