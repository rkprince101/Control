## Install

**Easiest:** add `https://github.com/rkprince101/Control` to [Obtainium](https://github.com/ImranR98/Obtainium). It installs like an app store, tells you about updates, and usually avoids Android's *restricted settings* step.

**Or download an APK below.** Not sure which? Take `Control-<version>.apk`; `arm64-v8a` is smaller and fits almost every recent phone.

1. **Pause Google Play Protect while you install.** Play Store › your profile picture › Play Protect › ⚙ Settings › turn off *Scan apps with Play Protect*. (If it only warns you, *More details › Install anyway* also works.)
2. Open the APK and allow installing from your browser or file manager.
3. **Turn Play Protect back on** afterwards.

## First run

Turn on **App blocking** and **Usage access** in Control's Settings › Access & permissions. On Android 13 and later these switches start greyed out (*Controlled by restricted setting*) for apps installed from a download. Control shows you the steps:

1. Tap Control's greyed-out switch once and press OK.
2. Settings › Apps › Control › ⋮ › **Allow restricted settings**.
3. Go back and switch Control on.

Or, from a computer: `adb shell appops set com.rkprince.control ACCESS_RESTRICTED_SETTINGS allow`

## Check your download

`sha256sum -c SHA256SUMS.txt --ignore-missing`, and the signing certificate SHA-256 is
`42:6D:13:9C:D0:0D:44:F3:92:70:1D:22:39:FA:46:74:84:B2:43:D1:54:14:77:79:37:2C:5F:8A:04:2D:19:BD`.
