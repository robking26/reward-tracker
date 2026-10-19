# Vaultality 2.0 — Product requirements

This condenses the Vaultality 2.0 brief (19 Oct 2026) into stable, numbered requirements. Code, tests and the implementation checklist refer to these IDs. The user's decisions on conflicts are in `DECISIONS.md`.

**Promise:** "Vaultality understands my life, knows what matters to me, and helps me take the next action."

**Principles (P1–P12):**
- P1: the coach plans; the user stays in control.
- P2: understand real context before recommending.
- P3: one actionable suggestion beats ten tasks.
- P4: plans adapt.
- P5: remove obstacles in advance.
- P6: firm accountability, never shame.
- P7: tangible progress over perfect streaks.
- P8: protect enjoyment, relationships and recovery.
- P9: every activity serves an objective, a responsibility or quality of life.
- P10: minimise screen time, notifications, data entry and decisions.
- P11: native iOS quality.
- P12: no new recurring costs.

**Single user.** Becky (wife) is context, never a coached user: no monitoring, tasks, scoring or penalties for her.

## Target user (U)

- **U1:** 32, UK, senior product designer, ADHD.
  - Hard to start tasks; long focus once going; hard to restart after interruptions.
  - Overwhelmed by big lists; likes structure but not repetition.
  - Motivated by tangible results and by fear of losing money; wants firm, direct coaching.
  - Forgets evening self-care; wants less non-work screen time.
- **U2:** completed 75 Hard, then a broken streak collapsed motivation. **No unbroken streaks as the main progress mechanism**; a miss never means the transformation has failed.

## Twelve-month objectives (O), 19 Oct 2026 – 19 Oct 2027

- **O-A Health and body composition**
  - Starts at about 95.3 kg and about 30% body fat; aims for 10–12%, safely.
  - Building to 4 gym sessions a week (2 upper, 2 lower) plus 1 attached swim.
  - Steps building gradually towards 12,500. The 7,000 starting aim must be checked against the real Health baseline.
  - Better sleep and recovery.
  - Weight and body fat are trends, not truths.
- **O-B Knee rehab, return to five-a-side** (by Oct 2027, only if functionally ready)
  - History: right lateral knee, IT-band-related; running and changing direction provoke symptoms; pain can be delayed; previous reinjury.
  - Rehab is built into gym sessions. No diagnosis, no automatic loading increases.
  - The date is not medical clearance.
- **O-C Home move:** sale preparation around Jan/Feb 2027, ideally moving within about 6 months.
- **O-D Lifestyle and presence**
  - Less drinking, little or no vaping, gambling not automatic, varied social activities.
  - More time with Becky, spontaneity, protected evenings, self-care, preparing for children.
  - Pregnancy and house outcomes are never scored.

## Navigation (N)

- **N1:** four tabs: **Today** (default), **Coach**, **Calendar**, **Progress**. Settings opens as a sheet from any tab.
- **N2 Today**
  - Shows the current action (visually dominant), the next commitment, the next opportunity, essentials still due, completion status, the potential financial consequence and a short coach line.
  - Never shows the whole backlog or the whole week.
  - Quick actions: Done · Start · Not now · Change plan · Something's blocking me · Talk to coach.
- **N3 Coach:** a messaging-style conversation.
  - Input: text, dictation, voice notes, spoken replies, images, recipe screenshots, PDFs, receipts.
  - Persistent history, contextual quick replies, deep links.
  - Natural-language commands act on the same data as the UI. The AI may only say something was saved after a tool call has confirmed it.
- **N4 Calendar:** a consolidated, **read-only** view of external calendars (Outlook work, Apple personal, shared with Becky) plus internal coach objects.
  - Distinguishes work meetings, work focus blocks, personal, shared, coach suggestions, confirmed commitments and flexible opportunities.
  - Day view first, week view second.
  - A blank slot isn't free time. Focus blocks are protected. Becky's events don't make the user busy.
- **N5 Progress:** rolling trends and cumulative totals.
  - Covers weight, body fat, weekly photos (private; delete and export), strength, workout consistency, swimming, walking, rehab, road to five-a-side, house-sale preparation, consistency and recovery, and money retained.

## Coach (C)

- **C1 Personality:** direct, firm, warm, concise British English. One question at a time. Never re-asks what memory already knows. No speeches.
- **C2 Intelligence:** finds the highest-value next action, anticipates blockers, offers small starting steps, protects focus, recognises genuine changes and challenges avoidance without diagnosing.
- **C3 Launch mode:** step-by-step task initiation that backs off once the user starts.
- **C4 Pause and resume:** before a meeting or the end of work, ask "Where have you got to?" and store the voice note on the task. On return, restate where they left off.

## Memory (M)

- **M1:** structured, durable, searchable stores: profile, objectives, calendar context, routines, commitments, task backlog, workouts, rehab, nutrition/recipes, inventory, accountability, social, conversation, coach decisions.
- **M2:** each record has an id, type, value, source, created and updated times, confidence/verification, review or expiry, correction and deletion.
- **M3:** user-stated facts are kept distinct from inferred hypotheses. A guess is never silently promoted to a fact.
- **M4:** the user can inspect, correct, export and delete. Medical, financial, relationship and location records carry privacy controls.

## Morning briefing (B)

- **B1:** never starts automatically. The user finishes their routine (wake about 05:55 on weekdays), then says or taps **"I'm ready"**.
- **B2:** inputs include calendar changes, work location, workload, Becky's events, recovery, the knee, weather, travel, meal prep, essentials, unfinished tasks and social plans.
- **B3:** suggestions come conversationally, **one at a time**. Accepting one makes it a commitment. It's about today, not a goals report.

## Scheduling (S)

- **S1:** a deterministic engine, separate from the language model.
  - Inputs: availability, travel, location, duration, preparation, dependencies, recovery, work constraints, weather, energy, deadlines, importance and preferences.
- **S2 Work**
  - Window about 08:00–16:00; peak design focus about 13:00–16:00; prefers to finish at 16:00.
  - Personal projects never displace employment work.
  - Office days (read from the calendar): fewer, discreet prompts and no voice.
  - Workload light/normal/heavy. Work time is borrowed only with explicit approval when workload allows.
- **S3 Replanning:** triggered by relevant calendar changes, confirmed plan changes and meaningful transitions. Never regenerates the whole day needlessly.
  - Example: a meeting appears over a gym slot. Find another feasible slot (including travel), keep dinner around 19:00, protect evening self-care and sleep, offer a walk as a fallback, move the workout within the week, and **no fine**.
- **S4:** never claims real-time monitoring when refresh is periodic.

## Location and gym (L)

- **L1:** primary gym Nuffield Health Bolton.
  - Door-to-door time = travel + changing + workout + travel home.
  - Occupancy only from legitimate sources or labelled estimates and feedback; never invented.
  - Persistent location monitoring needs consent.

## Workouts (W)

- **W1:** 4 sessions of 45–60 minutes (2 upper, 2 lower) including warm-up and rehab, plus 1 attached swim, ramping up gradually.
- **W2 Progression**
  - Usually 3×10 (8–10 acceptable; some lifts 3×8).
  - Move up one increment after hitting the target in **three consecutive relevant sessions**.
  - Hold or reduce when technique or symptoms say so. Never progress just because time passed.
- **W3:** the starting loads table in the brief are expectations to validate in the first session.
- **W4 Set logger (on the iPhone)**
  - Shows proposed and actual weight and reps.
  - Logging a set starts the rest countdown. After the final set, show the next exercise and wait for "ready".
  - Equipment busy → alternative or reorder. Extend only when the calendar allows. End workout.
  - Short on time: supersets or cut optional accessories, never rehab.
  - An incomplete workout counts what was done, with no catch-up sets.
  - Heavy compound lifts get proper rest.
- **W5 Apple Watch:** rest timers, haptics, progress and status. The phone is the logger. Timers don't need the phone in the foreground. Ending on either device closes and saves the session.

## Rehab (R)

- **R1:** hip and glute strength, hip control, single-leg stability, step-downs, balance. These are candidates from earlier physio advice and don't replace a clinical prescription.
- **R2:** rehab defaults to the start of the session after the warm-up (ask each time). 10–15 minutes on lower days, optional on upper days, within the session length.
- **R3:** tracks balance, reps, resistance, tolerance, and symptoms during activity and **the next day**, plus progress towards running and changing direction.
  - Worsening or concerning symptoms → recommend professional care.
  - Never auto-clears the user for football.

## Walking (K)

- **K1:** starting baseline from Health; gradual progression within knee tolerance.
- **K2:** lunchtime preferred. 5-minute heads-up, then "Trainers on". Avoid rain.
- **K3:** running isn't recommended until the knee is ready. Quiet walks aren't turned into mandatory mindfulness.

## Swimming (SW)

- **SW1:** now about 20–25 minutes of front crawl, resting every 4 lengths of a 25 m pool. Former competitive swimmer.
- **SW2:** aim to rebuild for Darwen Masters (60–90-minute sessions) within 12 months.
  - One weekly committed swim once capacity allows, attached to a gym visit.
  - Low pressure: track duration, lengths and distance from the watch, plus the knee response.
- **SW3:** the kit-ready state and its laundry dependency are tracked.

## Nutrition (F)

- **F1 Safety**
  - Binge and secret eating history: no fasting or aggressive deficits by default, no moralising foods, no compensatory exercise.
  - Calorie guidance is transparent, conservative and adjustable; suggest a dietitian before anything restrictive.
  - **Food, weight, binges, skipped meals and calories never create fines.**
- **F2 Meals**
  - Breakfast: optional, pre-prepared, high protein.
  - Lunch: the same Monday–Friday is fine on a 4-week rotation (chicken, turkey mince, pork, rice, vegetables, sauces), microwave at work, batch-cooked weekly.
  - Dinner: shared with Becky, **two identical portions**, about 19:00, varied, never repetitive. Friday can be a fakeaway, cooking or eating out.
- **F3 Exclusions:** mushrooms, courgette, cauliflower.
- **F4 Equipment:** air fryer, oven, microwave, slow cooker, hob. **No dishwasher**, so washing up should take 5–10 minutes at most; prefer one-pot, one-pan or tray bakes.
  - Slow-cooker prep only on work-from-home mornings, never on office days.
- **F5 Batch cooking:** one hour at most covering 5 lunches plus extra freezer dinners. If it doesn't fit, adjust the recipes rather than pretend.
- **F6:** keep 2–3 favourite emergency freezer meals plus takeaway-style options.
- **F7 Recipe library**
  - Imports from camera, screenshots, PDFs, files, manual entry and conversation.
  - Extracts ingredients, quantities, steps, servings, timings, washing-up time and estimated macros, with uncertainty shown.
  - Optimises macros without changing the taste; a change to flavour needs approval.
  - Learns preferences. Copyright-aware personal use only.

## Shopping and inventory (I)

- **I1:** Aldi first, Co-op fallback.
  - **£400 a month household ceiling** covering groceries, toiletries, cleaning, Co-op top-ups, and takeaways or meals out paid from the food budget.
  - It's a ceiling, not a target.
- **I2 Flow:** meals → quantities → inventory check → consolidate → round to pack sizes → group by Aldi department → tappable list → receipt → spending → inventory.
- **I3 Receipts:** merchant, date, line items, quantities, total; uncertain items flagged; duplicates refused; reviewable; manual entry possible.
- **I4 Inventory:** probabilistic. Never "definitely present" from an old receipt. Conversational corrections. No barcode chores. No toothbrush-head or razor replacement alerts.
- **I5 Defrosting:** anticipate safe thawing, with a safe alternative if it was forgotten.

## Social, drinking and recovery (SO)

- **SO1 Eating out:** recommend dishes from the menu and nutrition data where available; say when it's estimated; never spoil the occasion.
- **SO2 Drinking**
  - Typically 4–10 pints. The aim is less automatic drinking, not abstinence.
  - Offer advance plans (alcohol-free, lighter, moderate, alternative activities). No prompts during events.
  - Never imply multi-day heavy drinking is risk-free. No drinking before driving.
  - No gambling suggestions or alcohol-to-gambling links.
- **SO3 Recovery (48–72 h)**
  - Before the event: easy food ready, chores reduced, expectations realistic.
  - During recovery: hydration, normal meals, sleep, gentle movement only if well.
  - On return: restart with one manageable action.
  - Patterns are tracked only with consent. Recovery or illness never brings a penalty.

## Household and house sale (H)

- **H1:** routine tasks with dependency chains (wash → dry → put away; clean pan → prep → cook → eat → wash up). The first stage doesn't complete the chain.
- **H2:** sale backlog: attic (tidy, sort, remove, tip runs), carpets, paint touch-ups, kitchen and office skirting, main bedroom, jet-wash the rear, paint the rear walls, repoint the front patio, deep clean, estate agents, valuation and photography.
  - Broken into small subtasks; never shown all at once.
- **H3:** opportunity tasks sized to gaps (5/10/15/30 minutes) with a buffer.
  - The user picks from 2–3. Repeated avoidance of a high-priority task gets challenged.
  - Rest stays available. Becky is never assigned tasks.

## Relationship (RE)

- **RE1:** Becky's shared calendar informs gym timing, meals, joint free time, dates and weekends.
  - Suggestions are spontaneous ("You're both free tonight. Fancy badminton?"), sometimes further ahead (a night in the Lakes).
  - Ask for a budget when suggesting paid activities. Not every weekend has to be productive.

## Financial accountability (A)

- **A1:** £500 a month in Starling (already the user's money). **Transferable = £500 − confirmed applicable fines.** Fines stay in Starling and are never spent or moved.
- **A2 Daily score → fine**

  | Daily score | Fine |
  |---|---|
  | 80–100% | £0 |
  | 60–79% | £5 |
  | 40–59% | £10 |
  | Below 40% | £15 |

  - The monthly fine cap is **£100**. All of these values are configurable and reviewed after a trial.
- **A3 Weighted commitments:** weight reflects priority, time, difficulty, urgency, dependencies, opportunity, capability and agreement. Pre-agreed essential routines count without daily approval.
- **A4 States:** proposed, approved/pre-agreed, due later, in progress, completed, missed, excused, rescheduled, cancelled before commitment, pending verification.
  - Only applicable states count in the denominator.
  - A genuine miss can't be erased by inventing new tasks, but completing the remaining ones can still raise the score.
  - The day stays open through the evening routine; nothing is final until daily reconciliation.
- **A5 Live projection:** confirmed completion, remaining commitments, possible final score, potential fine, month-to-date fines and the month-end transfer estimate.
  - Never shows a misleading 100% while evening items remain.
  - Explains every penalty. Weights are never changed retrospectively.
- **A6 Never fine for** weight, food, binges, skipped meals, calories, illness, necessary rest, injury symptoms, sleep, genuine scheduling impossibility or circumstances outside the user's control.
  - No compounding, no debt, nothing beyond the allocation, no escalation, no artificial urgency.
- **A7 Banking:** ledger first, simulated first. Real transfers only after review, with explicit authorisation, idempotency and reconciliation. Never automate bank security screens. If automation isn't available, give a manual month-end instruction and confirmation.

## Notifications (NO)

- **NO1:** contextual and limited, at natural transitions: briefing requested, meeting ended, commitment approaching, departure, laundry done, start cooking, end of work, evening self-care.
- **NO2:** escalating firmness only for agreed, realistically actionable tasks (three levels). Never insulting, body-shaming or financially threatening.
  - Silence is never proof of a miss.
  - Respects Focus, meetings, quiet hours, sleep, office mode, permissions and accessibility.

## Widgets and Live Activities (WG)

- **WG1 Lock Screen:** next action, time to the next commitment, activity, important events. Discreet: no sensitive health data or fines without consent.
- **WG2 Live Activities and Dynamic Island:** rest timer, active workout, departure countdown, task timer, cooking timer. Never an all-day agent.
- **WG3 Home Screen:** what's next, essentials, activity, workout shortcut, weekly progress. Actionable where supported.

## Input (V)

- **V1:** voice at home, text in the office, quick voice notes, photos, receipts, recipes and natural-language task creation, all in one conversation history.
- **V2:** use on-device Apple speech; don't assume cloud voice is free.

## AI (AI)

- **AI1:** zero added cost. The provider sits behind an abstract interface.
  - Operations: respond, interpret intent, structured action proposal, explain, summarise, extract recipe, interpret receipt, decompose task.
- **AI2:** deterministic code owns calendar maths, timing, task state, fines, progression, ingredient maths, budgets, notifications, HealthKit writes and the ledger.
- **AI3:** tool calls take validated, structured arguments, and every recommendation passes deterministic feasibility and safety checks. The AI never executes anything financial.
  - The app degrades gracefully when the model is unavailable or rate-limited (scenario N).

## Engineering, privacy and reliability (E)

- **E1:** Swift, SwiftUI, Swift concurrency, SwiftData, HealthKit, EventKit, UserNotifications, WidgetKit, ActivityKit, App Intents, Core Location, watchOS/WatchConnectivity. No cross-platform frameworks or web views.
- **E2:** fast, works offline at its core, dark mode, Dynamic Type, VoiceOver, contrast, Reduce Motion, clear loading and error states, battery-aware.
- **E3 Privacy:** collect as little as possible; local first; encrypted at rest; secrets in the Keychain; nothing committed; no embedded production secrets.
  - Explicit permissions that can be revoked. Export and delete. Work meeting details aren't sent externally.
- **E4 Pipeline:** inputs → state → opportunities → constraints → candidates → validation → recommendation → response → persisted outcome.
  - Every recommendation carries its reason, objective, duration, preparation, dependencies, constraints, confidence and an alternative.
  - Explicit event and state model; no duplicate notifications or penalties; a record of why things changed.
  - Plausible user corrections override device telemetry.

## Acceptance scenarios

A–O as written in the brief, mapped to tests in `TEST_PLAN.md`.
