# Data model

All data is stored on device in SwiftData (`Persistence.schema`). Money is always integer pence. New attributes on existing entities are optional, so older stores open without a migration plan.

## Existing (v1)

| Entity | Purpose | Status |
|---|---|---|
| `MonthlyVault` | Month allowance and month-end close | Kept. The allowance is the £500 the fines are taken from. |
| `DailyActivity` | Health totals per day | Kept. Feeds Progress and walking baselines. |
| `RewardLedgerEntry` | Per-activity earnings lines | Kept read-only after the 19 Oct 2026 cutover (D-005). |
| `HealthSyncState` | Sync bookkeeping | Kept |
| `BankTransfer`, `PaymentOrder` | Starling releases and Monzo payments | Kept |
| `GoldAllocation` | Month-end gold | Dormant (D-005) |
| `Meal` | Retired nutrition v1 | Kept so stores open |
| `AuditEvent` | Append-only financial and coaching audit | Kept, now also records commitment changes |

## Coaching (v2, Phase 1)

### `Commitment`
One agreed (or proposed) action on a given day.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID, unique | |
| `day` | String `yyyy-MM-dd` | The day it counts towards |
| `title`, `detail` | String, String? | |
| `kindRaw` | `CommitmentKind` | workout, walk, swim, rehab, household, meal, selfCare, work, social, other |
| `stateRaw` | `CommitmentState` | See the state machine below |
| `weight` | Int, 1–5 | Frozen once approved (D-012) |
| `scheduledStart` | Date? | Nil means any time that day |
| `durationMinutes` | Int | |
| `sourceRaw` | routine / coach / user | |
| `routineID` | UUID? | Set when generated from a `Routine` |
| `objectiveRaw` | `Objective?` | O-A … O-D, or household |
| `reason` | String? | Why the coach suggested it (E4) |
| `excuseRaw`, `note` | `ExcuseReason?`, String? | |
| `assumedMissed` | Bool | Set by D-014 |
| `createdAt`, `updatedAt`, `approvedAt` | Date | |

**State machine** (`CommitmentRules.canTransition`):

```
proposed ──approve──▶ approved ──start──▶ inProgress ──done──▶ completed
   │                    │  │                 │
   └─cancel▶ cancelled  │  └─reschedule─▶ rescheduled (+ new approved copy)
                        ├─excuse(reason)─▶ excused
                        └─(day ends)─▶ pendingVerification ─▶ completed | missed | excused
missed ──correct(reason)──▶ completed | excused     (until the month closes)
completed ──correct──▶ missed
```

- **Applicable** (counted in the score): approved, in progress, completed, missed, pending verification.
- **Not applicable:** proposed, cancelled, rescheduled, excused.
- "Due later" is how an approved commitment with a future start is labelled, not a separate state.

### `CommitmentEvent`
Append-only history: `commitmentID`, `from`, `to`, `reason`, `actor` (user/coach/system), `at`. It answers "why did this change?" (E4).

### `Routine`
A pre-agreed recurring commitment: `title`, `kind`, `weight`, `weekdays` (bitmask, Mon = 1), `minuteOfDay?`, `durationMinutes`, `isEnabled`. Enabled routines create approved commitments each day without asking (A3). Suggested routines are seeded **disabled**.

### `DayRecord`
The daily reconciliation result.

| Field | Notes |
|---|---|
| `day` (unique) | |
| `applicableWeight`, `completedWeight` | |
| `scorePercent?` | Nil when there were no applicable commitments |
| `finePence` | After the monthly cap |
| `uncappedFinePence` | Before the cap |
| `finalisedAt?` | |
| `isSimulation` | |
| `explanation` | Shown to the user |

It's recomputed when a correction arrives before the month closes.

### `CoachMessage`
One conversation item: `role` (user/coach/system), `text`, `createdAt`, `quickReplies [String]`, `relatedCommitmentID?`, `toolSummary?`. The tool summary is the confirmation of what the app actually did.

### `MemoryRecord`
A structured memory (M1–M4).

| Field | Notes |
|---|---|
| `store` | profile, objective, routine, rehab, nutrition, inventory, social, work, decision, preference |
| `key`, `value` | Human-readable |
| `source` | userStated, brief, inferred, imported, system |
| `status` | confirmed, hypothesis, superseded |
| `confidence?` | |
| `sensitivity` | general, medical, financial, relationship, location |
| `createdAt`, `updatedAt`, `reviewAt?` | |

An inferred record is always a **hypothesis** until the user confirms it (M3).

### `TaskItem`
A backlog task: `title`, `area` (household, houseSale, personal, work), `parentID?`, `dependsOn [String]`, `estimatedMinutes`, `priority` 1–5, `state` (open, inProgress, parked, done, dropped), `resumeNote?` (C4), timestamps.

## Settings additions (`AppSettings`, Codable)

- `coach: CoachSettings`: wake, bedtime, work and lunch windows, focus window, workdays, fine schedule (bands and cap), simulation flag, and calendar roles keyed by EventKit calendar identifier.
- `activityEarningsEndDay`: the cutover day.
- `goldInvestingEnabled`.

## Planned (later phases)

`WorkoutSession`, `ExerciseSet`, `ExercisePlan`, `SymptomLog`, `BodyMetric`, `ProgressPhoto` (file-protected), `Recipe`, `Ingredient`, `InventoryItem`, `Receipt`, `ShoppingList`, `SocialEvent`. Each is added in its phase with optional attributes, so migration stays lightweight.
