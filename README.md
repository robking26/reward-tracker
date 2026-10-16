# Fitness Vault

A native iOS app that turns activity recorded in Apple Health into real money. Each month £400 sits in a Starling Savings Space. Activity unlocks it, and the money you earn is paid to your Monzo account. Every payment needs your approval in the Starling app.

**Move more. Earn more.**

> The original web tracker (`index.html`, with points and a rewards shop) is still in the repo so the existing site keeps working. The iOS app replaces it and doesn't use it.

## Requirements

- Xcode 16 or later (the project uses folder-synchronised groups)
- iOS 17 or later on a real iPhone. HealthKit has no real data in the Simulator.
- An Apple Developer team, for the HealthKit capability

## Getting started

1. In Xcode, choose **Integrate → Clone…**, paste `https://github.com/robking26/reward-tracker.git` and pick the `main` branch. To get updates later, use **Integrate → Pull…**.
2. Signing is preset to Rob's personal team (`P9VHAY42J5`) and the bundle identifier `com.robking.FitnessVault`. If you're signing with a different Apple ID, choose your team under **Signing & Capabilities**.
3. Run on your iPhone. On first launch, tap **Allow Access** to connect Apple Health.
4. To try the app without Health data or a bank, open **Settings → Development → Demo mode**. Demo mode uses generated activity and a pretend bank, and it can never move real money.
5. Run the tests with **⌘U**. They cover all the reward, ledger, cap, settlement and meal-limit maths.

## Connecting Starling (sandbox first)

1. In the [Starling developer portal](https://developer.starlingbank.com), create a **sandbox** personal access token with only the scopes this app needs: account, balance, savings goals and savings-goal transfers, payees, and local payments.
2. In the app, open **Settings → Starling**, keep **Sandbox** selected, paste the token and tap **Load Accounts**.
3. Choose your account, the Savings Space that holds the vault, and your existing Monzo payee.
4. Live use needs a separate production token, the **Live** environment, *and* switching on **Allow live transfers**. That toggle is off by default.

Tokens are stored only in the iPhone's Keychain, marked device-only. They are never written to the repo, `UserDefaults` or the app bundle.

## How money moves

| State | Meaning |
|---|---|
| Earned | Activity qualified for a reward. These are integer-pence ledger lines, capped at the month's allocation. |
| Released | Starling confirmed the transfer from the Savings Space to your main balance. |
| Awaiting approval | A payment order to Monzo exists and you need to approve it in the Starling app. |
| Processing | Approved, and Starling is still processing it. |
| Paid | Starling reported the payment as completed. |
| Rejected / Failed | Nothing left Starling. These earnings are included in the next payment. |
| Needs checking | The outcome is unknown. Nothing else is sent until you check it. |

- **Releases** are batched (at least £1) and use Starling's idempotent transfer UID, so retrying is safe.
- **Settlement** runs once a day after the settlement time (08:00 by default). It pays only finished days that were synced after they ended. It makes at most one payment, and never while another payment is unresolved.
- **Unearned money** stays in the Space. Next month the Vault tab shows how much carried forward, and suggests a top-up only for the shortfall.

## Reward rates (defaults)

| Activity | Reward |
|---|---|
| Steps | 1p per 50 steps |
| Swimming | 1p per 5 m |
| Strength training | 1p per 6 seconds (strength workouts only) |
| Exercise minutes | 1p per 10 seconds (Apple Exercise minutes) |
| Active energy | 1p per 10 kcal |
| Flights climbed | 10p per flight |
| Meal photo | 50p each, first 3 distinct meals a day |
| Protein target | £1 |
| Calorie target (range) | 50p |

Rewards are calculated from cumulative daily totals using whole intervals only. Days become final after 7 days, and after that they are never recalculated, even if the rates change.

## Project layout

```
FitnessVault/
  App/             App entry, tab shell, AppModel (orchestration)
  DesignSystem/    Colour, spacing, radius tokens and shared components
  Domain/          Pure, tested logic: Pence, reward engine, ledger, settlement
  Persistence/     SwiftData entities and settings
  Services/        Health (HealthKit + mock), Meals (AI analysis), Banking (Starling + mock), Platform
  Features/        Activity, Nutrition, Vault, Settings
  Preview Content/ Preview-only fixtures (DEBUG only)
FitnessVaultWidget/ Large home-screen widget (WidgetKit)
Shared/           Code used by both the app and the widget
FitnessVaultTests/ Financial unit tests
Config/            Info.plist additions and entitlements
docs/              Architecture and roadmap
server/meal-analysis/  Cloudflare Worker for AI meal analysis
.github/workflows/     iOS build/test and server check/deploy
```

## Home-screen widget

The widget comes in three sizes:

- **Small (2×2):** earned today, steps and mini rings.
- **Medium (4×2):** earned today and the top three inputs, with the Activity rings alongside.
- **Large (4×4):** earned today, the rings, up to six inputs that earned money (with their measurements) and this month's progress.
- **Lock Screen:** a circle (today's earnings inside a ring of the month's progress), a rectangle (earnings, steps and mini rings) or a single line above the clock. To add one, press and hold the Lock Screen, tap **Customise → Lock Screen**, tap the widget area and choose **Fitness Vault**.

- **Add it:** on the Home Screen, long-press an empty spot, tap **Edit → Add Widget**, search for **Fitness Vault**, swipe to the size you want and tap **Add Widget**.
- **How it updates:** the widget can't read Apple Health itself. It shows the numbers the app saved at its last sync, with the time of that sync, and refreshes whenever you open the app.
- **After midnight:** until the app syncs again, the widget asks you to open it rather than showing yesterday's numbers as today's.
- **Activity rings:** these need the Activity summary permission in Apple Health. Open the app and tap **Allow Access** when it asks.

## AI meal analysis

Meal photos are analysed by your own small server. By default it uses Cloudflare's free AI allowance, and Claude is available as a paid option. It's in [`server/meal-analysis`](server/meal-analysis/README.md), along with the deployment steps and costs. Until you deploy it, the app uses a clearly labelled mock analyser.

## Automatic checks

Every push that touches the app is built and tested on GitHub's Macs. See the **Actions** tab, which needs no Apple account. The meal server is type-checked and tested the same way.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for design decisions, platform limits and what is still to do.
