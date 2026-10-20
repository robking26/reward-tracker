# Accessibility review (Phase 7)

These were checked against the code. Items marked *device* need checking on an iPhone with the setting on.

| Area | Status |
|---|---|
| **Dynamic Type** | All text uses text styles, except the widget's fixed-size countdown (Live Activities cap text size anyway). The in-app rest timer is now `.largeTitle`, capped at accessibility size 2 so it fits. *Device:* check the largest sizes on Today and the workout screen. |
| **VoiceOver** | Icon-only buttons have labels: settings, options menus, favourites. Cards combine their children into one element. Activity rings, the week widget, the consistency strip and day rows read as sentences. Shopping list rows say "in the trolley" or "to buy". |
| **Reduce Motion** | Card presses dim instead of scaling. The animations on Today, Progress, money figures and progress bars are turned off. |
| **Touch targets** | Action buttons, menus and list rows are at least 44 points tall. |
| **Colour and contrast** | The dark theme uses light text on near-black. Warnings use amber, never aggressive red (design bar §31). Nothing relies on colour alone: states are also written as words, such as "Missed", "Done" or "check first". |
| **Haptics** | Only for meaningful moments: something done, a suggestion answered, a set logged, rest over, a list item ticked. iOS turns them off when system haptics are off. |
| **Discretion** | Lock Screen widgets hide sensitive commitment names. No widget shows money, fines or body measurements. |
| **Offline** | Coaching, kitchen, accountability and intents all work without a network. Weather and travel say when they're unavailable and never guess. |

Still to check on device: Voice Control labels on the workout logger, and VoiceOver order on the Kitchen screens.
