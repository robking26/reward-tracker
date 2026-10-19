# Decisions

Newest first. Each entry records what was decided, why, and who made the call ("User" means answered by the user; "Team" means a default chosen because the question wasn't blocking).

## D-023 · Progress photos stay inside the app (Team)
Photos are copied into the app's own folder with complete file protection: unreadable while the phone is locked, kept out of the photo library, never uploaded. Each photo can be viewed, shared or deleted. "Delete all coach data" doesn't remove photos; they're managed in Progress.

## D-022 · Apple Watch role (Team, from W5)
- **iPhone:** stays the set logger.
- **Watch:** mirrors the rest countdown through WatchConnectivity, taps your wrist when rest is over, and can skip rest or end the workout. It runs an `HKWorkoutSession` (strength training) so it stays awake between sets and saves the session to Apple Health.
- **Starting:** starting a workout on the iPhone asks iOS to open the watch app (`startWatchApp`). That's best effort, so the watch app can also be opened by hand.
- **Cost:** the watch app needs its own App ID (`com.robking.FitnessVault.watchkitapp`), which counts towards the free team's App ID limit.

## D-021 · Rest timer everywhere (Team)
Logging a set starts the rest countdown in three places, so it's visible while you're in another app between sets:
- in the app;
- a rest-timer Live Activity on the Lock Screen and in the Dynamic Island, which counts down by itself and ends with the workout;
- a local "Rest's up" notification.

## D-020 · When a workout counts as done (Team)
- Ending a workout with at least one working set marks the agreed gym commitment done.
- What was done is logged as is, with no catch-up sets (scenario I).
- Progression only moves on sessions that hit the full target.
- Warm-up sets never count as working sets.

## D-019 · How the AI acts (Team)
- Known commands go to the rule-based parser: instant, offline, never sent to the model.
- Everything else goes to Apple's on-device model, with a **fresh session per message**. The prompt is a compact summary the app builds (today, calendar, free time, score, up to six relevant memories, the last six messages), because the model's context window is small.
- The model acts only through validated tools:
  - add task, suggest a commitment, update the current commitment, remember, find free time, list tasks;
  - a suggestion is always *proposed*, so it counts only after the user says yes;
  - an excuse needs a legitimate reason;
  - there are no money tools.
- "What changed" under a reply comes from the tools, never from the model's wording. A reply that claims a change no tool made gets a visible note.

## D-018 · Gym ramp and recovery (Team, trial rule)
- The weekly gym target is 2 sessions for the first two weeks from 19 Oct 2026, 3 for the next two, then 4.
- No gym suggestion after two consecutive days of workouts. Upper and lower alternate.
- Gym sessions are planned door to door: travel both ways, 10 minutes of changing, and 60 minutes of training. They never run into dinner (19:00–20:00) or wind-down.

## D-017 · Reminder levels (Team)
Only agreed commitments with a time get reminders, three at most:

| Level | When |
|---|---|
| Heads-up | 15 minutes before for gym and swim, 5 minutes before for everything else |
| "15 minutes before it gets difficult" | Grace period minus 15 minutes after the start |
| "Is there a genuine blocker?" | At the end of the grace period: 30 minutes for gym, swim, household, rehab and self-care; 20 for walks |

- No reminders during meetings, focus blocks, personal events, or before wake and after bedtime.
- Silent in the office.
- Rehab reminders are worded generically so the Lock Screen stays discreet.
- The plan is rescheduled only when it changes.

## D-016 · A calendar clash is excused automatically (Team)
When a new or moved calendar event overlaps an agreed commitment:
- the commitment is excused for "Something unavoidable came up", so it's never fined (S3);
- the coach offers the first same-day slot that fits;
- if the gym no longer fits anywhere, it offers a 30-minute walk instead.

Each clash is handled once.

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
