# Physical — Getting it onto an iPhone

**Short answer to "how do I download it?":** to test on *your own* iPhone you do
**not** need the App Store and you do **not** need to pay anything. You build it
from your Mac straight onto your phone with a free Apple ID. The paid stuff
($99/yr) only matters when you want it to stay installed without weekly rebuilds,
or when you want *other people* to install it.

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
