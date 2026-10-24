# Al Anad HR on iPhone: build it on a Mac

The iPhone project is already prepared in `mobile_app/ios` (name "Al Anad HR", icons, permission texts, portrait only,
bundle id `com.hrportal.hrMobileApp`). Windows cannot build iPhone apps, so these steps run on the MacBook.

## What you need on the Mac (one time)
1. **Xcode** from the App Store (open it once and accept the license; let it install extra components).
2. **Flutter** (stable, 3.35 or newer): https://docs.flutter.dev/get-started/install/macos
3. **CocoaPods**: `sudo gem install cocoapods` (or `brew install cocoapods`)
4. An **Apple ID** (free is enough to run on your own iPhone; a paid Apple Developer account is needed for TestFlight / App Store).

Check everything with `flutter doctor`. Fix any red line it shows for Xcode or CocoaPods.

## Get the code onto the Mac
- Copy `Al Anad HR-for-Mac.zip` (USB stick, AirDrop, cloud drive) and unzip it, **or**
- `git clone <your repository>` once the code is on GitHub.

## Build and install on your iPhone
```bash
cd mobile_app
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```
In Xcode:
1. Click **Runner** (left side) > **Signing & Capabilities** > tick *Automatically manage signing* > choose your **Team** (your Apple ID).
2. Change the **Bundle Identifier** to something unique, for example `com.yourname.alanad` (Apple rejects a name already taken).
3. Plug the iPhone in with a cable and choose it as the run device at the top.
4. On the iPhone: **Settings > Privacy & Security > Developer Mode** > turn on and restart.
5. Press **Run** (the play button), or from Terminal: `flutter run --release -d <iPhone name>`.
6. First launch on the iPhone: **Settings > General > VPN & Device Management** > tap your Apple ID > **Trust**.

With a free Apple ID the app stops opening after 7 days; run it again from Xcode to renew it.
For a normal install that stays, use TestFlight (paid account): `flutter build ipa`, then upload with the Xcode *Organizer* or the *Transporter* app.

## What works on iPhone and what does not yet
Works: login, company sign-up, home, attendance check-in/out with GPS, leave and requests, documents, payslips, directory, rewards,
kudos, Getting started checklist, assistant, Arabic and English, dark mode, privacy policy and support links.

Not on iPhone yet:
- **Reminders and notifications while the app is closed.** They use an Android background task. iPhone needs Apple push (APNs)
  through a Firebase project, which has to be set up first.
- **Location pings while checked in with the app closed.** Android only for now.
- **In-app updates.** iPhone updates come from TestFlight or the App Store, not from a download link.
- **Wi-Fi name check.** Needs a paid account: in Xcode > Signing & Capabilities > **+ Capability** > *Access WiFi Information*
  (or copy `ios/Runner/Runner.entitlements.optional` to `Runner.entitlements` and set it in the build settings).
  Without it, iPhone checks the workplace by GPS only.

## If something fails
- `pod install` errors: run `pod repo update`, then `pod install` again.
- "Untrusted developer": do step 6 above.
- "No profiles for ...": the Bundle Identifier is taken; change it (step 2).
- The app opens but cannot log in: the iPhone needs internet; the server is `https://hr.quadrocloud.net`.

---

# Upload to TestFlight (needs a paid Apple Developer account, 99 USD a year)

TestFlight is how the app stays installed on iPhones (testers install it from the TestFlight app, no cable, no 7-day expiry).

## One time on the Apple websites
1. Join the **Apple Developer Program**: https://developer.apple.com/programs/enroll
2. In **App Store Connect** (https://appstoreconnect.apple.com) > **Apps** > **+** > **New App**:
   - Platform iOS, Name **Al Anad HR**, Primary language English, SKU `alanad`
   - Bundle ID: the same one you set in Xcode (it appears in the list after Xcode signs the project once).
3. App Store Connect > your app > **App Privacy**: answer the questionnaire. The app collects name, e-mail, phone, precise location
   (only while checking in), photos/files you upload, and a device identifier. None of it is used for tracking or advertising.
   Privacy policy URL: `https://hr.quadrocloud.net/app/privacy.html`.
4. For external testers only: Apple reviews the first build. Give them a **demo login** (Review Information > Sign-in required),
   for example an HR owner created on a test company. Internal testers (up to 100 people from your team) need no review.

## Every release (on the Mac)
```bash
cd mobile_app
../scripts/ios_testflight.sh            # builds the .ipa (build number comes from pubspec.yaml: version: 1.6.3+16)
```
Then upload `build/ios/ipa/*.ipa` with one of:
- the **Transporter** app (free, Mac App Store): drag the .ipa in and press *Deliver*, **or**
- Terminal with an App Store Connect API key (App Store Connect > Users and Access > Integrations > Keys):
  `xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>`
  (put the downloaded `AuthKey_<KEY_ID>.p8` in `~/.appstoreconnect/private_keys/`).

After 5 to 30 minutes the build shows under **TestFlight** in App Store Connect:
1. Wait until the status is not "Processing".
2. **Internal Testing** > create a group > add testers (they need an Apple ID invited under Users and Access) > select the build.
3. Testers open the **TestFlight** app on the iPhone and tap *Install*.

Every upload needs a **higher build number**: change the number after `+` in `mobile_app/pubspec.yaml` (for example `1.6.3+17`).

## Checks before the first upload
- `flutter doctor` is green for Xcode and CocoaPods.
- The Bundle Identifier is unique and the Team is your paid team (Xcode > Runner > Signing & Capabilities).
- The app launches on a real iPhone in release mode first: `flutter run --release`.
- Log in with a real account to see data (the server is live at `https://hr.quadrocloud.net`).
