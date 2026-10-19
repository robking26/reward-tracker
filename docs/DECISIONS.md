# Decisions

Newest first. Each entry records what was decided, why, and who made the call ("User" means answered by the user; "Team" means a default chosen because the question wasn't blocking).

## D-014 · Unresolved commitments after the grace period (Team, trial rule)
At midnight, open commitments become **pending verification**, never missed straight away (NO2: silence isn't proof). The next morning Today asks about them. Anything still unanswered by the end of the following day is recorded as **missed (assumed)**: it's flagged, explained, and can be corrected until the month closes. Without this, ignoring the question would be the easiest way to avoid a fine. Review it after the trial month.

## D-013 · Rescheduling and excuses (Team, trial rule)
- Moving a commitment to a later time **the same day** is free.
- Moving it to another day, or excusing it, needs a reason from a fixed list: illness, injury or symptoms, necessary rest or recovery, sleep, a calendar conflict, outside your control. A free-text note is optional. "Don't fancy it" isn't on the list (scenario C), so the coach offers a minimum version instead.
- Rescheduled and excused commitments leave the denominator. A missed one can't be rescheduled after the fact.
- Every change is logged with its reason.

## D-012 · Weights are frozen at approval (Team)
A commitment's weight can only change while it's proposed. That makes "no retrospective weight changes" (A5) a property of the code. Default weights run from 1 (light) to 5 (major), as below.

| Weight | Typical commitments |
|---|---|
| 1 | Laundry stage, quick tidy |
| 2 | Walk, evening self-care, meal prep |
| 3 | Rehab block, batch cook |
| 4 | Gym session |
| 5 | Rarely used |

## D-011 · The scheduling engine is pure Swift (Team)
Availability, travel padding, work protection and replanning are value types and functions with no framework dependencies, so they can be unit tested. The language model never decides whether something fits.

## D-010 · Day boundaries and defaults (Team)
| Setting | Default |
|---|---|
| Wake time | 05:55 weekdays |
| Bedtime | 22:30 |
| Wind-down from | 21:30 |
| Work hours | 08:00–16:00 |
| Peak focus | 13:00–16:00 |
| Lunch | 12:00–13:00 |
| Dinner | about 19:00 |

All are configurable. Work hours apply Monday–Friday unless the calendar shows leave.

## D-009 · Calendar roles are user-assigned (Team)
Each calendar visible in iOS is labelled once as Work, Personal, Shared (Becky) or Ignore. Inside Work calendars, events titled with *focus*, *deep work*, *heads down* or *do not book* are protected focus blocks; other timed events are meetings. Events marked *free* never block. Shared events are context only and never make the user busy (N4).

## D-008 · Outlook access path (User: "Not sure")
EventKit first: if the work account appears in iOS Calendar, it's read on device. Otherwise the app says plainly that it can't see work events and offers quick manual "busy until" blocks. Microsoft Graph is out of scope unless the employer approves an app registration (see `INTEGRATIONS.md`).

## D-007 · Apple Watch: yes (User)
A watchOS companion comes in Phase 3 for rest timers, haptics, session status and HealthKit workouts. The iPhone stays the set logger.

## D-006 · AI provider: Apple on-device (User)
Apple Foundation Models on iOS 26 (the user's iPhone supports Apple Intelligence). No cloud AI, no keys, no cost. Everything works with deterministic intent parsing when the model is unavailable or busy (scenario N). The code builds back to iOS 17 with `#if canImport(FoundationModels)` and availability checks. CI uses Xcode 26.3 so this code is compiled.

## D-005 · Money model: fines replace earnings (User)
- From **19 Oct 2026** (project start) activity no longer earns pence. Ledger lines before that date stay and still settle to Monzo as before.
- Month-end gold investing is switched off (`goldInvestingEnabled = false`); its code is kept.
- Fines run in **simulation** first (A7). No real money moves on fines until the rules have been reviewed after a trial month.
- Then the existing Starling → Monzo payout pays "£500 − fines" at month end, with approval in the Starling app as now.

## D-004 · Four tabs replace the single-page dashboard (Brief N1)
The 17 Oct request for a single page is superseded by the brief. The previous activity dashboard (period earnings, movement tiles, history) moves into **Progress → Activity**, so nothing is lost.

## D-003 · Keep Swift 5 language mode for now (Team)
Moving to Swift 6 strict concurrency means a project-wide audit. Not worth the risk during Phase 1; revisit in Phase 7.

## D-002 · Stay on the existing project and bundle ID (Brief §2)
The architecture suits the brief: SwiftUI, SwiftData, service protocols, pure domain. Changing the bundle ID would lose the user's Health permissions and data. Identifiers stay `FitnessVault`; the display name stays Vaultality.

## D-001 · No local Swift toolchain (Environment)
The cloud development environment can't install Swift. Builds and tests are verified on GitHub's macOS runner before anything is merged to `main`.
