# Memory.md — Walking Beat project notes

> Living file. Primary context: this repo is a research prototype for freezing-of-gait (FoG)
> cueing on Apple Watch + iPhone. Update this file whenever something important changes
> (build cmds, decisions, metrics, device info).

## What the app does (validated idea, one paragraph)

A person with Parkinson's walks; mid-walk a freeze hits (feels "stuck", feet glued, 1-10 s,
legs tremble at 3-8 Hz). The Apple Watch — running detection during an explicit walk mode —
notices the sudden cadence collapse + freeze-band trembling inside 1-3 s and fires a rhythmic
beat: discreet wrist taps first, audible cue (metronome/soft drum/spoken count) after ~4 s if
the freeze continues. Stepping in time with the beat (RAS — Rhythmic Auditory Stimulation)
helps them restart. A giant "Help me walk" button fires the same beat instantly with zero false
positives. Cue stops automatically when walking resumes / after 30 s / on tap Stop.

- **Idea validation: yes, the app implements this — reaction, not prediction.** Closed-loop
  cueing on a freeze *event*, not a risk %, matches Bächlin 2010 (auto-metronome halved freeze
  time) and RESCUE 2007 (cueing improves gait; benefit fades without a *permanent* cueing
  device — that's the product gap we target).
- **Honest caveat (docs/RESEARCH.md §4):** near-zero false alarms + useful sensitivity is NOT
  achieved yet on public data; none exists for the wrist. Detection is gated hard (5 gates) and
  the manual button is the product floor until personal wrist data exists (phase 2 study).

## Repo & environment

- GitHub: `github.com/dhruvbhavsar0612/walking-beat` (branch `main`; agent branch
  `cursor/fog-cue-app-385c` retained for history). Local: `~/Desktop/development/Github/walking-beat`
- Cursor cloud agent session `bc-01a0de94-bb2d-75ff-a391-0424ab9c385c` ("Freeze of gait rhythm")
  built all of this; final run errored mid-push; workspace copy was synced into main
  via merge commit `112c55b` (history preserved).
- Mac toolchain: Xcode 27.0, xcodegen 2.46.0, XcodeGen spec = `project.yml`.
- iPhone: device UDID `00008150-001225190AF3401C` (iPhone 17, iOS 26.6.2, Developer Mode ON).
  Trust prompt required after first install (Settings → General → VPN & Device Management).
- Signing: personal team `7WK6W7T5HK` ("Dhruv Bhavsar (Personal Team)", free tier, Apple ID
  dbhavsar9898@gmail.com). Free apps expire after 7 days → rebuild+reinstall when that happens.

## Build / test commands

```bash
cd ~/Desktop/development/Github/walking-beat
xcodegen generate                       # regenerate FoGCue.xcodeproj after target changes
xcodebuild -project FoGCue.xcodeproj -scheme FoGCue \
  -destination 'id=00008150-001225190AF3401C' -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-001225190AF3401C \
  ~/Library/Developer/Xcode/DerivedData/FoGCue-*/Build/Products/Debug-iphoneos/FoGCue.app
xcrun devicectl device process launch --device 00008150-001225190AF3401C com.example.fogcue
# Swift core tests (incl. Python-parity on real patient data): 15 pass, 0 failures
cd Packages/FoGCore && swift test
```

Bundle IDs: phone `com.example.fogcue`, watch `com.example.fogcue.watchkitapp`.
Watch app ships embedded in the phone app; installs from Watch app → Available Apps (needs a
paired Apple Watch; requires Motion + Health permissions on-watch).

## Architecture (how it actually works)

Detection chain (watch): `HKWorkoutSession` (walk mode) → accelerometer 64 Hz → 3 s windows /
0.5 s hop → features (freeze-band 3-8 Hz vs locomotion-band 0.5-3 Hz power → Freeze Index,
oriented axis-independent) → logistic model (trained on Daphnet in Python, exported to Swift)
→ 5 gates (G1 was-walking ≤5 s ago, G2 freeze signature + stillness floor, G3 persistence
3-4 s, G4 personal threshold from 2-min setup walk, G5 optional phone-in-pocket dual sensor —
not built) → cue fires via CueEngine. Feedback: Yes/No label after each auto cue → event log →
CSV export. Study-recording mode logs features for the future wrist dataset.

- `Packages/FoGCore` — DSP, features, detector, model, calibration (platform-independent Swift).
- `Packages/FoGKit` — settings, events, cue scheduler (escalation policy is unit-tested logic).
- `WatchApp/Sources` — workout manager, sampling, detection pipeline, cue engine (haptics+audio,
  synthesized click, no audio assets), Help button, FreezeCoordinator state machine, UI.
- `PhoneApp/Sources` — onboarding (limitations screen), Today summary, event log with Real/Not-
  needed labels, settings w/ preview metronome, CSV export, local caregiver alerts.
- `research/` — Python reference: Daphnet loader, nested leave-one-subject-out eval,
  `research/results/*.json` (honest numbers), fixture export → Swift parity tests.
- Fixture chunks: parity fixtures split into `Fixtures/*.partNN` (joined by the test) — full
  `samples.csv`/`expected.json` are gitignored, upload friendly.

## Measured detection reality (nested LOSO, Daphnet, new patients)

Best configs: trunk/belt-clip 16% cued @ 0.45 FP/h (conservative) or ~25-30% cued
(responsive, after personal calibration). Thigh (phone-pocket proxy) ~8-22% cued @ ~2-2.5 FP/h.
**No config yet meets both product targets (≥50% freezes ≥5 s cued AND ≤0.5 FP/h).**
Wrist: never validated (no public wrist dataset — that's T1's whole point). Personal
adaptation + real wrist data is the main lever, not better generic ML.

## Validation posture

- Business validation plan: docs/VALIDATION.md (H1-H4 hypotheses, pre-registered pass/fail).
- Tech targets: docs/VALIDATION.md T2 (≤0.5 FP/h daily activity, ≥50% of ≥5 s freezes cued,
  ≤3 s median cue latency, Help-to-first-tap ≤0.5 s).
- Regulatory: this is SaMD territory (510(k)/De Novo in US; MDR IIa in EU). No disease claims
  in marketing; demo runs as research. Regulatory counsel before public launch.
- Medical disclaimer is in README + app onboarding. Research prototype, not a medical device.

## Where the IP lives (working notes, not legal advice)

1. **Proprietary wrist dataset** (phase 2 study, study-recording mode) — likely the strongest,
   most defensible asset; nobody else has labeled wrist FoG + daily-activity negative data.
2. **Personal adaptation loop** — setup-walk thresholds + Yes/No labels → per-user model
   retuning; the *feedback loop as a system* (labels → calibration → gates) is the novel combo.
3. **Specific pipeline design** — taps-first escalating cue policy, just-walking hard gate,
   event-level FP/hour metric framing. Possible provisional patent / prior-art search needed;
   underlying detection methods (Moore FI, Bächlin) are published → FTO search before filings.
4. **Brand:** "Walking Beat" (trademark candidate), code copyright automatic.
5. Patentability bar to check: is 1-3 combined "non-obvious"? Get a patentability opinion only
   if phase 2/3 data shows the moat is real. Trade-secret the calibration internals meanwhile.

## v16 — settings verified + made functional (2026-09-27)

- **Sensitivity profiles are functional but subtle** (bundled detector_profiles.json): all three
  share prob_threshold 0.9; differences are confirm_sec (4/3/3 s) and the require_prior_walking
  gate (on/on/**off** for responsive). Switching clears personalConfig (by design) and takes
  effect at next walk-mode start.
- **Sound options were static on the phone** (always the same click; volume/audioStyle ignored
  — watch-only). Fixed: PhoneCueAudio now honors audioStyle (click / 120 Hz drum thump /
  AVSpeechSynthesizer spoken count) and volume.
- Walk-mode meter now shows the ACTIVE profile name, firing threshold, confirm seconds, and
  walking-gate state — settings differences are visible instead of invisible.
- ML teammate model: random forest via Core ML, installed as separate app "Walking Beat ML"
  (com.example.fogcue.ml, v1) — kept installed but parked; pkl archived at
  research/teammate_model/. Head-to-head LOSO eval pending (use fog_api_server.py + pkl or
  wire .mlmodel into a Swift harness).

## v4 — phone detection parity (2026-09-27, branch `v4-phone-detection`)

Phone now mirrors the watch's core abilities without any watch:

- **Automatic detection on the phone** (`PhoneApp/Sources/PhoneDetection.swift`):
  `CMMotionManager` 64 Hz → same `SlidingWindow`/`FeatureExtractor`/`FoGDetector` from FoGCore
  (zero detection-math changes) → beat (audio click + haptic at settings.bpm). Rationale: a
  pocketed phone is the closest consumer stand-in for the thigh placement the model was
  trained/validated on — our best-evidence automatic configuration.
- **Walk mode UI** (`PhoneWalkModeView`): foreground-only by iOS design (documented), confirm-to-end,
  pocket guidance text.
- **Setup walk on the phone** (`SetupWalkProgressView`): 120 s guided walk, CMPedometer cadence,
  then the identical `Calibration.calibrate` → personal detector config + recommended BPM —
  same path as watch calibration. Phone- and watch-calibration products are interchangeable.
- **PhoneBeatHost** bridges all service events into the journal/alerts path, so manual beats,
  auto cues, and calibrations land in the caregiver log exactly like watch events.
- v4 = build 4, CFBundleShortVersionString 1.3; branch `v4-phone-detection` on GitHub (merge to
  main after on-device verification).

Known phone-detection limits (see LIMITATIONS.md):
- Foreground-only (iOS): screen must stay on during walks; beat audio continues if locked.
- Placement matters: pocket, not loose hand; guidance text says so.
- No study-recording on phone yet (watch only).

## Evidence & limitations tracking (added 2026-09-26 evening)

- **docs/EVIDENCE_LOG.md** — every user-facing claim → numbered citation + strength (Strong /
  Moderate / Weak / Our data). Rule: a claim with no row does not ship. Key new finding:
  RCT evidence supports cue tempo at **110% of preferred cadence** (Arias & Cudeiro 2010;
  2019 Clin Neurophysiol) — now the app's default tempo anchor (90/100/110% chips).
- **docs/LIMITATIONS.md** — L1–L15 register; every limitation needs mitigation + in-app
  disclosure. Source of truth for onboarding limitations screen & investor Q&A.
- Physician question resolved: not required for basic setup (cadence-anchored, evidence-based);
  positioning is "bring your journal to the clinician" (CSV export; clinician PDF = L14 gap).
- Phone app redesign shipped: role selection (patient vs caregiver views), 7-step onboarding
  wizard (story → limits → role → watch check → setup walk → tempo → done), tempo anchored to
  measured cadence ×110%, role switch in Settings. Built & installed on the iPhone.

## Known gaps / next steps (as of 2026-09-26)

- [ ] Never compiled/run on device until today — do phase-1 device verification
      (background haptics+audio with wrist down, AirPods routing, battery ≤10%/h, cue ≤1 s).
- [ ] README says "22 tests" but suite runs 15 — reconcile or fix README.
- [ ] Event log is in-memory on the phone (SwiftData from the plan not implemented) — data lost
      on app restart. Worth fixing before any user study.
- [ ] Music-file cue mode (user's original "play a song" idea) not implemented — only
      synthesized metronome/drum/spoken count.
- [ ] Phone-in-pocket fusion (Gate 5) not implemented.
- [ ] Parity fixture work came from the errored agent run — walk-mode smoke test on watch
      should confirm no missing parts at runtime (parts 00-35 verified complete).
