# Implementation plan and checklist

Every box is ticked only when the code is on `main` **and** CI (build plus unit tests) has passed. Anything that needs a real device, account or permission is marked *(device)* until the user confirms it works.

## Dependency map

```
Phase 0 docs/CI
   └─▶ 1a domain (commitments, scoring, fines, availability, calendar classification)
          └─▶ 1b persistence + seed memory + money cutover
                 └─▶ 1c Today · Coach shell · Calendar · Progress · privacy settings
                        ├─▶ 2 coaching engine (memory retrieval, intents, on-device AI, briefing, replanning, notifications)
                        │      ├─▶ 4 nutrition & household (needs tasks, memory, AI extraction)
                        │      └─▶ 6 contextual intelligence (needs scheduling + location/weather/travel)
                        ├─▶ 3 fitness (needs commitments; watch needs HealthKit write)
                        └─▶ 5 accountability (needs commitments + reconciliation; real money last)
                               └─▶ 7 polish (widgets, Live Activities, App Intents) ─▶ 8 real-world validation
```

## Phase 0 — Audit and architecture
- [x] Audit (`AUDIT.md`)
- [x] Requirements, decisions, data model, integrations, plan and test plan docs
- [x] CI on Xcode 26.3 with an iOS 26 simulator, so Foundation Models code is compiled

## Phase 1 — Core native foundation
- [x] 1a `CommitmentRules` state machine (A4, D-012/013/014)
- [x] 1a `DayScoring`: weighted score, live projection, fine bands, monthly cap (A2, A5, A6)
- [x] 1a `Availability`: work protection, focus blocks, lunch, shared events non-blocking, door-to-door padding (S1–S2, N4)
- [x] 1a `CalendarClassifier`: roles, focus detection, free events, office/home day hints (D-009)
- [x] 1a unit tests for scenarios J, K and the scoring parts of B and O
- [x] 1b SwiftData entities: Commitment, CommitmentEvent, Routine, DayRecord, CoachMessage, MemoryRecord, TaskItem
- [x] 1b Seed memory from the brief (profile, objectives, preferences, house-sale backlog, suggested routines disabled)
- [x] 1b Money cutover: no activity earnings from 19 Oct 2026, gold off, earlier earnings still settle
- [x] 1b `CoachModel`: commitments for today, routines → commitments, transitions with history, reconciliation, projection
- [x] 1c Four tabs (N1); the old dashboard moves to Progress → Activity
- [x] 1c Today: current action card, quick actions, next commitment, next opportunity, essentials, projection, coach line
- [x] 1c Coach: persistent chat, quick replies, deterministic intents (what's next, done, not now, park, I'm back, add task, blocked), dictation *(device)*
- [x] 1c Calendar: EventKit read-only day and week views, role assignment, missing-work-calendar state *(device)*
- [x] 1c Settings: privacy and permissions, calendars, coach memory inspector (edit, delete, export), delete all coach data
- [x] 1c Widgets show the next action and commitments (no money); sensitive titles hidden on the Lock Screen *(device)*

## Phase 2 — Coaching engine
On-device items still need checking on the iPhone (see `TEST_PLAN.md`).

- [x] Foundation Models provider behind `CoachLanguageModel`, with tools for add task, propose commitment, transition commitment and remember fact
- [x] Memory retrieval: relevant records summarised into a small prompt
- [x] Morning briefing on "I'm ready", one suggestion at a time
- [x] Recommendation engine (deterministic candidates → validation → wording), with reason and alternative
- [~] Dependency-aware task planning and opportunity tasks (H1–H3): ordered steps and gap-sized picks done; AI task breakdown still to do
- [x] Replanning on calendar changes without fines (S3, scenario B)
- [x] Launch mode and pause/resume voice notes (C3–C4)
- [x] Scheduled contextual notifications with three escalation levels (NO1–NO2)
- [x] Spoken replies (home mode only)

## Phase 3 — Fitness and health
On-device items still need checking on the iPhone and watch.

- [x] Exercise library, upper/lower program generator, progression rule (W1–W3)
- [x] Set logger with rest countdown, busy-equipment swaps, reorder, extend, end (W4)
- [x] Rehab block placement and symptom logging, including next day (R1–R3)
- [x] Walking baseline and gradual targets (K1–K3)
- [x] Swimming tracking and kit readiness (SW1–SW3)
- [x] watchOS app: rest timers, haptics, workout session, HealthKit save *(device)*
- [x] Rest timer Live Activity *(device)*
- [x] Progress: weight and body-fat trends, strength, consistency, photos (file-protected)

## Phase 4 — Nutrition and household
Camera, document scanner and notification behaviour still need checking on the iPhone.

- [x] Recipe import (camera, screenshot, PDF, file, typed), extraction, estimates with uncertainty, corrections (F7)
- [x] Macro tweaks that keep the dish; flavour changes need approval (F7)
- [x] Meal plan: same lunch Mon–Fri on a 4-week rotation, varied dinners for two, exclusions, slow cooker only on home days, fakeaway Fridays (F2–F4)
- [x] Batch-cook fit check: one hour, drops freezer extras rather than pretending (F5)
- [x] Freezer meals and probabilistic inventory with conversational corrections (F6, I4)
- [x] Defrost reminders the evening before, safe advice when forgotten (I5)
- [x] Aldi list by department with pack sizes and estimates; £400 ceiling as a ceiling, not a target (I1–I2)
- [x] Receipts: scan or type, review, duplicate protection (I3)
- [x] Dinner rescue when dinner isn't happening (scenario G)
- [x] Household task chains (H1)
- [ ] Generate new dishes from favourites with the on-device model (needs Apple Intelligence; later)

## Phase 5 — Accountability
- [ ] Daily reconciliation job and pending-verification flow
- [ ] Month view: fines, explanations, transfer estimate, audit trail
- [ ] Review the trial with the user, then wire "£500 − fines" into the Starling → Monzo payout (approval in Starling)

## Phase 6 — Contextual intelligence
- [ ] Home/office mode, location consent, travel times, weather, social-event preparation, post-event recovery, outing ideas

## Phase 7 — Platform polish
- [ ] Widgets (what's next, essentials), Lock Screen, Live Activities, App Intents, haptics, accessibility audit, Swift 6 mode

## Phase 8 — Real-world validation
- [ ] A week of real use; fix wrong recommendations before adding features
