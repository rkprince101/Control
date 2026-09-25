# Privacy Policy for Control

_Last updated: 25 September 2026_

Control is an app for blocking distracting apps and websites, building habits,
and keeping todos, notes and a money log. It is made by Rishikesh Prince
Prajapati ("I", "me"). This policy explains what the app reads, what it keeps,
and where that goes.

**The short version:** Control has no accounts, no ads, no analytics and no
servers. Everything it knows about you stays on your phone. The only time it
talks to the internet is to load map tiles when you choose a place on a map.

## What Control reads, and why

| What | Why | Where it goes |
| --- | --- | --- |
| **Which app is on screen** (Accessibility service) | To show a block screen in front of the apps you chose to block. | Nowhere. Used on the phone, at that moment, and not stored. |
| **The address bar of supported browsers** (Accessibility service) | To block the websites you chose to block. | Nowhere. Not stored. |
| **The text of Android Settings screens** (Accessibility service, only while Hard mode is on) | To notice an attempt to uninstall or disable Control, and leave that screen. | Nowhere. Not stored. |
| **App usage time and phone pickups** (Usage access) | For Insights, and for rules that allow an app a set amount of time. | Stays on the phone. |
| **Your list of installed apps** | So you can pick which apps a rule blocks. | Stays on the phone. |
| **Step count** (Physical activity permission) | For rules that unlock after a number of steps. | Stays on the phone. |
| **Your location, once, when you tap Check in** (Location permission, foreground only) | For rules that unlock when you are at a place you chose. | Stays on the phone. Control never reads location in the background and keeps no history of it. |

Control never reads what you type in other apps, the contents of your
messages, or anything else on screen beyond what is listed above.

## What Control stores

Your rules, locks, habits, todos, notes, money entries, budgets, loans, focus
sessions and settings are saved in the app's private storage on your phone.
If you set a page-lock PIN, only a salted SHA-256 hash of it is stored, never
the PIN itself; block passwords are stored the same way, as salted, iterated
hashes.

This data is not sent to me or to anyone else. It is not backed up by Control
to any server. Uninstalling the app, or clearing its data in Android Settings,
deletes all of it.

## The internet

Control asks for internet access for one thing: when you pick a place for a
location rule, the map is drawn from tiles downloaded from
[OpenStreetMap](https://www.openstreetmap.org). Your phone requests the tiles
for the area you are looking at, so OpenStreetMap's servers receive your IP
address and that area, as with any website. Their use of it is covered by the
[OpenStreetMap Foundation privacy policy](https://osmfoundation.org/wiki/Privacy_Policy).
Nothing else in the app uses the internet.

## Device admin and device owner

If you turn it on, Control can hold device admin so Android asks for an extra
step before it can be uninstalled. If you set it up yourself over `adb`, it can
be device owner, which lets it block its own uninstall and a few system
settings while your blocks are locked. It declares no device admin policies:
it cannot wipe, lock or read your device. Both can be turned off from inside
the app.

## Notifications

Control shows notifications for the focus timer, habit reminders and the
weekly report. They are created on the phone; no push service is involved.

## Sharing and selling

Control does not share, sell or transfer any data to third parties, and does
not use it for advertising.

## Children

Control is not directed at children under 13 and does not knowingly process
their data.

## Changes

If this policy changes, the new version is published with the app and here,
with a new date at the top.

## Contact

Questions are welcome as an issue at
[github.com/rkprince101/Control](https://github.com/rkprince101/Control/issues).

The app shows this same policy under **Privacy policy** in its navigation
drawer and in Settings > About.
