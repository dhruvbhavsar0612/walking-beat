# Walking Beat — Installation & Demo Guide

Freezing-of-gait cueing app for iPhone + Apple Watch (research prototype, not a medical device).

## What's in this package

| Item | Purpose |
|---|---|
| `WalkingBeat.ipa` | Pre-built iOS app (v2.6, build 17). **Runs only on the developer's registered iPhone** — see "Option A" |
| `source.zip` | Full source code (Swift packages, watch + phone apps, Python research pipeline) |
| `INSTALL.md` | This guide |

## Requirements

- **iPhone** running iOS 17 or later (built and tested on iPhone 17, iOS 26)
- Apple Watch running watchOS 10+ (optional — the phone app works standalone, including automatic detection with the phone in a pocket)
- For Option B: a Mac with **Xcode 15+** and a free Apple ID (no paid developer account needed)

---

## Option A — install the pre-built .ipa (developer device only)

Free-provisioning builds are cryptographically locked to the devices registered in the
provisioning profile (currently the team owner's iPhone). On any other phone the install will
be rejected by iOS. If you have the registered device:

```bash
# From the Mac the device is paired with:
xcrun devicectl device install app --device <DEVICE_UDID> WalkingBeat.ipa
```

Then on the iPhone: **Settings → General → VPN & Device Management → Apple Development:
dbhavsar9898@gmail.com → Trust** (required after first install; the app also **expires after
7 days** — a free-account limit, not a bug).

> **For hackathon judges without the registered device: use Option B.** It takes ~10 minutes.

---

## Option B — build from source (recommended, works on any iPhone)

1. **Unzip** `source.zip` and open a Terminal in the folder.
2. **Install XcodeGen** (one-time): `brew install xcodegen`
3. **Generate the Xcode project:**
   ```bash
   xcodegen generate          # creates FoGCue.xcodeproj
   open FoGCue.xcodeproj
   ```
4. **Set your signing team** (free Apple ID works):
   - Xcode → Settings → Accounts → add your Apple ID
   - Select the project → target **FoGCue** → Signing & Capabilities → Team: *Your Personal Team*
   - Repeat for targets **FoGCueWatch** (and **FoGML** if you want the ML comparison app)
5. **Connect your iPhone** (enable Developer Mode: Settings → Privacy & Security → Developer Mode),
   select it as the run destination, and press **Cmd+R** (or `Product → Run`).
6. First launch: on the iPhone, **Settings → General → VPN & Device Management** → trust your
   own developer profile. (Free-account apps expire after 7 days — rebuild to refresh.)
7. When prompted, allow **Motion & Fitness** permission.

### Apple Watch setup (optional)

- The watch app ships inside the iPhone app. Open the **Watch app** on the phone →
  **Available Apps → Walking Beat → Install** (requires a paired watch).
- On the watch: grant **Motion** and **Health** permissions, then tap **Set up my beat** and
  walk for 2 minutes — this personalizes thresholds and sets the beat tempo (110% of the
  measured cadence, per RCT evidence).

---

## Quick demo (60 seconds)

**On the phone alone (no watch needed):**

1. Choose your role on first launch ("person walking" = patient mode).
2. **Instant cue path:** the big **"Help me walk"** button plays a rhythmic beat immediately —
   zero false positives by design.
3. **Automatic detection path:** **Walk mode → Start** (keep the phone in a pocket, screen on).
   Walk for 10 seconds, then act a freeze — stop and tremble. The live meter shows the
   detector's freeze probability; when it crosses the line, the beat fires and stops itself
   when walking resumes. (Tip: Settings → "Cue delay after threshold" → *Instant* makes the
   response near-immediate for demos.)
4. Switch to caregiver mode → **Log** → every event is recorded, labelable, and exportable as
   CSV for a clinician.

**With an Apple Watch:** the same detection runs from the wrist with the screen off — the
intended production experience.

**Deterministic playback demo:** Walk mode → **"Run patient-data demo"** replays a real
freezing episode from the Daphnet clinical dataset (patient S02R02, thigh sensor) through the
live detector — the beat fires at the recorded freeze, every time.

---

## Repository & technical summary

- Source: https://github.com/dhruvbhavsar0612/walking-beat
- Stack: Swift (SwiftUI, CoreMotion, HealthKit, WatchConnectivity, Accelerate vDSP, AVFoundation),
  Python (Daphnet dataset evaluation, nested leave-one-subject-out, fixture export)
- Detection: 64 Hz accelerometer → 3 s windows → freeze-band/locomotor-band power ratio →
  logistic regression → 5-gate confirmation → rhythmic cue
- Honest performance: best published-data configuration ≈ 30% of freezes cued at ≤0.5 false
  alarms/hour; the manual Help button (0% false positives) is the product floor. Detection on
  the wrist is not yet validated — the study-recording mode exists to collect that dataset.

*Research prototype. Not a medical device. It misses freezes and can fire when not needed.*
