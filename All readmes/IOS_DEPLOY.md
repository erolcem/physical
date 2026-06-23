# Physical — Getting it onto an iPhone

> **Erol's situation: no Mac, developing on Linux.** iOS apps can only be *built
> and code-signed on macOS*, so the routes below that say "from your Mac" don't
> apply directly. Use **Route 0 (Codemagic cloud build → TestFlight)** instead.
> The rest of this doc is kept for reference / for when a Mac is available.

## Route 0 — No Mac: build in the cloud (Codemagic) → TestFlight  ← *current plan*

You can get Physical onto your iPhone without owning a Mac by letting a cloud
macOS machine build and sign it. The repo already has a ready `codemagic.yaml`.

**What it costs:** the **$99/yr Apple Developer Program** (required for TestFlight)
+ Codemagic's **free tier** (cloud macOS minutes). No Mac purchase.

**One-time setup:**
1. **Enrol** in the Apple Developer Program — developer.apple.com ($99/yr).
   Identity verification can take ~24–48h, so start this first.
2. **App Store Connect** → create a new app with bundle id
   `com.cemiloglu.physical`. Copy its numeric **Apple ID** into
   `APP_STORE_APPLE_ID` in `codemagic.yaml`.
3. **Codemagic** (codemagic.io, sign in with GitHub) → add the `physical` repo →
   Teams → Integrations → add an **App Store Connect API key**, name it
   `codemagic_asc` (matches `integrations.app_store_connect` in the yaml).
4. **Start build.** Codemagic creates the signing cert/profile, builds the IPA,
   and uploads to TestFlight.
5. On your iPhone: install Apple's **TestFlight** app, accept the invite, run it.

**Why TestFlight, not the App Store, for now:** TestFlight is Apple's beta
channel — your own device + invited testers, minimal review. The public App Store
needs full review + screenshots + privacy metadata; that's for release, not for
"checking the app."

**HealthKit later (Phase 3):** reading the Apple Health app on iOS is the iPhone
analogue of "Google Health" — it uses **HealthKit**, which needs the paid program
(already covered), a HealthKit **entitlement**, and an
`NSHealthShareUsageDescription` string in `ios/Runner/Info.plist`. Not needed to
ship the current build; flagged so it's not a surprise.

---

## Reference: routes that assume a Mac

**Short answer (with a Mac):** to test on *your own* iPhone you do **not** need the
App Store and you do **not** need to pay anything — you build it from your Mac
straight onto your phone with a free Apple ID. The paid stuff ($99/yr) only
matters when you want it to stay installed without weekly rebuilds, or when you
want *other people* to install it.

## The three routes

| Route | Cost | Who can install | Build lifetime | Use when |
|---|---|---|---|---|
| **Xcode free provisioning** | Free | Only your own devices | **7 days**, then rebuild | Testing on your iPhone now |
| **TestFlight** | $99/yr (Apple Developer Program) | You + invited testers | 90 days | Sharing a beta; keeping it installed |
| **App Store** | $99/yr + app review | Anyone (public) | Until you remove it | Public release |

Note: even a **free** app on the App Store still requires the $99/yr membership +
review. There is no "free App Store upload." So for now, free provisioning is the
right call; move to the $99 program when you outgrow the 7-day cycle or want
testers.

---

## A. Free provisioning — run it on your iPhone today (recommended now)

Requirements: a **Mac with Xcode** installed, a USB cable, and a (free) Apple ID.

1. Connect the iPhone to the Mac. On the phone, tap **Trust** if prompted.
2. Set a unique bundle id and signing team:
   ```bash
   cd physical          # your Flutter project root
   open ios/Runner.xcworkspace   # opens Xcode (use .xcworkspace, NOT .xcodeproj)
   ```
   In Xcode: select **Runner** (left sidebar) → **Signing & Capabilities** tab →
   - tick **Automatically manage signing**
   - **Team** → "Add an Account…", sign in with your Apple ID → pick your
     *Personal Team*
   - **Bundle Identifier** → make it globally unique, e.g. `com.cemiloglu.physical`
     (reverse-domain style; can't clash with an existing App Store id)
3. Back in the terminal, with the phone still connected:
   ```bash
   flutter devices       # confirm your iPhone is listed
   flutter run --release -d <your-iphone>   # builds + installs + launches
   ```
   (`--release` runs without the Mac tethered after launch; `flutter run` alone is
   the debug build.)
4. First launch will fail to open with "Untrusted Developer". On the phone:
   **Settings → General → VPN & Device Management → [your Apple ID] → Trust**.
   Re-open the app.

**The 7-day catch:** free-provisioned apps stop launching after 7 days. To renew,
just re-run step 3 (rebuild/reinstall). Your logged data persists across reinstalls
*only if* the bundle id stays the same — keep it constant.

---

## B. TestFlight — keep it installed / share with testers ($99/yr)

1. Enroll in the **Apple Developer Program** ($99/yr) at developer.apple.com.
2. Build an upload-ready archive:
   ```bash
   flutter build ipa
   ```
   That produces `build/ios/ipa/*.ipa`. Upload it via Xcode's **Organizer** (Window
   → Organizer → Distribute App) or **Transporter** (free Mac app).
3. In **App Store Connect** → your app → **TestFlight**: add yourself/others as
   testers. Testers install Apple's **TestFlight** app and tap your invite.
4. Builds expire after **90 days**; internal testers (people on your App Store
   Connect team) need no review, external testers need a quick beta review.

This is the cleanest way to have it live on your phone long-term and let Erol's
friends try it without cables.

---

## C. App Store — public ($99/yr + review)

Same `flutter build ipa` upload, then fill in App Store Connect metadata
(screenshots, description, privacy details) and submit for **review**. Approval is
typically a few days. Works for free apps too — the cost is the membership, not the
listing.

---

## Gotchas & what's next

- **You need a Mac.** iOS builds/signing can't be done from Linux/Windows. (You're
  already building Flutter for iOS, so this is covered.)
- **Bundle id is forever-ish.** Pick it once (`com.cemiloglu.physical`) and keep it;
  changing it later orphans the on-device data and any App Store record.
- **No special permissions yet.** Phase 1 (local logging, shared_preferences,
  charts) needs nothing in `Info.plist`. It builds clean.
- **HealthKit later (Phase 3):** reading Apple Health *does* require the paid
  Developer Program, a HealthKit entitlement, and an `NSHealthShareUsageDescription`
  string in `Info.plist`. Not needed now — flagging so it's not a surprise.

For just getting Phase 1 in your hand to test: **Route A, today, free.**
