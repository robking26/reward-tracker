# Vaultality

**Healthy habits unlock wealth.**

Vaultality is a native iOS app. Each month a £500 fitness allowance sits in a Starling Savings Space, and activity recorded in Apple Health unlocks it. Money you earn is paid to your Monzo account, and each payment needs your approval in the Starling app. Whatever isn't earned by month-end simply stays in Starling. Nothing is ever taken off you for missing a day: the app only counts what you earn.

The app has four tabs, plus daily routines:

- **Vault:** the **transformation battery** for the year, which starts at 0%: each gym session +0.5%, each swim or run +0.25%, each planned gym session missed in a week −0.5% (against the weekly gym target in Day settings, counted when the week ends), and each day under the Gym tab's step target −0.25% (counted when the day ends). It stays between 0% and 100%, shows this week's change and where the last four weeks' pace leads by the year mark, and opens to a chart and a log of every change. Gym sessions are ones logged in the Gym tab or 20+ minutes of strength in Apple Health. Below it, this month's allowance, today's earnings and your activity cards. Everything about money (payouts, Starling, previous months and reward rates) lives in **Settings → Money & Vault**.
- **Day:** Suggestions can be moved to a time you choose (and put back), and the refresh button re-reads your calendars and works them out again. Up to three pools: the swim goes to the nearest from where you'll be, and straight after the gym when the gym has a pool. **Chores**: write a list (one per line); each gets a time estimate (or write "30 min") and an outdoor flag, indoor jobs are batched into blocks of up to an hour, and outdoor ones like mowing only go in when it's dry and light. Your Apple calendar, your work Outlook calendar and Becky's calendar in one hour-by-hour calendar for the next seven days (overlaps side by side, a red line at now, suggestions dashed, routines as blocks; tap anything for details). Outlook's "Office focus" or "Home focus" event at 9 am sets where the day starts. In Outlook, "Blocked" and "Lunch walk" are busy to work but free for you (a lunch walk is where the day's walk goes), and "Rob King AL" makes it a day off. Everything in your own calendar counts; Becky's events only count once you mark them **Shared**, and each new one asks (once per repeating event). The rest of hers stay faded, just so you know. Into the free time it fits the gym (an hour's workout), a swim (an hour, changing included), the Aldi weekly shop and the Sunday batch cook of next week's lunch, plus runs (only while your knee is settled) and walks when it's dry and light. Each suggestion includes the drive there and back from where you'll be: your current location today, the office after an office day, otherwise home. **Add to calendar** books it in your own calendar; **Directions** opens Google Maps. Set it up under the sliders button: label each calendar (Mine, Becky's, Work) and save home, the office, the gym, the pool and Aldi. Outlook shows up once the work account is added in iOS **Settings → Calendar → Accounts**, and Becky's once she shares her iCloud calendar with you. Drive times come from Apple Maps, because Google's Directions API would need a permanent API key inside the app.
- **Routines and journal (on the Day tab):** a morning routine for today's you and a night routine for tomorrow's you, each with weekday and weekend versions, at home and away, plus a 20-minute walk after lunch and another after tea. Mornings follow Rob's timed lists: on work weekdays a 10-minute run, 15 minutes of knee rehab, shower and teeth, shave and minoxidil, dressed with breakfast, a walk after breakfast, face cream and hair, and the gym kit in the van, with a coffee, journal, wash on and tea prep on home days, or work bag, train station and journal on the train on office days (from Outlook's 9 am focus). The weekday morning starts at 6 and runs as long as its timings add up to; weekend and away mornings are 10 to 11, or the hour before the first calendar event. Each item shows its planned time, and while a routine is open the card shows whether you're ahead or behind; a streak, your best, and the last seven days as dots keep score. A routine is done at 80% ticked; a home morning or night not done in time halves that day's earnings (once, rounded in your favour), and walks never cost anything. Nights away count from 8:30 pm if you're not home. Home days get an 8:45 reminder to sort the washing. The **journal** takes a mood, feelings and free writing, with a 30-day mood trend; journal items in the routines are ticked by writing the entry. Knee rehab is in the morning routine, so gym workouts are lifting only (rehab on its own is still in the Gym tab).
- **Gym:** your own exercise bank split into Push, Pull and Legs days (the Gym suggests the next one in rotation; weights and records carry on from your history), an optional shorter functional session (full body, core-focused, finished with a swim), or knee rehab on its own. Every exercise shows a short form loop (its start and finish positions, from the public-domain [Free Exercise DB](https://github.com/yuhonas/free-exercise-db)) with a link to a full YouTube video, and at least two swaps for when you can't do it (busy, sore or no kit); swaps are knee-checked, so an irritable knee only gets gentler options. Sets, warm-ups, rest timers (with a Live Activity and the Apple Watch app) and knee check-ins are logged on the phone, alongside strength, knee, walking, body and swim trends. Gym sessions earn money the same way as any other workout: through the strength minutes Apple Health records.
- **Kitchen:** an 8-week cycle. Each week has one batch-cooked lunch for Monday to Friday (about 600 kcal) and one five-minute breakfast for every day (about 500 kcal); every meal is 50 g+ protein and low fat, calculated from Aldi products. Each week has its own Aldi list for the lunches and one for the breakfasts, rounded to whole packs. **Share list** sends both as one text list in Aldi walking order (to Messages, WhatsApp, Notes and so on); once you've started ticking, it sends only what's still to get. Evening meals and extras are logged by scanning the barcode (looked up on Open Food Facts) or by hand, and the day's calories and macros add up on the Today screen. **Teas** (Kitchen → Teas): your own recipe bank, from your books. Send Claude photos or PDFs of recipes with the prompt the app copies for you, and it gives back JSON (title, source, servings, macros per portion, prep and cook times, whether it freezes, ingredients and method); paste it or import the file. The bank ships with 102 recipes from the four Fit Food Diary guides (Slow Cooker, Meal Prep V9, Meal Prep Vol 2, Fakeaway). Every recipe is adapted to 600–700 kcal with 50 g+ protein: the book's portion is resized (for example ×1.1), and where the book's version is light on protein a lean top-up suited to the dish is added (more chicken breast, king prawns, cod, 5% beef mince, turkey mince or pork loin, in 10 g steps, with how to cook it). Gram and ml amounts are scaled to match. Prep and cook times are estimated from the method (the books don't print them) and can be corrected in the recipe, as can whether it freezes. Each week (a reminder comes at 9 on Saturday mornings) you say who's eating each night (together, just you, just Becky, or not cooking), then Rob swipes, the phone goes to Becky, and she swipes. Together nights get meals you both liked, solo nights that person's likes; Monday to Thursday only get quick meals (30 minutes or less, prep and cook); the swipe deck has everything. Any night can be swapped. Recipes Claude processes in this chat can also go straight into `FitnessVault/Resources/TeaRecipes.json`. The kitchen never earns or costs money.

**Widgets:** besides **Today** (earnings and rings, with the transformation battery on the 4×2 size), there are two 2×2 Home Screen widgets: **Day** (the next three hours of your calendar, hour by hour, with suggestions and routines) and **Transformation** (the battery, this week's change and days to go). They show what the app last worked out, so open the app now and then to keep them fresh.

> The original web tracker (`index.html`) is still in the repo so the existing site keeps working.

## Requirements

- Xcode 16 or later (the project uses folder-synchronised groups)
- iOS 17 or later on a real iPhone. HealthKit has no real data in the Simulator.
- An Apple Developer team, for the HealthKit capability

## Getting started

1. In Xcode, choose **Integrate → Clone…**, paste `https://github.com/robking26/reward-tracker.git` and pick the `main` branch. To get updates later, use **Integrate → Pull…**.
2. Signing is preset to Rob's personal team (`P9VHAY42J5`) and the bundle identifier `com.robking.FitnessVault`. If you're signing with a different Apple ID, choose your team under **Signing & Capabilities**.
3. Run on your iPhone. On first launch, tap **Allow Access** to connect Apple Health.
4. To try the app without Health data or a bank, open **Settings → Development → Demo mode**. Demo mode uses generated activity and a pretend bank, and it can never move real money.
5. Run the tests with **⌘U**. They cover all the reward, ledger, cap and settlement maths.

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
  Features/        Activity, Vault, Gym, Workout, Progress, Kitchen, Settings
  Preview Content/ Preview-only fixtures (DEBUG only)
FitnessVaultWidget/ Home-screen widget and Live Activities (rest timer, cooking countdown)
FitnessVaultWatch/ Apple Watch companion for gym sessions
Shared/           Code used by both the app and the widget
FitnessVaultTests/ Unit tests (money, training, kitchen)
Config/            Info.plist additions and entitlements
docs/              Architecture and roadmap
.github/workflows/     iOS build and tests
```

## Month-end and gold (Trading 212, switched off)

At month-end, Vaultality calculates `forfeited = max(0, allowance − earned)`. It closes the month on the 2nd, after a fresh Apple Health sync, so late activity still counts. From then on the month is locked. Gold investing is **switched off**, so the unearned amount just stays in the Starling Space and the Trading 212 settings are hidden. The rest of this section describes the dormant gold flow: when it's on, the forfeited amount becomes a **gold allocation** in **Settings → Money & Vault → Gold investment**. It's never added to a future allowance.

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

## Home-screen widget

The widget comes in three sizes:

- **Small (2×2):** earned today, steps and mini rings.
- **Medium (4×2):** earned today and the top three inputs, with the Activity rings alongside.
- **Large (4×4):** earned today, the rings, up to six inputs that earned money (with their measurements) and this month's progress.
- **Lock Screen:** a circle (today's earnings inside a ring of the month's progress), a rectangle (earnings, steps and mini rings) or a single line above the clock. To add one, press and hold the Lock Screen, tap **Customise → Lock Screen**, tap the widget area and choose **Vaultality**.

- **Add it:** on the Home Screen, long-press an empty spot, tap **Edit → Add Widget**, search for **Vaultality**, swipe to the size you want and tap **Add Widget**.
- **How it updates:** the widget can't read Apple Health itself. It shows the numbers the app saved at its last sync, with the time of that sync, and refreshes whenever you open the app.
- **After midnight:** until the app syncs again, the widget asks you to open it rather than showing yesterday's numbers as today's.
- **Activity rings:** these need the Activity summary permission in Apple Health. Open the app and tap **Allow Access** when it asks.

## Automatic checks

Every push that touches the app is built and tested on GitHub's Macs. See the **Actions** tab, which needs no Apple account.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for design decisions, platform limits and what is still to do.
