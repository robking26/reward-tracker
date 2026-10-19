# Integrations

Status key:
- **Live**: implemented and used.
- **Built, unverified**: code exists but hasn't been run against the real service or device.
- **Planned**: not yet built.
- **Not possible**: a platform or policy limit.

| Integration | Status | How | Limits and notes |
|---|---|---|---|
| Apple Health (read) | Live | `HealthKitService`: statistics queries, workouts, activity summary, observer queries, hourly background delivery | iOS hides whether read access was granted. No reads while the phone is locked. |
| Apple Health (write workouts) | Built, unverified on device (Phase 3) | `HKWorkoutSession` + `HKLiveWorkoutBuilder` on the watch (strength training) | The iPhone has `NSHealthUpdateUsageDescription` because watch workouts are authorised there. |
| Apple Health (body weight, body fat, swims) | Built, unverified on device (Phase 3) | Sample queries for `bodyMass` and `bodyFatPercentage`; swimming workouts | Read-only. Adding these types triggers a new permission prompt. |
| Apple Watch link | Built, unverified on device (Phase 3) | WatchConnectivity (application context and messages); `startWatchApp` | The iPhone is the logger; the watch mirrors rest and can skip or end. Needs its own App ID on the free team. |
| Calendars (Apple, shared, Outlook if added to iOS) | Built, unverified on device (Phase 1) | EventKit `requestFullAccessToEvents`, read-only. Refreshed on launch, foreground, `EKEventStoreChanged` and background refresh. | **The app never writes to external calendars.** Change detection isn't real time when the app is closed (S4). |
| Outlook via Microsoft Graph | Not planned | — | Needs an Azure AD app registration, tenant admin consent and a public HTTPS webhook for change notifications. Only worth doing if EventKit can't see the work calendar and the employer approves. |
| Apple Foundation Models | Built, unverified on device (Phase 2) | `LanguageModelSession` with tools and `@Generable` structured output, iOS 26+ | On device, free, private. Small context window. Can be unavailable (not enabled, still downloading, low battery), in which case the deterministic coach answers. |
| Speech to text | Built, unverified on device (Phase 1) | `SFSpeechRecognizer` (en-GB) with `requiresOnDeviceRecognition` when supported | Needs microphone and speech permissions. Falls back to typing. |
| Text to speech | Built, unverified on device (Phase 2) | `AVSpeechSynthesizer`, British voice | Never in office mode. |
| Starling | Built against the docs, sandbox-tested earlier | Personal access token in the Keychain; Space transfers; payments to a payee | Payments need approval in the Starling app. Fines are simulated until a review (D-005). |
| Monzo | Payee only | Paid via Starling | No Monzo API is used. |
| Trading 212 | Dormant | — | Switched off (D-005). |
| Weather | Planned (Phase 6) | Open-Meteo forecast API (free, no key) | WeatherKit isn't available to free developer teams. Coordinates are rounded to about 1 km before sending. |
| Travel time | Planned (Phase 6) | MapKit `MKDirections.calculateETA` | Free. Traffic-aware estimates where Apple has them. |
| Location | Planned (Phase 6) | Core Location, when-in-use. Home and office regions only with consent. | |
| Gym occupancy | Not possible as a live source | User feedback ("it was busy") builds time-of-day estimates, always labelled as estimates | No public Nuffield Health API is known. Values are never invented. |
| OCR (receipts, recipes) | Built, unverified on device (Phase 4) | Vision `VNRecognizeTextRequest`, VisionKit document camera, PhotosPicker, PDFKit text layer with page rendering as a fallback | On device; nothing is uploaded. At most 6 PDF pages are read at a time. |
| Nutrition data | Built (Phase 4) | About 70 common foods with typical UK values per 100 g, bundled in the app | Always shown as estimates with a confidence level (D-025). Open Food Facts for packaged items is a possible later addition. |
| Supermarket prices | Not available | Typical Aldi shelf prices bundled for estimates | Aldi and Co-op have no public price API. Prices are labelled as typical, not live. |
| Notifications | Built: scheduled commitment reminders (Phase 2), unverified on device | `UNUserNotificationCenter` calendar triggers for agreed commitments only; normal alerts at home, silent (passive) in the office | Local only (no push on a free team). The iOS limit is 64 pending notifications. |
| Live Activities | Built, unverified on device (Phase 3) | ActivityKit rest timer on the Lock Screen and in the Dynamic Island | Updated locally without a push server; ends with the workout. |
| App Intents | Planned (Phase 7) | "I'm ready", "What's next", "Done" for Siri and Shortcuts | |
