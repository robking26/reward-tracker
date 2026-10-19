# Test plan

Automated tests run on every push (GitHub Actions, iOS simulator). Deterministic logic is tested directly. Anything needing permissions, a device or an account is tested by hand on the user's iPhone and recorded here.

## Acceptance scenarios

| ID | Scenario | Automated coverage | Manual on device |
|---|---|---|---|
| A | Normal work-from-home day | **Phase 2:** `RecommendationEngineTests` and `CoachPlanningTests.testBriefingOffersOneThingAtATime`: walk, gym with Becky, self-care; one at a time; yes and no chain | Full morning → evening run |
| B | Unexpected Outlook meeting over the gym | **Phase 1–2:** availability recomputed; the clash is excused (no fine) and a same-day slot is offered, or a walk if the gym no longer fits (`CoachPlanningTests`, `ReplannerTests`) | Add a meeting to a calendar visible in iOS |
| C | Avoidance | **Phase 1–2:** "don't fancy it" isn't an excuse, even through the AI tools; the coach offers ten minutes as a minimum; reminders escalate in three levels (`NotificationPlannerTests`) | |
| D | Knee symptoms | Phase 3: pain report blocks progression and swaps lower-body load | |
| E | Social weekend | Phase 6 | |
| F | Five-minute gap | **Phase 1:** availability returns work-gap windows only for micro tasks. Phase 2: 2–3 feasible tasks. | |
| G | Dinner not prepared | **Phase 4:** `KitchenDomainTests.testDinnerRescueOffersLowFrictionOptions`, `KitchenModelTests.testDefrostReminderAndForgottenDefrost`: options come from what's probably in, the freezer, a Co-op top-up or a takeaway within budget. A forgotten defrost gets the safe microwave route. | Tap "Forgot" on the Dinner card |
| H | Equipment busy | Phase 3 | |
| I | Incomplete workout | Phase 3: completed sets persist, no catch-up | |
| J | Evening routine outstanding | **Phase 1:** projection never shows 100% confirmed while applicable items are open; no fine before reconciliation | |
| K | Financial cap | **Phase 1:** band boundaries (79/80, 59/60, 39/40), £100 monthly cap, no fine beyond the allocation, empty day = no fine | |
| L | Offline | Phase 1: all coaching data is local; intents work without a network | Airplane-mode run |
| M | Limited calendar permission | **Phase 1:** a missing work calendar produces an explicit notice, not "free" | Deny calendar access |
| N | No model | **Phase 1–2:** the parser handles core commands; with the model unavailable or failing, the coach explains and carries on (`CoachAITests`) | Disable Apple Intelligence |
| O | Ill or exhausted | **Phase 1:** illness, injury, rest and sleep excuses are fine-free; food and weight inputs don't exist in scoring | |

## Unit suites

| Suite | Covers |
|---|---|
| `RewardEngineTests`, `LedgerTests`, `SettlementTests`, `InvestingTests`, `MonthEndSettlementTests`, `CalendarKeyTests` | v1 money (still in use for pre-cutover earnings) |
| `CommitmentRulesTests` | Allowed and forbidden transitions, frozen weights, corrections |
| `DayScoringTests` | Applicable set, live projection, bands, cap |
| `AvailabilityTests` | Work protection, focus, lunch, shared events, travel padding, minimum durations |
| `CalendarClassifierTests` | Roles, focus keywords, free and all-day events, office hints |
| `CoachIntentTests` | Natural-language command parsing |
| `RecommendationEngineTests`, `ReplannerTests`, `NotificationPlannerTests`, `MemoryRetrieverTests` | Phase 2 engines |
| `CoachPlanningTests` | Briefing, replanning, reminders, launch mode through `CoachModel` |
| `CoachAITests`, `ToolParsingTests` | Model routing, validated tools, honesty guard, fallback, compact context |
| `TrainingTests`, `TrainingModelTests` | Phase 3 programme, progression, knee rules and the workout logger |
| `KitchenDomainTests` | Ingredient and recipe parsing, nutrition confidence, exclusions, macro tweaks, meal planning, batch-cook fit, defrost reminders, dinner rescue, inventory presence, shopping list, budget, receipts, kitchen intents, starter recipes |
| `KitchenModelTests` | Seeding and weekly plan, conversational corrections, list ticking, freezer portions, defrost, receipts and the ceiling, task chains |

## Manual device checklist (Phase 1)
- [ ] Calendar permission prompt appears from Settings → Privacy, not on launch
- [ ] Each calendar can be labelled; work focus events show as protected
- [ ] Dictation in Coach works in airplane mode (on-device recognition)
- [ ] Health sync and the widget still work after the update

## Manual device checklist (Phase 2)
- [ ] "I'm ready" gives one suggestion at a time; Yes/No moves to the next
- [ ] Add a meeting over an agreed gym session in Calendar: the coach messages within a minute of opening the app, with no fine
- [ ] Reminders arrive for an agreed walk: 5 minutes before, then 5 and 20 minutes after; silent on office days
- [ ] With Apple Intelligence on, "Find us something to do Friday" gets a model reply; with it off, the coach explains
- [ ] Dictate a message at home: the reply is spoken

## Manual device checklist (Phase 4)
- [ ] Today shows tonight's dinner; "Eaten" on a freezable dinner adds its spare portions to the freezer
- [ ] Kitchen → Recipes → Add a recipe: scan a cookbook page, then a screenshot, then a PDF; check what was read before saving
- [ ] Kitchen → List → Build from meals: grouped in Aldi order; ticking marks things as in
- [ ] Scan an Aldi receipt; scanning the same receipt again is refused
- [ ] Plan a freezer meal for tomorrow: the defrost reminder arrives at 20:30
- [ ] Say "We've run out of milk" and "We've got three portions of curry left" to the coach
