# Making a signed archive

Everything from a clean checkout to a build sitting in TestFlight.

**Run all of this outside the nono sandbox.** `xcodebuild` applies its own
Seatbelt sandbox for SwiftPM manifest evaluation and Seatbelt does not nest, so
every command here fails inside it with `sandbox_apply: Operation not permitted`.
None of it has been executed in this repository — the commands are written from
the project's actual configuration, but the first run is the first run.

---

## 0. Before you start

| Thing | State | Where |
|---|---|---|
| App Group `group.dev.andcake.sudoku` | ✅ registered | developer portal |
| App ID `dev.andcake.sudoku` | ✅ App Groups enabled, 1 assigned | developer portal |
| App ID `dev.andcake.sudoku.widgets` | ✅ App Groups enabled, 1 assigned | developer portal |
| Apple **Distribution** certificate | ✅ `Apple Distribution: Ivan Pedrazas (TQ86N6HVWY)` | §1 |
| App record in App Store Connect | ✅ app `6800377712` | §2 |
| Screenshots at the sizes the page accepts | ❌ **iPhone wrong size, iPad partial** | see the end |
| Privacy policy page | ✅ live | <https://sudoku.andcake.dev/privacy> |

Provisioning and the app record are done, so §4 onward will run. The two
outstanding rows both block *submission* rather than the archive itself — you
can build and upload to TestFlight today and sort them out before review.

---

## 1. The distribution certificate — done

An **Apple Development** certificate signs builds for devices you own; it cannot
sign an App Store submission. That needs an **Apple Distribution** certificate,
made in Xcode → Settings → Accounts → **Manage Certificates → + → Apple
Distribution**.

Confirm it whenever a build starts complaining about signing:

```bash
security find-identity -v -p codesigning | grep Distribution
#   1) 2234B5AF… "Apple Distribution: Ivan Pedrazas (TQ86N6HVWY)"
```

The team in parentheses must match `DEVELOPMENT_TEAM` in `project.yml`. It does.

Every command below passes `-allowProvisioningUpdates`, which lets Xcode create
and download the App Store provisioning profiles for both the app and the widget
extension rather than either being made by hand.

> **Headless alternative.** If you would rather not sign Xcode in — for CI, say
> — create an App Store Connect API key (Users and Access → Integrations → keys,
> role: App Manager), then add these to every `xcodebuild` call instead:
> `-authenticationKeyPath /abs/path/AuthKey_XXXX.p8 -authenticationKeyID XXXX
> -authenticationKeyIssuerID <uuid>`. The path has to be absolute.

---

## 2. The App Store Connect record — done

The bundle ID being registered in the developer portal is not the same thing as
the app existing in App Store Connect. Without the record an upload fails with an
error about the bundle ID not being found, which reads like a provisioning
problem and is not one.

The record exists: **app `6800377712`**, at
<https://appstoreconnect.apple.com/apps/6800377712/distribution/ios/version/inflight>.

The listing itself — subtitle, description, keywords, privacy answers, review
notes — is written out in [`store-listing.md`](store-listing.md) ready to paste.

---

## 3. Version and build number

```yaml
# SudokuApp/project.yml
MARKETING_VERSION: "1.0"        # the version people see
CURRENT_PROJECT_VERSION: "1"    # the build number
```

`MARKETING_VERSION` stays `1.0` until there is something worth calling 1.1.
**`CURRENT_PROJECT_VERSION` must increase for every upload**, including a second
attempt after a rejected one — App Store Connect refuses a build number it has
already seen, and the refusal arrives by email several minutes after the upload
appears to have succeeded.

Edit `project.yml`, never the `.xcodeproj`. Then regenerate:

```bash
task xcodegen
```

---

## 4. Archive

```bash
cd sudoku-ios
task xcodegen                     # the .xcodeproj is generated and gitignored

xcodebuild archive \
  -project SudokuApp/SudokuApp.xcodeproj \
  -scheme SudokuApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/SudokuApp.xcarchive \
  -allowProvisioningUpdates
```

Three details that matter:

- **No `CODE_SIGNING_ALLOWED=NO`.** That flag is all over `Taskfile.yml` for
  simulator builds, and it is exactly wrong here — it is what lets CI build
  without a certificate, and an unsigned archive cannot be uploaded.
- **`generic/platform=iOS`**, not a simulator destination. An archive of a
  simulator build is not a thing you can ship.
- **`-configuration Release`** is what the scheme's archive action already
  specifies (`project.yml`, `schemes.SudokuApp.archive`), stated again so a
  changed scheme cannot silently produce a Debug archive.

The widget extension is built and embedded automatically: the app target depends
on `SudokuWidgets`, so archiving the app archives both.

### Check the archive before exporting

Two things are worth confirming, because both fail silently and both are
expensive to discover from App Store Connect:

```bash
APP=build/SudokuApp.xcarchive/Products/Applications/SudokuApp.app

# 1. The App Group entitlement actually made it into the signature.
codesign -d --entitlements - "$APP" 2>/dev/null | grep -A2 application-groups
```

You want `group.dev.andcake.sudoku`. If this is empty, the profile did not carry
the entitlement, and every widget will be permanently blank on device while the
app itself works perfectly — the exact failure `SnapshotStore` degrades to.

```bash
# 2. The widget extension is embedded.
ls "$APP/PlugIns/"
```

You want `SudokuWidgets.appex`. Nothing there means the extension built but was
never embedded, and the widgets simply will not appear in the gallery.

```bash
# 3. The icon and privacy manifest are present.
ls "$APP/AppIcon"*.png "$APP/PrivacyInfo.xcprivacy" 2>/dev/null
plutil -extract CFBundleIcons raw -o - "$APP/Info.plist" 2>/dev/null | head
```

---

## 5. Export the .ipa

```bash
xcodebuild -exportArchive \
  -archivePath build/SudokuApp.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist SudokuApp/ExportOptions.plist \
  -allowProvisioningUpdates
```

[`SudokuApp/ExportOptions.plist`](../SudokuApp/ExportOptions.plist) is committed
and commented. It exports to disk rather than uploading, deliberately: an upload
that happens as a side effect is hard to inspect and impossible to repeat, and
the first one is worth looking at. Once this is routine, change `destination` to
`upload` and step 6 disappears.

Result: `build/export/SudokuApp.ipa`, plus a `DistributionSummary.plist` and the
`Packaging.log` that is the first place to look when something went wrong.

---

## 6. Upload

Pick one.

**Xcode's own uploader** — no extra credentials if Xcode is signed in:

```bash
xcrun altool --upload-app \
  -f build/export/SudokuApp.ipa \
  -t ios \
  -u ipedrazas@gmail.com \
  -p "@keychain:AC_PASSWORD"
```

`AC_PASSWORD` is an **app-specific password** (appleid.apple.com → Sign-In and
Security → App-Specific Passwords), stored once with:

```bash
xcrun altool --store-password-in-keychain-item AC_PASSWORD \
  -u ipedrazas@gmail.com -p <the-app-specific-password>
```

Your normal Apple ID password will not work and the error does not say so
clearly.

**With an API key** instead, if you made one in §1:

```bash
xcrun altool --upload-app -f build/export/SudokuApp.ipa -t ios \
  --apiKey XXXXXXXXXX --apiIssuer 00000000-0000-0000-0000-000000000000
```

**Or Transporter.app** from the Mac App Store — drag the `.ipa` in. Worth
knowing about because its error messages are consistently better than the CLI's.

---

## 7. After the upload

The build takes 5–30 minutes to finish processing before it appears in
TestFlight, and failures arrive by email rather than in the terminal.

- **Export compliance** will not be asked: `ITSAppUsesNonExemptEncryption` is
  already `false` in `Info.plist`, which is honest — the app has no networking
  code at all.
- **Privacy answers** in App Store Connect must match
  `PrivacyInfo.xcprivacy`: no data collected, no tracking. Answering the
  questionnaire differently from the manifest is a review rejection.
- **The privacy policy URL** is <https://sudoku.andcake.dev/privacy>, live and
  verified on a direct hit — which matters, because it is a client-side route in
  a single-page app and Apple will load it cold rather than by clicking through.
  It is a page in the `sudoku-and-cake` repository, not this one.

---

## Common failures

| Symptom | Cause |
|---|---|
| `No signing certificate "iOS Distribution" found` | §1 — the distribution certificate is missing or belongs to another team |
| `Provisioning profile ... doesn't include the com.apple.security.application-groups entitlement` | The App Group is registered but not *assigned* to that App ID. Enabling the capability is not enough; the group has to be ticked in the App ID's **Configure** sheet until it reads "Enabled App Groups (1)". Both App IDs here already read that. |
| `The bundle identifier cannot be found` on upload | §2 — the App Store Connect record is missing, or the bundle ID does not match it |
| `The provided entity includes an attribute with a value that has already been used` | Build number not incremented — §3 |
| Archive succeeds, widgets blank on device | The entitlement did not make it into the signature. Check it with the `codesign -d --entitlements` command in §4 *before* uploading. |
| `sandbox_apply: Operation not permitted` | You are inside nono. Every command here needs a normal shell. |

---

## Screenshots

**Read the accepted dimensions off the App Store Connect upload page**, which
prints them above each drop zone. What a simulator produces and what a slot
accepts are different facts, and this file asserted the second from the first
once already and was wrong. Today the page offers a **6.5" iPhone** slot —
1242×2688 or 1284×2778 — and a 13" iPad one at 2064×2752.

`DEVICE` selects the model, and `iPhone 14 Plus` is the 6.5"-compatible one:

```bash
DEVICE="iPhone 14 Plus" ./scripts/screenshot.sh screenshots/iphone-6.5/1-home.png \
    iphone -skipWelcome -inMemoryStore
```

Xcode 26 ships no such simulator by default; creating it is a one-liner, in
[`store-listing.md`](store-listing.md#one-time-simulator-setup), and it is
already done on this machine.

The exact commands for a whole set are in
[`store-listing.md`](store-listing.md#capturing-a-set), along with which two
shots still need a manual ⌘S.
