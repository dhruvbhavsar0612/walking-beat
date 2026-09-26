# Validation plan: customer, research-based, and technical

Citations like [n] point to [REFERENCES.md](REFERENCES.md).

The startup rests on four hypotheses. Each one gets a test with a pass/fail threshold written
down **before** running it, so the result can't be rationalised afterwards.

| # | Hypothesis | Riskiest assumption |
|---|---|---|
| H1 | Freezing is a frequent, top-3 daily problem for people with FoG and their caregivers | Problem severity |
| H2 | They will wear a watch and use a beat when frozen (on demand or automatic) | Behaviour change and usability for elders |
| H3 | Automatic detection on the wrist can reach a tolerable false-alarm rate after personalisation | Technical feasibility |
| H4 | Someone will pay (patient, family, clinic, insurer), and a regulatory path exists | Business model |

---

## Track A: validation with real customers

### A1. Recruit (no product needed)

- **Channels:**
  - Parkinson's support groups (in-person and online)
  - Parkinson's UK and APDA local chapters
  - Parkinson's-specific exercise classes (boxing, dance)
  - Movement-disorder clinics and neuro-physiotherapists
  - Online communities: HealthUnlocked Parkinson's forums, r/Parkinsons, Facebook caregiver groups
  - The Michael J. Fox Foundation's Fox Trial Finder for later studies
- **Target:**
  - 15 people with PD who freeze
  - 10 caregivers
  - 5 physiotherapists or neurologists
- **Screen:** "In the last month, have your feet felt glued to the floor when walking or
  turning?" This mirrors the item used in FoG questionnaires [2].

### A2. Problem interviews (tests H1)

These are 30-minute conversations about past behaviour. Don't pitch.

1. Tell me about the last time you got stuck. Where were you, what happened, how did it end?
2. How often does it happen in a normal week? Where does it happen most?
3. What do you do now to get going again? (counting, stepping over lines, music, a cane laser,
   someone's help, nothing)
4. What has that cost you? (falls, avoiding going out, embarrassment)
5. Have you tried any device or app for it? Why did you keep it or stop?
6. Do you wear a watch or smartwatch today? What would stop you wearing one?
7. Caregivers only: what worries you most when you're not with them?

**Pass:** at least 60% of patient interviewees report weekly freezing *and* already use some cueing
strategy (proof that they value cueing). At least 40% of caregivers raise freezing or falls as a
top-3 worry unprompted.

### A3. Clinician interviews (tests H1 and H4)

- How do you assess FoG today? Would an objective log between visits change your decisions?
- Would you prescribe or recommend a cueing app? What evidence would you need?
- Who pays for cueing aids in your system?

**Pass:** at least 3 of 5 would recommend it to patients if a pilot shows benefit, and name the
evidence they would need.

### A4. Concierge and on-demand test (tests H2, no detection risk)

Give 5-8 participants the watch app with **only the Help button and walk mode** for 1-2 weeks.
Automatic detection stays off.

- **Measure:** days used, number of Help presses, SUS usability score, and a 3-question weekly
  check-in ("Did the beat help you get moving? Yes / Somewhat / No").
- **Pass:** at least 60% use it in at least 3 of 7 days; median "helped" is at least "somewhat";
  SUS is at least 70.
- **Why this test:** it shows whether the on-demand floor of the product is valued, before
  investing more in detection.

### A5. Detection pilot (tests H3, supervised)

Run the Technical protocol T1 below with the same participants.

### A6. Willingness to pay (tests H4)

- **Patients and families:** a Van Westendorp price-sensitivity survey (4 questions) plus a
  landing page with a "join the waitlist" or refundable pre-order button, split-tested at two
  price points.
- **Clinics:** a letter of intent for a paid pilot.
- **Pass:** at least 10% of landing-page visitors from PD communities join the waitlist; at least
  2 clinics or physiotherapy practices sign an LOI.

---

## Track B: research-based validation (when customers aren't reachable yet)

These can be done from public sources, and each one produces an artifact for a pitch deck.

| Step | Method | Output | Status |
|---|---|---|---|
| B1. Problem size | Prevalence x population: 11.77 M with PD [4] x ~40% FoG [2] | ~4-5 M people with FoG worldwide; UK ~58k (145k with PD x 40% [18]) | Done (RESEARCH.md section 1) |
| B2. Intervention evidence | RCT and meta-analyses on cueing [6-10] | "Cueing works but benefits fade without a permanent device" [6] | Done (RESEARCH.md section 2) |
| B3. Technical feasibility | Replicate detection on public data with patient-level holdout | Our nested-LOSO numbers; wrist gap identified [14] | Done (RESEARCH.md section 4, `research/results/`) |
| B4. Competitor map | Product pages, regulatory databases, trial registries | CUE1+ (sternum vibration, UK, US approval pending) [17, 21]; Path Finder (laser shoes) [18]; NeuroRPM (Apple Watch symptom monitoring, cleared, no cueing) [19] | Started (PRODUCT_PLAN.md section 6) |
| B5. Voice of the customer without interviews | Systematically code 200 public forum posts (HealthUnlocked, r/Parkinsons) that mention freezing: triggers, coping strategies, devices tried, complaints | Frequency table of pains and workarounds; quotes for the deck | To do |
| B6. Regulatory path | FDA 510(k)/De Novo database search for FoG and cueing devices; general wellness guidance [20] | Predicate candidates; classification memo | Started (PRODUCT_PLAN.md section 7) |
| B7. Expert check | 3-5 cold emails to authors of [6, 10, 12, 14, 15] asking for a 20-minute call | Expert quotes; potential clinical partner | To do |

**How to read Track B.** It can show that the problem is large, that the intervention is
evidence-based, and that the technical risk is identified. It cannot show that people will adopt
it or pay for it. That still needs A4 and A6, even at small scale.

---

## Technical validation protocol

### T1. Supervised wrist study (dataset creation)

- **Participants:** 15-20 people with PD who report FoG; testing in both ON and OFF medication
  states where clinically appropriate.
- **Sensors:** the watch in study-recording mode on the more affected side, an iPhone in the
  trouser pocket, and video for reference labels.
- **Protocol:** a FoG-provoking course in the style of Ziegler et al. and the DeFOG protocol
  [15]: gait initiation, 360-degree turns, a doorway, a narrow passage, and dual-task walking.
  Add 10 minutes of normal daily activities (sit, eat, talk, dress) as a false-alarm challenge.
- **Labels:** two raters annotate FoG start and end from video, with inter-rater agreement
  reported.
- **Ethics:** institutional ethics approval and informed consent. The app shows its limitations
  screen.

### T2. Metrics and targets

These are always reported per participant and pooled, with patient-level holdout.

| Metric | Target to proceed to home pilot |
|---|---|
| False alarms per hour in the daily-activity block (walk mode on) | <= 0.5 |
| False alarms per hour during walking tasks | <= 1 |
| Freezes >= 5 s that received a cue | >= 50% after personalisation |
| Median time from freeze onset to cue | <= 3 s |
| Help button: time from press to first tap | <= 0.5 s |

### T3. Re-running the analysis

```bash
cd research
python evaluate.py --sensor thigh     # or ankle / trunk; wrist once T1 data exists
python export_fixtures.py             # regenerate Swift parity fixtures
cd ../Packages/FoGCore && swift test  # Swift must still match Python
```
