# Vaultality

**Your coach for the next action.**

Vaultality is a native iPhone app that acts as a personal coach. It knows your goals, calendar, routines and Apple Health activity. It takes the work out of deciding what to do, when, and how to start. Version 2.0 is being built in phases; see [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) for what's done.

It has four tabs:

- **Today**: the one thing to do now, with Start, Done, Not now, Change plan, Something's blocking me and Talk to coach. Below it: what's coming up, tonight's dinner, what's still due, and what's at stake. The Dinner card opens the **Kitchen**: this week's meals, the Aldi list, what's probably in, your recipes, and spending against the £400 household ceiling.
- **Coach**: a chat that acts on the same data as Today. Type or dictate. It works offline, with no AI service, and Apple's on-device model arrives in Phase 2.
- **Calendar**: your calendars, read-only, plus your commitments and the free time the coach can see. Work focus blocks are protected, and Becky's shared events never make you busy.
- **Progress**: consistency over the last 14 days (no streaks), money kept this month, house-sale progress, and movement from Apple Health.

**Money:** each month £500 sits in Starling. You keep it minus fines for agreed commitments you miss. The daily fine bands are below, and the monthly cap is £100. Food, weight, illness, injury and rest are never fined. **During the trial no real money moves**: fines are simulated until the rules have been reviewed. Activity earned money until 18 October 2026, and those earlier earnings still pay out as before.

| Day's score | Fine |
|---|---|
| 80% or more | Nothing |
| 60–79% | £5 |
| 40–59% | £10 |
| Below 40% | £15 |

> The original web tracker (`index.html`) is still in the repo so the existing site keeps working.

## Requirements

- Xcode 26 or later. CI builds with Xcode 26.3; Apple's on-device model needs the iOS 26 SDK.
- iOS 17 or later on a real iPhone. HealthKit has no real data in the Simulator.
- An Apple Developer team, for the HealthKit capability

## Getting started

1. In Xcode, choose **Integrate → Clone…**, paste `https://github.com/robking26/reward-tracker.git` and pick the `main` branch. To get updates later, use **Integrate → Pull…**.
2. Signing is preset to Rob's personal team (`P9VHAY42J5`) and the bundle identifier `com.robking.FitnessVault`. If you're signing with a different Apple ID, choose your team under **Signing & Capabilities**.
3. Run on your iPhone. On first launch, tap **Allow Access** to connect Apple Health.
4. To try the app without Health data or a bank, open **Settings → Development → Demo mode**. Demo mode uses generated activity and a pretend bank, and it can never move real money.
5. Run the tests with **⌘U**. They cover commitments, scoring, fines and the cap, availability, calendar classification, the coach's commands, and the earlier reward, ledger and settlement maths.

## Using the coach

1. **Calendars:** open **Settings → Calendars**, allow access, and label each calendar as Work, Personal, Shared with Becky, or Don't use. Unlabelled calendars are ignored. If your Outlook work calendar isn't listed, add the work account under iPhone **Settings → Calendar → Accounts** (if your employer allows it). Otherwise the coach treats 8–4 on weekdays as protected work time.
2. **Routines:** open **Settings → Routines** and switch on the ones you agree to: lunchtime walk, knee rehab, evening self-care, washing up. An agreed routine counts every scheduled day without asking, so only switch on what you mean.
3. **Every morning:** after your own routine, tap **I'm ready** on Today or say it to the coach.
4. **During the day:** use the buttons on Today, or just tell the coach:
   - "What's next?", "Done", "Not now", "In an hour"
   - "Something's blocking me", "My knee hurts", "I'm ill"
   - "Park this" and "I'm back"
   - "Put cleaning the attic on my list"
   - "We've run out of chicken", "We've got three portions of curry left", "Add bin bags to the shopping list"
   - "What's for dinner?", "I forgot to defrost", "There's nothing in for dinner"
5. **The next morning:** anything you didn't mark gets a "Did you do this?" card on Today. If it's still unanswered by the end of that day, it counts as missed. You can correct it until the month closes.
6. **Memory:** open **Settings → Coach memory** to see everything the coach knows about you. You can correct it, mark items as sensitive, delete them or export them. **Settings → Privacy & data** can delete everything.

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

## Reward rates (until 18 October 2026)

| Activity | Reward |
|---|---|
| Steps | Nothing for the first 2,500 steps, then 1p per full 20 steps (2,520 = 1p), up to £10 a day |
| Swimming | 3p per 25 m |
| Strength training | 1p per 12 seconds (strength workouts only) |
| Running | 1p per 20 m (running workouts only) |
| Exercise minutes | 1p per 10 seconds (Apple Exercise minutes) |
| Active energy | 1p per 10 kcal |
| Flights climbed | 5p per flight |

Rewards come from Apple Health activity only; the app has no nutrition or meal logging. They are calculated from cumulative daily totals using whole intervals only. Days become final after 7 days, and after that they are never recalculated, even if the rates change.

## Project layout

```
FitnessVault/
  App/             App entry, tab shell, AppModel (orchestration)
  DesignSystem/    Colour, spacing, radius tokens and shared components
  Domain/          Pure, tested logic: Pence, reward engine, ledger, settlement
  Persistence/     SwiftData entities and settings
  Services/        Health (HealthKit + mock), Banking (Starling + mock), Platform
  Features/        Today, Coach, Calendar, Progress, Workout, Kitchen, Settings
  Preview Content/ Preview-only fixtures (DEBUG only)
FitnessVaultWidget/ Large home-screen widget (WidgetKit)
Shared/           Code used by both the app and the widget
FitnessVaultTests/ Financial unit tests
Config/            Info.plist additions and entitlements
docs/              Architecture and roadmap
.github/workflows/     iOS build and tests
```

## Month-end and gold (Trading 212), switched off

Since Vaultality 2.0, fines stay in Starling and gold investing is switched off. The code is kept; this section describes how it worked.

At month-end, Vaultality calculates `forfeited = max(0, allowance − earned)`. It closes the month on the 2nd, after a fresh Apple Health sync, so late activity still counts. From then on the month is locked, and the forfeited amount becomes a **gold allocation** in **Settings → Money & Vault → Gold investment**. It's never added to a future allowance.

Each allocation moves through separate, explicit steps:

| Status | Meaning |
|---|---|
| Awaiting funding | Set aside; still in the Starling Savings Space |
| Funding processing | Moved out of the Space and sent to Trading 212. A Starling payment needs your approval in the Starling app |
| Cash available | Trading 212 shows the cash. Nothing bought yet |
| Order submitted / Partially filled | Trading 212 accepted the buy order |
| Purchased | Trading 212 reports it filled. Any remainder stays as cash in Trading 212 |
| Needs checking | An order request's outcome is unknown. Nothing else is sent until it's resolved |

**Setting up Trading 212:**

1. In Trading 212, use an Invest or Stocks ISA account and switch to **Practice** for the demo. Create an API key under Settings → API (Beta).
2. In Vaultality, open **Settings → Trading 212**, keep **Demo**, paste the key (and secret, if shown), then tap **Test Connection**.
3. Search for a physically backed gold ETC priced in GBP or GBX, then select and **confirm** it.
4. Optional: save Trading 212's bank details (with your deposit reference) as a payee in Starling, and choose it under **Funding from Starling**. Vaultality then prepares the transfer, and you approve it in Starling.
5. **Buy automatically** is off by default. **Allow live trading** appears only in the Live environment and needs a confirmed instrument.

Trading 212 market orders take a share quantity, not a £ amount. Vaultality keeps back 2% for price movement and fees, rounds down to 0.01 of a share, and never spends more than the allocation or the free cash. If you don't already hold the ETC, enter the current price shown in Trading 212 when buying, because the API has no price quote. The Trading 212 API is in beta, so check the whole flow in demo before going live.

## Widgets

The widgets show what's next, today's commitments and your activity. They never show money or fines.

| Size | Shows |
|---|---|
| Small (2×2) | Next action, commitments done, small rings |
| Medium (4×2) | Next action, rings, then steps, exercise, energy and flights |
| Large (4×4) | Next action, rings, what's still due, activity, and when it last updated |
| Lock Screen | Commitments done (circle), next action and steps (rectangle), or one line |

- On the Lock Screen, sensitive commitments such as knee rehab show as "Next commitment" rather than by name.
- **How it updates:** the widget shows what the app last saved. It refreshes when the app syncs (every minute while the app is open, and when iOS wakes it for new Health data), and iOS asks it to check about every 15 minutes.

## Automatic checks

Every push that touches the app is built and tested on GitHub's Macs. See the **Actions** tab, which needs no Apple account.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for design decisions, platform limits and what is still to do.
