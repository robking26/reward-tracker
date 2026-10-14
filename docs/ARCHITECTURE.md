# Architecture and roadmap

## Layers

| Layer | Where | Notes |
|---|---|---|
| Presentation | `Features/`, `DesignSystem/` | SwiftUI only. Views read derived state from `AppModel` and never calculate money. UIKit is used only for the camera (`CameraPicker`). |
| Orchestration | `App/AppModel.swift` | `@Observable`, `@MainActor`. Runs sync → reward calculation → ledger → settlement. |
| Reward engine | `Domain/RewardEngine.swift` | Pure function of one day's cumulative metrics. Deterministic. |
| Ledger | `Domain/Ledger.swift` | Append-only lines with stable IDs. Reconciles towards calculated totals, applies the monthly cap and skips final days. |
| Settlement | `Domain/MoneyMovement.swift` | Pure rules for releases, payments, money-flow states and monthly funding. |
| Health | `Services/Health/` | `HealthDataProviding` protocol, plus `HealthKitService` (live) and `MockHealthService`. |
| Meal analysis | `Services/Meals/` | `MealAnalyzing` protocol, plus `MockMealAnalyzer` and `RemoteMealAnalyzer` (your own server). |
| Banking | `Services/Banking/` | `BankingService` protocol, plus `StarlingClient` and `MockBankingService`. |
| Persistence | `Persistence/` | SwiftData: `MonthlyVault`, `DailyActivity`, `RewardLedgerEntry`, `Meal`, `HealthSyncState`, `BankTransfer`, `PaymentOrder`, `AuditEvent`. Settings are `AppSettings` (Codable) in `UserDefaults`; secrets go in the Keychain. |
| Notifications | `Services/Platform/Notifications.swift` | Local notifications only. |

`RewardRule` from the spec is `RewardRates` plus `NutritionTargets`. `NutritionEstimate` is a value type stored on `Meal`.

## Financial safety rules (enforced in code)

- All money is `Pence` (an integer). Floating point is used only to draw progress bars.
- The ledger never exceeds the month's allocation (`LedgerReconciler`).
- Syncing the same data twice adds nothing, because lines are reconciled against totals and not appended per sample.
- Deleted or corrected Health samples produce negative correction lines. Days become final after `lockAfterDays` (7).
- A transfer or payment intent is saved *before* calling Starling, so a crash can't lose track of it.
- A transfer is retried with the same UID, which Starling treats as idempotent.
- A payment with an unknown outcome becomes *Needs checking*. It blocks new payments and is never resent automatically.
- A payment is marked paid only when Starling's status says so.
- Production requires a separate token, the Live environment and an explicit opt-in. Demo mode always pairs mock Health with the mock bank.

## Platform constraints (verified, not assumed)

- **Health permissions:** iOS never tells an app whether reading was allowed. The app shows "Connected" once the request has been made, and explains where to check if data is missing.
- **Background work:** HealthKit background delivery and `BGAppRefreshTask` are best effort. iOS decides when they run, and Health data is unavailable while the phone is locked. So the 08:00 settlement also runs whenever you open the app after 08:00. No server can read HealthKit.
- **Exercise minutes:** read from `appleExerciseTime`, a public read-only HealthKit type. Heart rate is never used.
- **Strength:** only `traditionalStrengthTraining` and `functionalStrengthTraining` workouts, de-duplicated by workout UUID and assigned to the day the workout started.
- **Starling payments:** with a personal access token, payments to a payee must be approved in the Starling app. The app never tries to approve them.

## Roadmap

| Phase | Status |
|---|---|
| 1. App foundation: navigation, design system, four tabs, reusable components | Done |
| 2. Reward engine: rates, daily calculation, monthly cap, persistent ledger, unit tests | Done |
| 3. Apple Health: permissions, reading, workout classification, sync, reconciliation | Implemented; needs on-device testing |
| 4. AI meal logging: camera, analysis protocol, review, limits, totals, Health writing | Implemented with the mock analyser. **Next: the analysis backend.** |
| 5. Starling sandbox: connection, balances, releases, payment initiation, status | Client written against the documented v2 API. **Next: check the request and response shapes against the sandbox, especially local payments and payment-order status.** |
| 6. Production: live config, real-device testing, accessibility audit, performance | Not started |

### Meal analysis backend (to do)

The app posts a resized JPEG to `POST {endpoint}` with `Authorization: Bearer <device token>` and expects `NutritionEstimate` JSON back:

```json
{ "name": "…", "items": ["…"], "portionDescription": "…", "kilocalories": 0,
  "proteinGrams": 0, "carbohydrateGrams": 0, "fatGrams": 0, "confidence": "low|medium|high" }
```

The AI provider's key belongs only in that server's environment configuration, never in GitHub or the app. Pick a provider and check its pricing and usage limits before relying on it. Live analysis isn't free by default.
