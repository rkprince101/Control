# Control

**Habit-gated app blocking for Android, Windows, and beyond.**

Open an app you have put behind a rule and you get a block screen instead, until
the rule says otherwise: a schedule ends, you walk far enough, you finish the
habit you promised yourself.

Built with Flutter and a pure-Dart rule engine. Android also evaluates persisted
rules natively so schedules and allowance expiry work without Flutter running.

![Platform](https://img.shields.io/badge/platform-Android%207.0%2B-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Setting up on the device](#setting-up-on-the-device)
- [Project structure](#project-structure)
- [Architecture](#architecture)
  - [Why it looks like this](#why-it-looks-like-this)
  - [The plan cache](#the-plan-cache)
  - [Failing closed](#failing-closed)
  - [Uninstall protection](#uninstall-protection)
  - [Counting screen time](#counting-screen-time)
  - [Storage](#storage)
  - [Time](#time)
- [Surfaces outside the app](#surfaces-outside-the-app)
- [Design](#design)
- [Supported versions](#supported-versions)
- [Development](#development)
- [Roadmap](#roadmap)
- [Known decision to make](#known-decision-to-make)
- [Contributing](#contributing)
- [License](#license)

---

## Features

Implemented on Android; not yet tested on a physical device:

- **Time blocks** with multiple ranges per block, windows that wrap past
  midnight, a weekday picker, and Block-during / Unblock-during polarity.
- **Condition blocks** earned with steps, app time, or a shortcut channel,
  combinable, with one earned allowance per rule per day. Expired, spent grants
  remain until the next day, so cumulative daily signals cannot indefinitely
  mint new allowances after "block again after" expires.
- **Persistent app categories**: `browser`, `game`, and opt-in `all_apps`, with
  per-rule exclusions. Categories resolve dynamically against the foreground
  app, including new installs, rather than freezing a package list when saved.
  Browsers are detected by capability; games by Android category metadata or the
  legacy game flag. Misdeclared apps cannot be identified reliably. `all_apps`
  is stronger launchable-app blocking, excluding essential system components
  and current phone safety flows. A category exclusion only exempts that rule's
  category match: explicit app blocks and other rules still apply.
- **Steps** from the hardware step counter, with a daily baseline that survives
  reboots.
- **Shortcut channels** fired by NFC tag, QR code, home-screen shortcut, or an
  automation app, with a repeat count.
- **Locks**: password, or timed for 24h to a year. A timed lock refuses the
  password too; only an emergency unlock breaks it, and the five never refill.
  Store-level mutation checks protect both lock types, not just editor controls.
  Live locks cannot be replaced; locked rules cannot gain exclusions or lose
  categories. Tightening restrictions is allowed.
- **Uninstall protection** via device admin and best-effort accessibility guards,
  with stronger OS restrictions under optional device owner. No tier guarantees
  uninstall prevention. In-app release is refused while any timed lock is running;
  supported emergency-unlock and release paths remain available under lock policy.
- **Insights**: actual Android usage-event timelines for Day (hourly), Week
  (trailing 7 local calendar days), and Month (trailing 30), including today.
  Tap accessible chart bars for interval screen time and pickups. App rankings
  show icons, duration, and share of the selected period's total; app details
  can open Create a block with that app preselected. Pull-to-refresh, loading,
  empty, permission, and retryable error states are explicit; stale responses
  cannot overwrite a newer request. No fabricated comparisons or saved-time
  claims. See [Counting screen time](#counting-screen-time) for history limits.
- **Place check-in**: be inside a zone during a time window and check in there.
  The zone is picked on an OpenStreetMap map or from the current fix, and a
  check-in is refused unless the whole accuracy circle sits inside it.
- **Website blocking**: per block, matched from the browser address bar across
  supported address-bar IDs only. Covers subdomains and ignores search queries;
  incognito is covered only when a supported address bar is exposed. Embedded
  app browsers are unsupported. Browser category detection does not imply
  address-bar support for website blocking.
- **Themes**: system, light, black, pitch black.
- **Motion**: the wavy progress bars travel continuously; Settings chooses Off,
  Calm or Lively, and Android's remove-animations setting stops them.
- **Focus timer**: pomodoro (15/25/50/90 min) or stopwatch from the block card.
  One sheet runs the whole cycle: start, a live face (a wavy ring filling
  toward the end of a pomodoro or break; a sixty-tick dial for a stopwatch,
  which has no end to fill toward), pause and resume (paused time is not credited), finish, then a
  5 minute break, 15 after every fourth pomodoro. A pomodoro ends itself at its
  finish line, even with the app closed, and its minutes land on the day they
  were worked. Reaching the daily goal mid-session unlocks at once, without
  pressing stop. An ongoing notification shows the running clock (Android runs
  it, no service), and a sounding one marks the end of a session or break
  from a foreground service, on the minute, with a backup alarm if the
  process is gone. Put
  in four hours, get thirty minutes of the apps you ration. Per-block
  statistics (today, week, sessions, longest, average, streak, completed
  pomodoros, a week chart against the goal, a six-week heatmap, and recent
  sessions) open from the chart button in the same sheet style as the editor.
- **Hard mode**: the accessibility service attempts to back out of recognized
  Android screens used to uninstall or disable Control. See [Uninstall protection](#uninstall-protection)
  for what it does and does not buy.
- **Home-screen widget, Quick Settings tile, weekly notification** that read a
  flattened summary without waking Flutter. The tile is read-only by design.
- **Notifications you can trust**: permission and exact-timing status in
  Settings, warnings where a reminder or report could not arrive, alarms
  re-armed after reboots and clock changes, and a foreground service for the
  running focus timer. See [Notifications, alarms and the foreground service](#notifications-alarms-and-the-foreground-service).
- **Editing**: tapping a block card opens it. A locked block opens too, with
  cosmetic edits and permitted tightening, but no weakening of active locks.
- **Block icons** from the bundled set in `assets/icons`.
- **Habits**: track things done once a day (check), counted in units (count,
  e.g. 8 glasses), or timed (timer, keeps running with the app closed and
  splits a run across midnight). Each habit has a name, description, icon,
  colour, due weekdays and any number of reminders. Cards show a tile grid of
  recent weeks, the current and best streak, and the 30-day completion rate;
  the detail sheet adds a Week / Month / Year progress box (a bar per day, or
  per month for a year, filled toward that day's or month's goal, with the
  period's goal, amount completed and completion share, and arrows to step
  back through earlier periods) and a GitHub-style history: a column per
  week back to the habit's first day, scrolling sideways from the latest,
  shaded by how much of each day was done. Tapping any past day selects it
  for logging just below, which is how a missed day gets filled in. A day off never breaks a streak. Days done climb a rank ladder
  (Seed to Old growth), drawn: a compact card on the Habits page shows the
  plant swaying and growing a little with every check-in, and opens a sheet
  with the full scene, the pace and a projected date for the next stage, the
  journey with the day each stage was reached, and how growth works. A new
  stage is celebrated once. Nothing ever wilts: a missed day slows growth but
  never takes it back. A habit's history starts the day it was created: days
  before it cannot be logged, and it is not due on them. Sixteen colours. Reminders are native alarms, on
  the minute when exact timing is allowed, that re-arm themselves, survive
  reboots, and stay quiet once the habit is done that day.
- **Todos**, ported from Hushroom: each todo is due on a day or has no due
  date. A day shows what is overdue (in red), due, upcoming, undated, and
  finished on it; unfinished todos carry forward as overdue, and one finished
  after its day is marked late. A month date strip moves between days, a bar
  shows the day's progress, and the composer adds todos one after another.
  Swipe a todo left to edit or delete it; tap it for its steps, which tick
  the todo off when all are done (and are all ticked when it is). The drawer
  counts what is still open today.
- **Notes**, ported from Hushroom: rich text (bold, italic, underline,
  strikethrough, three heading sizes, checklists, bullet and numbered lists,
  text colour) in a full-screen editor that saves as you type and discards
  a note left empty. The list is searchable, pinned first; swipe right to
  pin, left to delete. Todos and notes also show up in the top search.
- **Money**, ported from Productivity Island: a month-by-month income and
  expense log in any of 44 currencies. Each month opens on the balance the
  last one closed on (brought forward) and shows its surplus or deficit,
  income against spending, and the entries in expense and income lists.
  Stats has the savings rate, a donut per side by category, a year of daily
  spending as a scrollable heatmap (days money came in are framed; tap one
  for what happened that day, or to add to it), and where the month's money
  went. Manage gathers investments (expenses filed under Investment, with
  any returns), budgets over any range of days, optionally for one category,
  and money lent or borrowed, settled with a tap. Deletes can be undone from
  the snackbar.
- **App lock**, ported from Productivity Island: a PIN of 4 to 12 digits in
  front of any pages you choose (everything but Settings, which holds the
  PIN's own controls, and asks for it before they change). A locked page is
  not built at all: it shows a number pad, opens on the digit that completes
  the PIN, keeps its contents out of search, its count out of the drawer and
  its rules out of the drawer's list. Pages lock again whenever you leave the
  app, or at once from the lock in the search bar. Only a salted SHA-256 of
  the PIN is stored: privacy from whoever picks the phone up, not a vault.
- **Navigation** laid out like Gmail: a floating search bar (menu, search
  across rules, habits and pages, and a status avatar that opens Settings), a
  modal drawer listing pages with live counts and every rule as a label, and a
  Compose-style action button that shrinks while scrolling. Wide screens get a
  rail with the menu and action at its head, expanding in place.
- Blocks, locks, grants, and the unlock budget persist across restarts, in a
  single atomically written `control_state.json` under the app support
  directory.

---

## Requirements

| Tool | Version | Notes |
| --- | --- | --- |
| Flutter | 3.44 or later | Stable channel. `flutter doctor` should be clean for Android. |
| Dart | 3.12.2 or later | Ships with Flutter; `pubspec.yaml` pins `sdk: ^3.12.2`. |
| Android SDK | API 24 to latest | `minSdk = 24`. `compileSdk` / `targetSdk` follow Flutter's defaults. |
| JDK | 17 | Kotlin `jvmTarget = 17`. |
| Android Studio or VS Code | any recent | Optional. The CLI is enough. |
| `adb` (Platform Tools) | any recent | Only needed for device-owner provisioning. See [Setting up on the device](#setting-up-on-the-device). |

A physical Android device is strongly recommended. The accessibility service,
usage stats, step counter and device admin all behave differently, or not at
all, on an emulator.

---

## Getting started

Clone and fetch dependencies:

```bash
git clone https://github.com/rkprince101/Control.git
cd Control
flutter pub get
```

Check the toolchain:

```bash
flutter doctor
```

Run on a connected device or emulator:

```bash
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`. Install it
with:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Or build an App Bundle for Play:

```bash
flutter build appbundle --release
```

> Before any build reaches a real device, change `applicationId` in
> [`android/app/build.gradle.kts`](android/app/build.gradle.kts). See
> [Known decision to make](#known-decision-to-make) for why this is awkward to
> do later.

---

## Setting up on the device

Control needs several system-level grants. The app walks through each one in
**Settings**, but here is what they are and why.

| Grant | Where | Why |
| --- | --- | --- |
| **Accessibility service** | Settings, Accessibility, Control | Post-launch shield on foreground/content events and roughly one-second foreground checks. Required for app and website blocking. |
| **Usage access** | Settings, Apps, Special access, Usage access | Screen-time insights and "app time" conditions read usage events. |
| **Notifications** | Prompted at first run (API 33+) | The weekly report and focus-timer notifications. |
| **Physical activity** | Prompted when a steps condition is created | The hardware step counter. |
| **Location** | Prompted when a place block is created | Place check-in. Fine location; a coarse fix fails closed. |
| **Device admin** | Settings, Uninstall protection | Adds a confirmation step before uninstall. Weak on its own; see below. |
| **Device owner** (optional) | Settings, Uninstall-proof setup | Stronger OS-level uninstall and configuration restrictions, not protection against every privileged bypass. |

### Device owner provisioning

Device owner is the strongest tier, but not bypass-proof. It is optional and
requires deliberate provisioning, not an ordinary permission prompt. Android only
accepts the command on a device with **no Google or other accounts added**, so
provisioning usually means a factory reset first. The in-app flow reads
`isProvisioningAllowed`, which is the same check the system runs, and tells you
whether the command will be accepted before you go near a reset.

Once the device is account-free, with USB or wireless debugging on:

```bash
adb shell dpm set-device-owner com.example.control/.enforcement.ControlDeviceAdminReceiver
```

The app shows the exact component string for your build under
**Settings, Uninstall-proof setup**. To release device owner later:

```bash
adb shell dpm remove-active-admin com.example.control/.enforcement.ControlDeviceAdminReceiver
```

Command-based removal depends on Android's admin-removal policy and build;
it is not a guaranteed recovery path. In-app release is refused while any timed
lock is running. The supported emergency-unlock and release flows are preserved;
understand them before provisioning.

The Settings page includes a card explaining what `adb` is, where to get it,
and why wireless debugging is the route that works the same on every make.

---

## Project structure

```
control/
├── lib/                          Flutter app
│   ├── main.dart                 Entry point, theme wiring, HomeShell
│   ├── data/                     Local store, block codec, focus sessions, habits, todos, notes, money, page lock, password hashing
│   ├── platform/                 MethodChannel seam. Ships plans/rules down, reads measurements up.
│   ├── state/                    ControlStore. Drives the engine, publishes plans.
│   └── ui/                       Blocks, Habits, Todos, Notes, Money, Insights, Settings, page lock, navigation shell, sheets, theme
│
├── packages/control_core/        Pure Dart rule engine. No Flutter, no dart:io.
│   ├── lib/src/engine.dart       Evaluates blocks into plans
│   ├── lib/src/lock_policy.dart  Password and timed locks, emergency unlock budget
│   ├── lib/src/clock.dart        TamperResistantClock
│   ├── lib/src/models.dart       Blocks, conditions, schedules, grants
│   └── test/                     Engine and lock tests
│
├── android/app/src/main/kotlin/com/example/control/
│   ├── MainActivity.kt
│   ├── bridge/ControlBridge.kt   MethodChannel handler
│   ├── enforcement/              Accessibility service, block overlay, plan cache,
│   │                             device admin, tamper guard and rules, web rules, boot receiver
│   ├── insights/                 Usage stats, installed apps, steps, location
│   ├── shortcuts/                NFC / QR / shortcut / automation triggers
│   └── surface/                  Widget, Quick Settings tile, weekly report, habit reminders, summary store
│
├── android/app/src/test/kotlin/  JVM tests: TamperRules, WebRules, UsageMath, PlanCodec, HabitReminders
├── test/                         Flutter tests: codec, editor, focus, habits, persistence, goldens
├── assets/icons/                 Bundled block icons
├── ios/ macos/ linux/ windows/ web/   Platform scaffolds (no enforcement yet)
└── pubspec.yaml
```

Dart evaluates conditions and publishes plans and persistent rules. Android
resolves categories and evaluates recurring schedules and `allowedUntil` without
Flutter. Shared semantics need tests on both sides to avoid decision drift.

---

## Architecture

### Why it looks like this

iOS can do this properly because Apple hands out the Screen Time API
(`FamilyControls` + `ManagedSettings`), which shields apps below the app layer
and can even forbid its own deletion. No other platform offers an equivalent, so
enforcement strength differs per platform and the app says so out loud rather
than pretending otherwise:

| Tier | Android | Windows |
| --- | --- | --- |
| Deterrent | Accessibility service + block screen. User can switch it off in Settings. **Implemented.** | Service under a non-admin daily account. |
| Strong | Hard mode: best-effort guards for recognized uninstall/disable screens; OEM and locale dependent. **Implemented.** | Watchdog pair, service ACL. |
| Locked | Optional device owner: stronger OS uninstall, safe-boot and user restrictions, with guided provisioning. Not root-proof or guaranteed uninstall prevention. **Implemented.** | Not achievable without a signed kernel driver. |

The pure-Dart engine remains separate from platform APIs. Android's native
evaluator handles persisted enforcement rules while Flutter is absent.

### The plan cache

Flutter publishes evaluated plans plus persistent rules to
[`PlanStore`](android/app/src/main/kotlin/com/example/control/enforcement/PlanStore.kt),
which the accessibility service reads without waking Flutter. Native rules
evaluate recurring schedules, including `allowDuring` and overnight windows,
and `allowedUntil` expiry. Category membership and per-rule exclusions resolve
against the foreground package, so newly installed browsers/games are covered
without reopening Control. Explicit blocks or another matching rule override
a category exclusion.

Foreground/content events and roughly one-second foreground checks re-evaluate
blocking, including time boundaries while an app is already foreground. This
does not require a live Flutter isolate, but does require the accessibility
service to remain enabled and running. Cached condition decisions are not a
headless Dart sensor evaluation, and stale plans do not simply drop protection.

Enforcement remains an accessibility **post-launch shield**: apps can start
before the shield appears. It is not package suspension and does not block
background execution or network traffic. Website checks only read supported
browser address-bar IDs; embedded app browsers remain unsupported.

### Restarting the phone

After setup, a normal restart does **not** require opening Control. Android
restores the enabled accessibility service; the service immediately loads saved
native rules and checks the foreground, without starting Flutter. Schedules and
expired allowances are evaluated using the current enforcement clock.

The service, block screen and boot receiver support Direct Boot. Native rules,
the hard-mode flag and the clock live in device-protected storage, available
before first unlock. Passwords and habit history remain in credential-protected
storage. Older installations migrate the native preferences automatically after
unlock. System apps, emergency/phone roles and unknown safety states are never
shielded before first unlock, even by explicit app rules.

This is not a zero-delay boot guarantee: Android controls when the service is
bound. A disabled service, force-stop, safe mode or OEM background/autostart
restriction can prevent enforcement; opening Control alone cannot silently
restore a revoked accessibility permission. Enable App blocking once, then test
a real reboot without opening Control. Check vendor autostart/battery settings
if the service is not restored. Physical-device reboot testing is still required.

### Failing closed

Where a signal is missing or too coarse to trust, the engine blocks. No location
fix means a place rule stays on. A GPS reading whose error circle straddles the
zone edge counts as inside for a "block here" rule and as outside for an "unlock
here" rule. Over-blocking is a complaint; under-blocking is a broken promise.

### Uninstall protection

Device admin no longer stops an uninstall. Current Android offers "Deactivate &
uninstall" as one step from the app info screen, so holding admin buys a
confirmation dialog and nothing more.

Protection by route; accessibility behavior is best-effort, not a guarantee:

| Route | Hard mode | Device owner |
| --- | --- | --- |
| Launcher long-press, App info, Uninstall | recognized screens only | OS uninstall restriction |
| Settings, Apps, Uninstall | recognized screens only | OS uninstall restriction |
| Play Store, Manage apps, Uninstall | recognized screens only | OS uninstall restriction |
| Settings search jumping to the app page | recognized screens only | OS uninstall restriction |
| OEM security/phone-manager uninstallers | OEM dependent | OS policy, OEM dependent |
| Force stop, Clear data | recognized screens only | partial; not guaranteed |
| Turning the accessibility service off | recognized screens only | not guaranteed |
| Deactivate device admin | recognized screens only | stronger owner-removal policy |
| **Safe mode boot** | **no** | `DISALLOW_SAFE_BOOT`, where honored |
| **`adb uninstall`** | **no** | `setUninstallBlocked`, subject to OS policy |
| **Shizuku / root `pm uninstall`** | **no** | no guarantee against privileged tools/root |
| **Second user or guest profile** | **no** | `DISALLOW_ADD_USER`; not isolation of existing profiles |
| **Factory reset** | **no** | Settings path only; recovery/wipe remains outside protection |

Hard mode is not immune to all phone-UI bypasses. OEM screens, localization,
missing accessibility content, service shutdown and timing can defeat detection.
Device owner is stronger, not root-proof, and neither tier guarantees uninstall
prevention. Essential system and current phone safety flows must remain usable.

**Hard mode** ([`TamperRules`](android/app/src/main/kotlin/com/example/control/enforcement/TamperRules.kt))
watches the settings, installer, store, and OEM-manager packages. Three gates,
in order: the class name has to be a screen that can remove or disable an app;
the app name has to appear as a whole word; and a destructive verb has to be on
screen, unless the class already proves intent. Content events are coalesced
into a check after 150 ms, and periodic checks catch windows whose content
arrives later. These heuristics depend on OEM and locale.

All three gates exist because of one bug. The first version tested only for the
app name and a keyword, which closed the Settings home page: the app is called
"Control", that is a substring of "Device controls", and "Accessibility" is an
ordinary menu entry. The rules now live in a pure object with
[JVM tests](android/app/src/test/kotlin/com/example/control/enforcement/TamperRulesTest.kt)
pinning both what must be closed and what must be left alone.

**Device owner** provisioning has a guided flow in Settings, "Uninstall-proof
setup". It reads `isProvisioningAllowed`, which is the same precondition check
the system runs, so it can say whether the command will be accepted before the
user goes near a factory reset. Alongside existing owner restrictions, API 28+
adds `DISALLOW_CONFIG_DATE_TIME` to restrict date/time configuration. It is an
additional OS guard, not a trusted external clock.

**The lock.** Hard mode as a plain switch is a hole: open Control, switch it
off, delete the app. So uninstall protection carries the same password or timed
lock the blocks do, held in the same
[`LockPolicy`](packages/control_core/lib/src/lock_policy.dart). Password locks
use password unlock; active timed locks require an emergency unlock. Store
mutation checks prevent replacing live locks or weakening locked category rules;
legitimate emergency and release paths are not removed.

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

[`UsageTimeline`](android/app/src/main/kotlin/com/example/control/insights/UsageTimeline.kt)
splits those foreground intervals into hourly Day buckets or local-calendar day
buckets for the trailing 7/30-day ranges, clipped to now. Calendar boundaries
respect DST, including 23/25-hour days and repeated hours; days are not assumed
to be fixed 24-hour durations. Accounting is covered by
[`UsageMathTest`](android/app/src/test/kotlin/com/example/control/insights/UsageMathTest.kt)
and [`UsageTimelineTest`](android/app/src/test/kotlin/com/example/control/insights/UsageTimelineTest.kt).

Screen-time totals, app rankings, and chart durations use the current installed,
launchable-app filter plus Control itself, not a historical inventory of apps.
Uninstalled apps and excluded system surfaces are therefore not represented.
Queries look back 12 hours before the selected window to recover sessions already
in progress, then clip usage to the window; a missing earlier resume can still
leave a session uncounted. Android retains usage events for a limited,
device-dependent period, so a 30-day selection does not guarantee 30 days of
history. Empty intervals do not prove zero use. Control processes this locally
but does not keep its own durable usage-event history.

The selected Insights range is separate from today-only app-time rule signals
and the widget's today summary: selecting Week or Month cannot credit older
usage toward today's conditions. Insights and the widget use the local wall
calendar; enforcement signals retain the protection clock described below.

### Storage

State is one JSON file, written to a temp path and renamed into place, so a
crash mid-write leaves the previous good file rather than a truncated one. It
was `shared_preferences`; a single consistent document is easier to reason
about, and `adb`-readable when the bug being chased is "my rules vanished".

Writes go through a future that opens the file, never through a nullable field:
a block created in the first moments after launch used to be dropped, and then
the load that finished afterwards cleared the list on top of it.

### Time

A shared native persisted clock anchors time to `SystemClock.elapsedRealtime()`
and `bootCount`. Within the same boot, elapsed time rather than later wall-clock
edits advances the anchor, preventing manual forward or backward jumps from
skipping locks or allowances. Flutter synchronizes its
[`TamperResistantClock`](packages/control_core/lib/src/clock.dart) anchor on refresh
so Flutter and native enforcement use the same basis across process restarts.
Step and shortcut day boundaries use that same clock. Flutter discards stale
daily measurements before publishing across midnight, so yesterday's completed
habits cannot silently consume the next day's allowance.

After a reboot, elapsed time cannot bridge the previous boot. The fallback uses
wall time with a persisted high-water floor: it resists rollback below that
floor but **cannot prevent forward manipulation across reboot**. No trusted
external time source is available. Timezone changes can still affect civil-time
recurring schedules. Device-owner date/time configuration restrictions on API
28+ add defense, not a guarantee of tamper-proof time.

---

## Surfaces outside the app

The home-screen widget, the Quick Settings tile and the weekly notification all
wake without a Flutter isolate, so none of them can run the rule engine. Dart
writes a flattened `Summary` whenever it recomputes, and they read it from
[`SummaryStore`](android/app/src/main/kotlin/com/example/control/surface/SummaryStore.kt).
The strings are formatted in Dart rather than Kotlin: the formatting rules live
there, and a second copy is how two screens end up disagreeing about the same
number.

The tile is read-only by design. A tile that could switch blocking off would be
a bypass sitting in the notification shade, reachable from the lock screen,
which is the opposite of the point.

Habit reminders work the same way. Dart hands every reminder to
[`HabitReminders`](android/app/src/main/kotlin/com/example/control/surface/HabitReminders.kt)
with its wording already written and the last day its habit was finished. Each
alarm covers only its next due day and re-arms itself when it fires.

### Notifications, alarms and the foreground service

Everything that reaches the user outside the app ends in a notification, so
the state is checked rather than assumed:

- **Permission.** `POST_NOTIFICATIONS` is asked for when it is first needed
  (weekly report, a habit reminder, the first focus session). Settings >
  Access & permissions shows whether notifications are actually on; its fix
  shows the prompt while Android still will, and opens the app's notification
  settings once it will not. The weekly report card, the reminder editor and
  the running timer each say so when they cannot reach the user.
- **Exact timing.** Optional. With *Exact timing* allowed (Android 12+),
  reminders and the timer's end fire on the minute; without it they use a
  short window. [`NotificationAccess`](android/app/src/main/kotlin/com/example/control/surface/NotificationAccess.kt)
  is the one place alarms are set.
- **Foreground service.** While a focus session or break counts,
  [`FocusTimerService`](android/app/src/main/kotlin/com/example/control/surface/FocusTimer.kt)
  (type `specialUse`) holds the ongoing notification, whose chronometer Android
  runs itself. The end is announced by the service on the minute and by a
  backup alarm if the process is gone; whichever fires first wins. The
  service stops the moment the session ends, pauses, or is finished.
- **Surviving restarts.** Android drops every alarm on reboot. The boot
  receiver re-arms reminders and the weekly report after the unlocked boot and
  after an app update, and a second receiver does the same when the clock, the
  time zone, or the exact-alarm grant changes.
---

## Design

Flutter Material 3 with an expressive warm-neutral, evergreen, and peach palette.
`ColorScheme.fromSeed` uses `tonalSpot` with tuned surface and accent roles;
system, light, black, and pitch-black choices remain available. Blocks, Settings,
focus timer/statistics sheets, and the native Android shield share the restyled
rounded, tonal visual language. The shield remains native and works without
starting Flutter.

`ControlColors` is derived from the `ColorScheme` rather than held beside it,
so there is one source of colour and the app-specific names (`card`,
`cardRaised`, the `heavy`/`medium`/`light` severity ramp) stay readable at the
call site while resolving to real M3 roles.

Depth comes from the surface-container family rather than shadows. Selection
uses tonal container roles across navigation, chips, and segmented controls.
Typography uses Flutter's system/default fonts across the M3 scale, available
offline from first launch; there is no Nunito runtime or font-download requirement.

Navigation follows Gmail. On compact layouts every page opens under a floating
M3 `SearchBar` (menu, search, status avatar) that hides on scroll down and
returns on scroll up; the menu opens a modal drawer with Blocks, Habits and
Insights, a *Your rules* section listing each rule like a Gmail label, and
Settings on its own. The page action (New block, New habit) is an extended FAB
that collapses to its icon while scrolling. At widths >= 840 logical pixels a
`NavigationRail` carries the menu and action at its head and expands in place.
Back from any other page returns to Blocks before leaving the app. Pages retain
their scroll positions, and inactive pages pause tickers.

Each of the sixteen habit colours is a muted seed run through the `fidelity`
scheme variant, which keeps its own colourfulness, so grey stays grey and sand
stays sand in light, black, and pitch black alike.

Every bottom sheet shares one chrome: a grabber, then a header row whose
actions sit in rounded, tonal pills inset from the sheet's corners. The way
out is on the left in a quiet tone, the confirming action on the right in the
primary container; a sheet with a single action keeps it top left. The title
stays centred while it fits and gives way rather than overlap
([`sheet.dart`](lib/ui/sheet.dart)).

Every dialog shares one layout too ([`dialogs.dart`](lib/ui/dialogs.dart)):
the page behind dims and softens, the dialog grows into place, and a tonal
badge heads it, green for a neutral step, amber for one that is hard to take
back, red for a delete or a spent emergency unlock. The title and message are
centred, a tinted note says what is at stake or what went wrong, and the two
buttons fill the width side by side, stacking with the confirming one on top
once large text would squeeze them. Password and PIN fields have a show/hide
toggle, and the emergency-unlock dialog shows the unlocks as dots: those kept,
the one about to go, those already spent. The date and time pickers use the
same shape and pill buttons.

[`ExpressiveProgress`](lib/ui/expressive_progress.dart) is a custom wavy linear
indicator with a 4dp stroke, rounded caps/track, a visible track gap, and a stop
dot that hides before colliding with the active stroke. The wave travels along
anything partly done, as Material 3 Expressive does, and value changes ease to
the new length. Settings > Motion > Progress wave picks Off (still, no easing),
Calm (one wavelength per 1.4 s, the default) or Lively (per 0.7 s), with a live
preview; the choice reaches every bar, sheets included, through
`WaveMotionScope`. Empty and finished bars stop on their own, pages in the
background pause, and the system's remove-animations setting always wins. Each
bar sits behind its own repaint boundary, so a moving wave repaints only
itself. RTL mirrors the drawing, and semantics expose the label plus a clamped
percentage or loading state.

Design references: [official Material Components progress indicator guidance](https://github.com/material-components/material-components-android/blob/master/docs/components/ProgressIndicator.md),
[Flutter Material library](https://api.flutter.dev/flutter/material/material-library.html),
and [Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3).
The Compose link is design guidance, not a migration: the app remains Flutter,
with native Android enforcement surfaces, not a Compose app.

---

## Supported versions

Android 7.0 (API 24) and up. Every enforcement path works there: usage events
are API 21, the step counter 19, device admin 21, and every newer call is behind
a runtime version check. Adaptive icons and Health Connect need API 26, so the
launcher icon falls back to a layer-list on Android 7 and Health Connect will
gate itself at runtime when it lands, rather than costing those users the app.

Worth knowing: device admin still blocks uninstall properly on Android 7. The
"Deactivate & uninstall" shortcut that made admin toothless arrived later, so
protection is stronger there than on a current release.

iOS, macOS, Linux, Windows and web scaffolds exist in the tree but have no
enforcement layer yet. The app will build and the UI will run; nothing will be
blocked.

---

## Development

Run every test suite:

```bash
flutter test
```

```bash
cd packages/control_core && dart test
```

```bash
cd android && ./gradlew :app:testDebugUnitTest
```

On Windows use `gradlew.bat` in place of `./gradlew`.

Redesign coverage includes `test/insights_page_test.dart` (charts, details,
refresh/states, accessibility, and app preselection),
`test/insights_store_test.dart` (range queries, stale-response rejection, and
today-only signal separation), `test/expressive_progress_test.dart` (finite
motion, reduced motion, RTL, and semantics), `test/controls_accessibility_test.dart`,
and `test/focus_sheet_ui_test.dart`. `test/redesign_preview_test.dart` checks
compact/large-text and wide navigation layouts plus light/dark Insights and
Blocks previews against `test/goldens/*.png`, using local cached Flutter fonts.

Golden updates are opt-in, only after visual review of intentional changes:

```bash
flutter test --update-goldens test/redesign_preview_test.dart
```

Review the resulting images before accepting them; normal `flutter test` compares
against the existing baselines. These automated checks do not replace the
physical-device checks below.

The engine is pure and has no platform dependencies, so its tests run anywhere
and cover the parts that matter: midnight-wrapping schedules, polarity, grant
expiry, coarse-fix handling, clock rollback.

Lint with the project's `analysis_options.yaml`:

```bash
flutter analyze
```

Format:

```bash
dart format lib packages test
```

### Manual device checks

No physical-device testing has been performed yet. On a test device, verify:

- With an active browser or game category and Flutter closed (not force-stopping
  the whole app/service), install a second browser/game and launch it. Confirm
  dynamic detection and shielding without reopening Control; check metadata for
  any game that is not detected.
- Exclude an app from one category rule, then explicitly block it or match it
  with another rule. Confirm the exclusion does not override either block.
- Exercise `allowDuring`, weekday selection and overnight windows with Flutter
  closed. Leave a target already foreground across start/end and allowance
  expiry boundaries; expect re-evaluation on roughly the next one-second check.
- Earn an allowance, let it expire, then restart Flutter and the service.
  Confirm the spent grant remains and unchanged cumulative daily signals cannot
  mint another allowance until the next day.
- Try same-boot forward/backward clock edits, process restart, timezone changes,
  and a reboot with an edited clock. Verify the same-boot anchor and document the
  reboot-forward/timezone limits; test the API 28+ owner date/time restriction.
- Under both password and timed locks, try replacing a live lock, adding an
  exclusion or removing a category; confirm rejection and permitted tightening.
  Verify password, emergency-unlock and release behavior under their policies.
- Check launcher, Settings/search, store and OEM uninstall paths, force stop,
  clear data, admin deactivation and accessibility-disable flows across locales.
  Record bypasses rather than assuming hard mode catches every screen; compare
  optional device-owner protection only on a deliberately provisioned test device.
- Enable `all_apps` deliberately and verify essential system access, the current
  dialer, incoming/in-call UI and emergency dialer access remain safe. Do not
  place a real emergency call as a test.
- Check supported website address bars, including incognito where exposed, and
  confirm embedded app browsers are outside website-blocking support.

### Where things live when you change them

| Want to change | Touch |
| --- | --- |
| What gets blocked and when | `packages/control_core/lib/src/engine.dart`, native rules in `android/.../enforcement/`, and both test suites |
| Lock rules, emergency unlock budget | `packages/control_core/lib/src/lock_policy.dart` |
| A new measurement (sensor, signal) | `lib/platform/` for the channel, `android/.../insights/` for the reader |
| Which Settings screens hard mode closes | `android/.../enforcement/TamperRules.kt` and `TamperRulesTest.kt` |
| Which browsers website blocking reads | `android/.../enforcement/WebRules.kt` and `WebRulesTest.kt` |
| Screen-time accounting | `android/.../insights/UsageMath.kt` and `UsageMathTest.kt` |
| Persisted state shape | `lib/data/block_codec.dart`, `lib/data/local_store.dart`, `test/persistence_test.dart` |
| Theme, colours, type | `lib/ui/theme.dart` |
| Navigation shell, drawer, search | `lib/main.dart`, `lib/ui/navigation.dart` |
| Habit streaks, ranks, persistence | `lib/data/habits.dart`, `test/habits_test.dart` |
| Todo sections, overdue and steps | `lib/data/todos.dart`, `test/todos_notes_test.dart` |
| Note editor (flutter_quill) | `lib/ui/note_editor.dart` |
| Money totals, budgets, loans, currencies | `lib/data/money.dart`, `test/money_test.dart` |
| Which pages the PIN can lock | `lockableDestinations` in `lib/ui/page_lock.dart` |
| Habit reminders | `android/.../surface/HabitReminders.kt` and `HabitRemindersTest.kt` |

Keep Dart and native persisted-rule semantics aligned. Schedule, category,
exclusion, allowance-expiry and clock changes need coverage on both sides;
native enforcement must not depend on a live Flutter isolate.

---

## Roadmap

Not built yet, in rough priority order:

1. **Headless condition refresh.** Refresh sensor-dependent Dart decisions
   without opening Flutter. Recurring schedules and allowance expiry already
   evaluate natively while the accessibility service runs.
2. **Health Connect.** Workout and mindfulness conditions, and steps aggregated
   across fitness apps rather than read from one sensor.
3. **Foreground service for the focus timer.** Sessions survive the process
   dying because their start time is on disk, but a live notification with the
   running clock is what people expect.
4. **Trusted time across reboot.** The shared monotonic anchor handles same-boot
   edits; forward manipulation across reboot still needs a trusted time source.
5. **Place and Device modes.** Engine supports both; needs geofencing and
   Bluetooth/Wi-Fi signals. Deliberately hidden in the editor until then.
6. **Windows.**

---

## Known decision to make

`applicationId` is still `com.example.control`. It has to change before any
build reaches a real device, and it is awkward to change later: the accessibility
service is identified by component name, so a rename looks like a new service to
Android and the user has to grant it again. Device owner is bound to the
component too, so a rename after provisioning means a factory reset to
re-provision.

---

## Contributing

Issues and pull requests are welcome.

- Keep the engine pure. `packages/control_core` must not import Flutter or
  `dart:io`.
- Every change to `TamperRules`, `WebRules` or `UsageMath` needs a test case
  in the matching JVM test, for both what must fire and what must not.
- Prefer failing closed. If a new signal is ambiguous, block.
- Run all three test suites before opening a PR.

---

## License

MIT. See [LICENSE](LICENSE).

Copyright (c) 2026 Rishikesh Prince Prajapati.
