# Walking Beat: freezing-of-gait cueing for Apple Watch + iPhone

When someone with Parkinson's disease freezes mid-walk, the watch taps a steady beat on the wrist
and, if needed, plays a sound. Stepping in time with a rhythm helps many people start walking
again (the RESCUE trial and the meta-analyses listed in [docs/REFERENCES.md](docs/REFERENCES.md)).
The beat starts in one of two ways:

- **On demand:** a large "Help me walk" button on the watch. It always works and has no false alarms.
- **Automatically:** the watch detects a likely freeze during walk mode.

> **Research prototype, not a medical device.** Automatic detection misses freezes and sometimes
> starts the beat when it isn't needed. See the honest numbers in
> [docs/RESEARCH.md](docs/RESEARCH.md#4-what-we-measured-ourselves).

## Documents

| File | Contents |
|---|---|
| [docs/RESEARCH.md](docs/RESEARCH.md) | Evidence review: the problem, why cueing works, detection literature, our own evaluation |
| [docs/PRODUCT_PLAN.md](docs/PRODUCT_PLAN.md) | Product definition, false-alarm strategy, roadmap with exit criteria, risks, regulatory stance |
| [docs/VALIDATION.md](docs/VALIDATION.md) | Customer validation, research-only validation, technical study protocol |
| [docs/REFERENCES.md](docs/REFERENCES.md) | All citations (verified), referenced as [n] across the docs |

## Repository layout

```
Packages/FoGCore/        Swift package, platform-independent, tested on Linux/macOS
  Sources/FoGCore/       Feature extraction, logistic model, multi-gate detector, calibration
  Sources/FoGKit/        Settings, event records, watch<->phone messages, cue scheduler, summaries
  Tests/                 22 tests incl. parity against Python on real patient data
WatchApp/Sources/        watchOS app: walk mode, detection pipeline, haptic/audio cue engine, UI
PhoneApp/Sources/        iOS app: onboarding, today summary, event log + labels, settings, export
research/                Python reference: Daphnet loader, features, model, detector, nested-LOSO eval
project.yml              XcodeGen spec for the two app targets
```

## Build and run the apps (macOS + Xcode 15 or later)

```bash
brew install xcodegen
xcodegen generate
open FoGCue.xcodeproj
```

1. Set your development team on both targets.
2. Run the `FoGCue` scheme on an iPhone that is paired with an Apple Watch (Series 6 or later,
   watchOS 10+).
3. On the watch, grant Motion and Health (workout) permissions when asked.

Test these on a real device. Simulators don't produce real accelerometer data or haptics.

## Run the tests

```bash
# Swift core (Linux or macOS, Swift 5.9+)
cd Packages/FoGCore && swift test
# The parity recordings live as Fixtures/*.partNN. The test joins them.

# Python reference pipeline
cd research
pip install -r requirements.txt
python download_datasets.py
python -m pytest -q tests
python evaluate.py --sensor thigh   # nested leave-one-subject-out; exports detector_profiles.json
python export_fixtures.py           # regenerates the Swift parity fixtures
```

## How detection works

Detection runs in the following stages:

1. **Sampling.** The accelerometer runs at 64 Hz. The detector looks at 3-second windows, one
   every 0.5 s.
2. **Features.** For each window it measures power in the stepping band (0.5-3 Hz) and the
   "trembling" band (3-8 Hz), summed across all three axes, so the result doesn't depend on how
   the watch sits on the wrist. From these it derives the freeze index [11], the dominant
   frequency, and how locomotion compares with the last 10 seconds.
3. **Scoring.** A logistic regression turns those features into a freeze probability. It was
   trained on Daphnet [13], and the same code runs in Python and Swift, verified by the parity
   tests.
4. **Gates.** A cue starts only if all of these hold:
   - the probability is at least 0.9;
   - there is enough movement to rule out quiet standing;
   - (default profile) the person was walking steadily within the last 5 s;
   - the evidence persists for 3-4 s.
5. **Cue.** Taps start first. Sound is added after 4 s, if that mode is chosen. The cue stops when
   walking resumes, when the person goes still, after 30 s, or when Stop is tapped.
6. **Setup walk.** A 2-minute guided walk raises the threshold above that person's own normal
   walking and sets the beat to their cadence.

## Status

| Area | State |
|---|---|
| Swift core and Python pipeline | Implemented; 22 Swift and 8 Python tests pass |
| watchOS and iOS apps | Implemented; need an Xcode build and on-device verification (not compiled in CI yet) |
| Detection accuracy on the wrist | **Not yet validated.** No public wrist dataset exists; the study-recording mode exists to collect one (docs/VALIDATION.md, T1) |
| Accounts, cloud sync, remote caregiver push | Out of scope for the demo |
