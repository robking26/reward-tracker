# Vaultality 2.0 — Initial audit

Audited 19 October 2026 at `88bc182` (main). Scope: the native iOS app in this repository. The repo also holds `index.html`, the original web reward tracker; it isn't built or shipped and is left as is.

## What exists

| Area | Current state | Files |
|---|---|---|
| Project | Xcode 16+ project, file-system-synchronised groups, one shared scheme. iOS 17.0 deployment target, iPhone only, Swift 5 language mode. Bundle `com.robking.FitnessVault`, free personal team `P9VHAY42J5`. | `FitnessVault.xcodeproj` |
| Targets | App, Widget extension (`FitnessVaultWidget`), unit tests (`FitnessVaultTests`). No watchOS target. | |
| Architecture | One `@Observable @MainActor AppModel` (≈1,000 lines across two files) orchestrating Health sync → reward engine → ledger → Starling settlement → month-end gold. Pure domain types in `Domain/`, services behind protocols with mocks. | `App/`, `Domain/`, `Services/` |
| Persistence | SwiftData: `MonthlyVault`, `DailyActivity`, `RewardLedgerEntry`, `Meal` (retired), `HealthSyncState`, `BankTransfer`, `PaymentOrder`, `AuditEvent`, `GoldAllocation`. Settings are a Codable struct in `UserDefaults` with version-tolerant decoding. | `Persistence/` |
| Apple Health | Read-only. Steps, swimming/running distance, strength workouts (deduplicated by UUID), exercise minutes, active energy, flights, Activity rings. Observer queries plus hourly background delivery (entitlement added 17 Oct 2026). | `Services/Health/` |
| Money | Integer `Pence`. Per-activity reward rates (steps, gym, swim, run, energy, flights) accrue into an idempotent ledger capped at a £500 monthly allowance. Daily settlement releases money from a Starling Savings Space and creates a payment to the Monzo payee that **you approve in the Starling app**. At month end the unearned remainder goes to a Trading 212 gold ETC (demo first). | `Domain/`, `Services/Banking`, `Services/Investing`, `App/AppModel+Gold.swift` |
| UI | Single-page dashboard (Day/Week/Month earnings, movement tiles, history). Settings sheet holds Money & Vault, Starling, Trading 212, Health, notifications, CSV export and demo mode. Dark charcoal design system. | `Features/`, `DesignSystem/` |
| Widgets | Home Screen small/medium/large and Lock Screen circular/rectangular/inline. They read a snapshot the app writes to the app group. | `FitnessVaultWidget/`, `Shared/` |
| Background | `BGAppRefreshTask` near the settlement time, HealthKit observers, a sync every minute while the app is open. | `App/FitnessVaultApp.swift` |
| Notifications | Four immediate local notifications (payment awaiting approval, paid, vault complete, daily progress). Nothing is scheduled. | `Services/Platform/Notifications.swift` |
| Secrets | Starling and Trading 212 tokens are in the Keychain only (`Keychain.swift`). A search of the tracked files found no credentials. `.gitignore` covers Xcode user data. | |
| Tests | 60 unit tests (reward engine, ledger, settlement, investing, month-end, calendar keys), all passing on CI. No UI tests. | `FitnessVaultTests/` |
| CI | GitHub Actions on macOS 15: unsigned simulator build plus tests. Xcode 16.4 until this change, now Xcode 26.3. | `.github/workflows/ios.yml` |

## Reuse, refactor, replace

**Reuse as is**
- The design system: `Palette`, spacing, surfaces, `MoneyText`, `NoticeBanner`, `SectionHeader`, `ValueRow`, `MetricCard`, `CardButtonStyle`.
- The `Pence` money type and the `DayKey`/`MonthKey` calendar keys.
- The HealthKit service. Walking, swimming and workout history for Progress and the step baseline all come from it.
- The Keychain, `NetworkMonitor`, `AuditEvent` and the SwiftData container setup.
- The Starling client and the idempotent transfer/payment machinery. It will later pay "£500 minus fines" to Monzo.
- Widget plumbing (app group snapshot, timeline provider) and CI.

**Refactor**
- `RootView`: the single page becomes four tabs (Today, Coach, Calendar, Progress). The existing activity dashboard moves into Progress.
- `AppModel` is already too broad. Coaching state goes in a separate `CoachModel`, and AppModel keeps Health and banking.
- `Notifier`: from four immediate alerts to scheduled, contextual and rate-limited notifications (Phase 2/7).
- The widget snapshot: from "earned today" to next action, commitments and activity (Phase 7).
- Settings gains Privacy & Permissions, Calendars, Coach Memory and data export/delete.

**Retire (kept in code, switched off)**
- Per-activity pence earnings stop from 19 Oct 2026, the project start. Earlier ledger lines remain and still settle.
- Month-end gold investing through Trading 212 stops. The code stays for possible reuse; the user chose to keep fines in Starling.

**New**
Everything in `PRODUCT_REQUIREMENTS.md` beyond the above: commitments, scoring and fines, calendar, scheduling engine, coach conversation and memory, on-device AI, workouts and the watch, rehab, nutrition, inventory and receipts, household tasks, notifications, Live Activities, App Intents.

## Technical blockers and platform limits (verified where marked)

| Item | Status | Consequence |
|---|---|---|
| No Swift toolchain in the cloud development environment (verified: download.swift.org and apt are blocked by the proxy) | Blocker for local compiles | Every compile goes through the GitHub macOS runner (~11 min). Changes are batched and written carefully. |
| Apple Foundation Models needs iOS 26 on an Apple Intelligence iPhone (15 Pro or later). The user confirmed their device qualifies. | OK | Compiled behind `#if canImport(FoundationModels)` and `@available(iOS 26, *)` so the app still builds and runs on iOS 17 with the rule-based coach. CI moves to Xcode 26.3 (verified installed on the runner image) so this code is compiled. |
| On-device model context is small (about 4k tokens) | Design constraint | The coach never puts the whole memory in a prompt. Deterministic code retrieves a few relevant records and the model gets a compact summary. |
| Outlook work calendar | Unknown; the user isn't sure it appears in iOS Calendar | EventKit first. If no work calendar is found, the app says so and offers manual work blocks. Microsoft Graph needs an Azure app registration and tenant consent, and push subscriptions need a public webhook; not planned without employer approval. |
| Calendar change detection | iOS limit | `EKEventStoreChanged` only fires while the app runs. Otherwise the app refreshes on foreground or background refresh, best effort. It never claims real-time monitoring. |
| Free Apple developer team | Constraint | Provisioning profiles expire every 7 days, so the app must be reinstalled from Xcode weekly. **WeatherKit isn't available to free teams**: weather uses Open-Meteo (free, no key; coarse location only, disclosed). Push notifications need a paid account, so all notifications are local. |
| Starling payments | Verified design from the earlier phases | With a personal access token, payments to a payee must be approved in the Starling app. The app never automates that approval. |
| Gym occupancy | No public Nuffield Health API known | Estimates come from user feedback only, labelled as such. No values are ever invented. |
| Background execution | iOS limit | No continuous agent. The app works with observers, `BGAppRefreshTask`, scheduled local notifications and Live Activities within their budgets. |
| Health Records entitlement | Previously rejected for this team | Not used. |

## Permissions and entitlements needed

| Need | Key | Phase |
|---|---|---|
| Calendars (read) | `NSCalendarsFullAccessUsageDescription` (iOS 17 full access) | 1 |
| Speech to text | `NSSpeechRecognitionUsageDescription`, `NSMicrophoneUsageDescription` | 1 |
| Camera (receipts, recipes, progress photos) | `NSCameraUsageDescription` | 4 |
| Location (home/office mode, travel) | `NSLocationWhenInUseUsageDescription`; region monitoring only with consent | 6 |
| Health writes (workouts from the watch) | `NSHealthUpdateUsageDescription` | 3 |
| Live Activities | `NSSupportsLiveActivities` | 3/7 |
| watchOS app | New target, shared app group | 3 |

## Security review

- No secrets are committed. Banking and broker tokens live in the Keychain with `AfterFirstUnlockThisDeviceOnly`.
- The SwiftData store uses iOS's default file protection (complete until first unlock). That's needed because Health background delivery writes while the phone is locked. Progress photos will get complete protection (Phase 3).
- The coach's AI runs on device, so personal context doesn't leave the phone. Weather (Phase 6) will send rounded coordinates to Open-Meteo, and the user will be told.
- Risk: memory and conversation data are as sensitive as health records. Mitigations: an inspector with edit and delete, export, delete-all, and a "sensitive" flag that keeps a record out of notifications and widgets.

## Proposed sequence

See `IMPLEMENTATION_PLAN.md`. Phase 1 starts with the deterministic core (commitments, scoring, availability, calendar classification), then persistence, then the four-tab UI.
