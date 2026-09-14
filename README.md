# Paperplanes Package Scanner

Flutter app that scans every machine code on a NY cannabis package at once —
the UPC (retail SKU) and the QR (Metrc Retail ID / COA / lot identifier) —
classifies each payload, and merges them into one normalized product record.

This is a POC developed for Melissa Fernandez 

## Architecture

```
              CAMERA (mobile_scanner, multi-format)
                 │  aggregating session — collects every code seen
                 ▼
        ScannerPage._captured  (deduped by payload)
                 │  auto-finish 2.5s after QR + UPC both captured, or Done
                 ▼
        CodeClassifier.classify()   ── per-code CodeClass:
            metrcRetailId > coaUrl > manufacturerCoa > retailSku >
            stateTraceability > marketing > dispensaryInternal > unknown
                 │
                 ▼
        CodeClassifier.normalize()  ── NormalizedScanResult:
            SKU side  : UPC → ProductRepository (local db + online fallback)
            Batch side: best QR source → Retail ID url / COA url / lot id
                 │
                 ▼
        ResultPage — product card, batch/COA card with open-link buttons,
                     ranked list of every captured code
```

## Run on an iPhone connected to your Mac

Prereqs (one-time): full Xcode from the App Store, then:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo gem install cocoapods
```

1. **Set up the project** (from this folder):

   ```bash
   bash setup.sh
   ```

   Scaffolds `ios/`/`android/`/`web/`, runs `pub get`, and ensures the
   camera permission and iOS 12 deployment target.

2. **Signing** (one-time):

   ```bash
   open ios/Runner.xcworkspace
   ```

   Runner → Signing & Capabilities → check **Automatically manage signing**
   → pick your Team (a free Apple ID works: Xcode → Settings → Accounts → +).
   If the bundle id collides, change it to your own reverse-domain.

3. **Phone** (one-time): connect with a data cable, unlock, tap **Trust This
   Computer**. Enable Settings → Privacy & Security → **Developer Mode**
   (reboots; the toggle appears after Xcode has seen the device).

4. **Run**:

   ```bash
   flutter devices          # copy your iPhone's device id
   flutter run -d <device-id>
   ```

   If iOS blocks launch with an untrusted-developer alert:
   Settings → General → VPN & Device Management → your Apple ID → **Trust**,
   then run again. Allow camera access on first scan.

Free-Apple-ID caveat: the signature expires every 7 days — plug in and
`flutter run` again to refresh (the trust step persists). We can fix this later.
