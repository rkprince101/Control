# control

Habit-gated app blocking for Android, Windows, and beyond. Open an app you have
put behind a rule and you get a block screen instead, until the rule says
otherwise: a schedule ends, you walk far enough, you finish the habit you
promised yourself.

## Why the architecture looks like this

iOS can do this properly because Apple hands out the Screen Time API
(`FamilyControls` + `ManagedSettings`), which shields apps below the app layer
and can even forbid its own deletion. No other platform offers an equivalent, so
enforcement strength differs per platform and the app says so out loud rather
than pretending otherwise:

| Tier | Android | Windows |
| --- | --- | --- |
| Deterrent | Accessibility service + block screen. User can switch it off in Settings. **Implemented.** | Service under a non-admin daily account. |
| Strong | Hard mode: the service closes the settings screens that lead to uninstalling or disabling the app. **Implemented.** | Watchdog pair, service ACL. |
| Locked | Device owner: uninstall blocked, safe boot disabled, removal needs a factory reset. Enforcement implemented; provisioning flow is not. | Not achievable without a signed kernel driver. |

The rule engine is therefore kept completely separate from enforcement. Every
platform gets the same decisions; only the shield differs.

```
packages/control_core/   Pure Dart. Rules, locks, tamper-resistant clock. No Flutter, no dart:io.
lib/platform/            MethodChannel seam. Ships decisions down, reads measurements up.
lib/state/               Drives the engine, publishes plans.
lib/ui/                  Blocks, Insights, Settings.
android/.../enforcement/ Accessibility service, block screen, cached plan.
android/.../insights/    Usage stats, installed apps.
```

Dart decides, native enforces. Nothing in `android/` re-implements a rule, so
the two sides cannot drift into disagreeing about what is blocked.

### The plan cache

The accessibility service fires on every app switch and must answer in
microseconds, long after the Flutter isolate is dead. So Dart flattens each
evaluation into a plan — a set of package names plus the next moment a decision
could change — and pushes it to `PlanStore`, which the service reads
synchronously. A plan whose wake time has passed keeps being enforced rather
than lapsing: dropping the shield on staleness is a bypass a user would learn to
trigger deliberately.

### Failing closed

Where a signal is missing or too coarse to trust, the engine blocks. No location
fix means a place rule stays on. A GPS reading whose error circle straddles the
zone edge counts as inside for a "block here" rule and as outside for an "unlock
here" rule. Over-blocking is a complaint; under-blocking is a broken promise.

### Uninstall protection

Device admin no longer stops an uninstall. Current Android offers "Deactivate &
uninstall" as one step from the app info screen, so holding admin buys a
confirmation dialog and nothing more.

Every route to removing the app, and what actually closes it:

| Route | Closed by hard mode | Closed by device owner |
| --- | --- | --- |
| Launcher long-press, App info, Uninstall | yes | yes |
| Settings, Apps, Uninstall | yes | yes |
| Play Store, Manage apps, Uninstall | yes | yes |
| Settings search jumping to the app page | yes | yes |
| OEM security/phone-manager uninstallers | mostly | yes |
| Force stop, Clear data | yes | partly |
| Turning the accessibility service off | yes | yes |
| Deactivate device admin | yes | yes |
| **Safe mode boot** | **no** | yes, `DISALLOW_SAFE_BOOT` |
| **`adb uninstall`** | **no** | yes, `setUninstallBlocked` |
| **Shizuku / root `pm uninstall`** | **no** | yes |
| **Second user or guest profile** | **no** | yes, `DISALLOW_ADD_USER` |
| **Factory reset** | **no** | Settings path only |

Hard mode covers everything reachable from the phone's own UI. The bottom five
rows need a PC, a reboot into safe mode, or a wipe, and no ordinary app can
touch them. Only device owner can, and it costs a factory reset to provision.

**Hard mode** ([`TamperRules`](android/app/src/main/kotlin/com/example/control/enforcement/TamperRules.kt))
watches the settings, installer, store, and OEM-manager packages. Three gates,
in order: the class name has to be a screen that can remove or disable an app;
the app name has to appear as a whole word; and a destructive verb has to be on
screen, unless the class already proves intent. Windows are re-checked once
after 350 ms, because a dialog is often reported before its text exists.

All three gates exist because of one bug. The first version tested only for the
app name and a keyword, which closed the Settings home page: the app is called
"Control", that is a substring of "Device controls", and "Accessibility" is an
ordinary menu entry. The rules now live in a pure object with
[JVM tests](android/app/src/test/kotlin/com/example/control/enforcement/TamperRulesTest.kt)
pinning both what must be closed and what must be left alone.

**Device owner** provisioning has a guided flow in Settings, "Uninstall-proof
setup". It reads `isProvisioningAllowed`, which is the same precondition check
the system runs, so it can say whether the command will be accepted before the
user goes near a factory reset.

**The lock.** Hard mode as a plain switch is a hole: open Control, switch it
off, delete the app. So uninstall protection carries the same password or timed
lock the blocks do, held in the same [`LockPolicy`](packages/control_core/lib/src/lock_policy.dart)
and broken only by an emergency unlock.

### Counting screen time

Exactly one app is in the foreground at a time, and
[`UsageMath`](android/app/src/main/kotlin/com/example/control/insights/UsageMath.kt)
models it that way: a resume closes whatever was open before it, and the screen
going off closes it too.

Tracking a start time per package independently looks equivalent and is not.
Pause events go missing — an app killed in the background, an `ACTIVITY_STOPPED`
where a pause was expected, a dropped event — and every package left open then
gets credited to the end of the window. That showed up as several apps each
reporting the same two hours the user had actually spent in one of them.

### Storage

State is one JSON file, written to a temp path and renamed into place, so a
crash mid-write leaves the previous good file rather than a truncated one. It
was `shared_preferences`; a single consistent document is easier to reason
about, and `adb`-readable when the bug being chased is "my rules vanished".

Writes go through a future that opens the file, never through a nullable field:
a block created in the first moments after launch used to be dropped, and then
the load that finished afterwards cleared the list on top of it.

### Time

Nothing checks a lock against `DateTime.now()` alone, because winding the device
clock back is the cheapest attack there is. `TamperResistantClock` takes the
latest of the system clock, a trusted anchor projected forward by monotonic
uptime, and a persisted high-water mark. The anchor survives clock changes but
not reboots; the high-water mark survives reboots. Together, time only moves
forward.

## Status

Working end to end on Android:

- **Time blocks** with multiple ranges per block, windows that wrap past
  midnight, a weekday picker, and Block-during / Unblock-during polarity.
- **Condition blocks** earned with steps, app time, or a shortcut channel,
  combinable, with a "block again after" re-arm.
- **Steps** from the hardware step counter, with a daily baseline that survives
  reboots.
- **Shortcut channels** fired by NFC tag, QR code, home-screen shortcut, or an
  automation app, with a repeat count.
- **Locks**: password, or timed for 24h to a year. A timed lock refuses the
  password too; only an emergency unlock breaks it, and the five never refill.
- **Uninstall protection** via device admin, upgraded to a hard block when the
  app is device owner. Releasing it is refused while any timed lock is running.
- **Insights**: screen time, pickups, per-app breakdown from usage events, over
  a day, week, or month. The accumulation is a pure object with
  [tests](android/app/src/test/kotlin/com/example/control/insights/UsageMathTest.kt),
  because every bug it has had was an undercount, and an undercount never looks
  like a bug.
- **Place check-in**: be inside a zone during a time window and check in there.
  The zone is picked on an OpenStreetMap map or from the current fix, and a
  check-in is refused unless the whole accuracy circle sits inside it.
- **Website blocking**: per block, matched from the browser address bar across
  the common browsers. Covers subdomains, ignores search queries, works in
  incognito. A site opened inside another app is still a way through.
- **Themes**: system, light, black, pitch black.
- **Focus timer**: pomodoro or stopwatch started from the block card. Put in
  four hours, get thirty minutes of the apps you ration. Per-block statistics
  behind the chart button.
- **Hard mode**: the accessibility service backs out of the Android screens used
  to uninstall or disable Control. See "Uninstall protection" below for what it
  does and does not buy.
- **Editing**: tapping a block card opens it. A locked block opens too, with
  everything but its name and icon held shut.
- **Block icons** from the bundled set in `assets/icons`.
- Blocks, locks, grants, and the unlock budget persist across restarts, in a
  single atomically written `control_state.json` under the app support
  directory.

Not built yet, in rough priority order:

1. **Scheduled re-evaluation.** `AlarmManager` at `nextWakeAt` plus a boot
   receiver, waking a headless Dart isolate to republish. Until this lands a
   schedule only flips while the app is open or has been resumed.
2. **Health Connect.** Workout and mindfulness conditions, and steps aggregated
   across fitness apps rather than read from one sensor.
3. **Foreground service for the focus timer.** Sessions survive the process
   dying because their start time is on disk, but a live notification with the
   running clock is what people expect.
4. **Monotonic clock anchor.** `SystemClock.elapsedRealtime` from native, so the
   tamper-resistant clock survives a reboot plus a clock change together.
5. **Place and Device modes.** Engine supports both; needs geofencing and
   Bluetooth/Wi-Fi signals. Deliberately hidden in the editor until then.
6. **Windows.**

## Design

Material 3, with the tonal palettes generated from the accent green by
`ColorScheme.fromSeed`. The `neutral` scheme variant is used deliberately: the
default tints every surface towards the seed, which on a near-black app reads as
a green cast across the whole screen.

`ControlColors` is now derived from the `ColorScheme` rather than held beside
it, so there is one source of colour and the app-specific names (`card`,
`cardRaised`, the `heavy`/`medium`/`light` severity ramp) stay readable at the
call site while resolving to real M3 roles.

Depth comes from the surface-container family, not shadows: M3 replaced
elevation overlays with tonal surfaces, and a drop shadow under a container that
is already lighter than the page is a second, competing cue. Selection state
everywhere uses `secondaryContainer` with `onSecondaryContainer`, which is what
makes the nav pill, the chips, the segmented controls and the weekday circles
read as one system.

Type is Nunito across the M3 scale. Rounded to match the shape scale, and chosen
over the more geometric rounded faces because this app is mostly numbers:
durations, step counts, times and percentages. Nunito keeps a tall x-height and
unambiguous digits at 12sp, where the rounder display faces turn 6, 8 and 0 into
the same blob.

## Surfaces outside the app

The home-screen widget, the Quick Settings tile and the weekly notification all
wake without a Flutter isolate, so none of them can run the rule engine. Dart
writes a flattened `Summary` whenever it recomputes, and they read it. The
strings are formatted in Dart rather than Kotlin: the formatting rules live
there, and a second copy is how two screens end up disagreeing about the same
number.

The tile is read-only by design. A tile that could switch blocking off would be
a bypass sitting in the notification shade, reachable from the lock screen,
which is the opposite of the point.

## Supported versions

Android 7.0 (API 24) and up. Every enforcement path works there: usage events
are API 21, the step counter 19, device admin 21, and every newer call is behind
a runtime version check. Adaptive icons and Health Connect need API 26, so the
launcher icon falls back to a layer-list on Android 7 and Health Connect will
gate itself at runtime when it lands, rather than costing those users the app.

Worth knowing: device admin still blocks uninstall properly on Android 7. The
"Deactivate & uninstall" shortcut that made admin toothless arrived later, so
protection is stronger there than on a current release.

## Development

```bash
flutter test
(cd packages/control_core && dart test)
(cd android && ./gradlew :app:testDebugUnitTest)
```

The engine is pure and has no platform dependencies, so its tests run anywhere
and cover the parts that matter: midnight-wrapping schedules, polarity, grant
expiry, coarse-fix handling, clock rollback.

## Known decision to make

`applicationId` is still `com.example.control`. It has to change before any
build reaches a real device, and it is awkward to change later: the accessibility
service is identified by component name, so a rename looks like a new service to
Android and the user has to grant it again.
