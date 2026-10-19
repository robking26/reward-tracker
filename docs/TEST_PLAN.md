# Test plan

Automated tests run on every push (GitHub Actions, iOS simulator). Deterministic logic is tested directly. Anything needing permissions, a device or an account is tested by hand on the user's iPhone and recorded here.

## Acceptance scenarios

| ID | Scenario | Automated coverage | Manual on device |
|---|---|---|---|
| A | Normal work-from-home day | Phase 2: briefing produces one suggestion at a time; accepting creates an approved commitment | Full morning → evening run |
| B | Unexpected Outlook meeting over the gym | **Phase 1:** availability recomputed around the new meeting; a calendar-conflict excuse removes the commitment from the score (no fine). Phase 2: replanner offers a feasible slot. | Add a meeting to a calendar visible in iOS |
| C | Avoidance | **Phase 1:** "don't fancy it" isn't an excuse reason, so the commitment stays applicable. Phase 2: coach offers a minimum version. | |
| D | Knee symptoms | Phase 3: pain report blocks progression and swaps lower-body load | |
| E | Social weekend | Phase 6 | |
| F | Five-minute gap | **Phase 1:** availability returns work-gap windows only for micro tasks. Phase 2: 2–3 feasible tasks. | |
| G | Dinner not prepared | Phase 4 | |
| H | Equipment busy | Phase 3 | |
| I | Incomplete workout | Phase 3: completed sets persist, no catch-up | |
| J | Evening routine outstanding | **Phase 1:** projection never shows 100% confirmed while applicable items are open; no fine before reconciliation | |
| K | Financial cap | **Phase 1:** band boundaries (79/80, 59/60, 39/40), £100 monthly cap, no fine beyond the allocation, empty day = no fine | |
| L | Offline | Phase 1: all coaching data is local; intents work without a network | Airplane-mode run |
| M | Limited calendar permission | **Phase 1:** a missing work calendar produces an explicit notice, not "free" | Deny calendar access |
| N | No model | **Phase 1:** deterministic intent parser handles core commands with no model | Disable Apple Intelligence |
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

## Manual device checklist (Phase 1)
- [ ] Calendar permission prompt appears from Settings → Privacy, not on launch
- [ ] Each calendar can be labelled; work focus events show as protected
- [ ] Dictation in Coach works in airplane mode (on-device recognition)
- [ ] Health sync and the widget still work after the update
