# Integrations

Status key:
- **Live**: implemented and used.
- **Built, unverified**: code exists but hasn't been run against the real service or device.
- **Planned**: not yet built.
- **Not possible**: a platform or policy limit.

| Integration | Status | How | Limits and notes |
|---|---|---|---|
| Apple Health (read) | Live | `HealthKitService`: statistics queries, workouts, activity summary, observer queries, hourly background delivery | iOS hides whether read access was granted. No reads while the phone is locked. |
| Apple Health (write workouts) | Planned (Phase 3) | `HKWorkoutSession` on the watch, mirrored to the phone | Needs `NSHealthUpdateUsageDescription`. |
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
| OCR (receipts, recipes) | Planned (Phase 4) | Vision `RecognizeTextRequest`, VisionKit document camera, PDFKit | On device. |
| Nutrition data | Planned (Phase 4) | UK CoFID (McCance & Widdowson) subset bundled under the Open Government Licence; Open Food Facts for packaged items | Always shown as estimates. |
| Notifications | Built: scheduled commitment reminders (Phase 2), unverified on device | `UNUserNotificationCenter` calendar triggers for agreed commitments only; normal alerts at home, silent (passive) in the office | Local only (no push on a free team). The iOS limit is 64 pending notifications. |
| Live Activities | Planned (Phase 3) | ActivityKit: rest timer, workout, departure countdown | Updated locally without a push server. |
| App Intents | Planned (Phase 7) | "I'm ready", "What's next", "Done" for Siri and Shortcuts | |
