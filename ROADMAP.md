# HGV Hours — Roadmap

Versioning: **Major.Minor.Patch**. 1.x = the app and its regular updates; 2.0 = big, harder features (map, accounts, advanced event tracking); 3.0 = the biggest (AI, worldwide rules). Patch numbers are small fixes.

Status key: ✅ done · 🚧 in progress · ⬜ planned

## V1.1 (1.1.0) — Fixes, Compliance & Core Improvements

### Driving hours, breaks and regulations
- ✅ Correct the start time after pressing a button too early or too late ("Wrong time?" bar: −5 / −1 / +1 min or set an exact time)
- ✅ Split break (15 + 30), split daily rest (3h + 9h), reduced weekly rest (24h), compensation and consecutive reduced weekly rests — checked in the rules engine and now shown on the Hours tab
- ✅ Combined break advice: one "next break" that satisfies both the 4h30 driving rule and the 6h working-time rule, with how long it must be
- ✅ "Driving left" now also respects working-time limits (driving is working time)
- ✅ Estimated clock time for every limit: driving break, working-time break, daily/weekly driving, 60h week, night work, daily rest, weekly rest
- ✅ Next shift start time available
- ✅ Driver card inserted / withdrawn button with green / red indicator

### Speed monitoring and infringements
- ✅ Overspeed events recorded in in-cab mode (time, duration, top speed, location) and shown in the day and shift records
- ✅ Over 60 s continuous = infringement; shorter overspeeds recorded but not counted as infringements
- ✅ Tachograph minute rule: each minute gets the activity that filled most of it; short movements during a break don't interrupt it

### Interface
- ✅ Today reorganised: card → status → help → buttons → in-cab → earnings → job & vehicle
- ✅ Hours reorganised: Right now · Next break · Coming up · Extensions & rest rules · All limits
- 🚧 Further polish of the remaining pages (History row layout fixed; Calendar, Notebook, Settings to review)

## V1.2 (1.2.0) — Earnings, Vehicles & Working Records
### Earnings and salary
- ✅ Fix: night-out button added a night out on every tap (now toggles, and duplicates are cleaned up)
- ✅ Guaranteed hours per shift, week and calendar month
- ✅ Salary pay type: per year, month, week or day, with contracted hours and overtime
- ✅ Earnings screen: week / month / year with chart and breakdown
- ✅ Estimated total for the current week / month / year (planned shifts or recent history)
### Vehicles and resources
- ✅ Scan a number plate with the camera (or type it) to select or add a vehicle — DVLA online lookup still to do (needs an API key)
- ✅ Vehicle dimensions in metres and feet/inches (enter in either)
- ✅ Odometer per vehicle, start/end mileage per day, GPS distance in in-cab mode; km or miles
- ✅ Fuel & resources log (diesel, petrol, AdBlue, gas, electricity, tacho rolls, oil) with monthly totals
### Journey and activity records
- ✅ Arrived / Departed per stop (time + location), unplanned stops, and a day Debrief table you can share
- ✅ Summary table: every day's times, activities, distance, fuel, pay and infringements, with CSV export

## V1.3 (1.3.0) — Personalisation, Notifications & Beta Release
- ✅ Multiple custom reminders: at a time (once/daily/weekdays/weekly), on a button press (start/end shift, Arrived, card inserted) or before a break/rest is due
- ✅ Spoken alerts: activity changes, warnings before limits, overspeed and reminders; choose voice, speed and lead time
- ✅ New widgets: HGV Countdown (one number you choose) and HGV Dashboard (choose each block; medium and large)
- ✅ Report a problem / suggest a feature (GitHub or share privately), with optional anonymous app details
- ✅ About page: version, privacy, rules links, support the development (star, share, ideas; donate link when set up)

## V2.0 (2.0.0) — Smart Navigation & Advanced Event Tracking
- ✅ Map: route driven (in-cab mode), event pins, job stops, day-by-day; navigate to the next stop in Apple Maps, Google Maps or Waze with a vehicle-height reminder
- ✅ Event log with location: shift start/end, activity changes, card in/out, arrived/departed, fuel, overspeed (speed + duration) and infringements; filter and CSV export
- ✅ Card inserted (done in V1.1)
- ⬜ Lorry-specific routing (height/weight restrictions) — needs a paid truck-routing service

## V2.1 (2.1.0) — Accounts & Wearable Integration
- ✅ Driver profile (registration on first launch) with licence, tacho card, CPC and medical expiry dates and reminders; Face ID / passcode app lock; backup & restore to a file
- ⬜ Cloud accounts and sync (Sign in with Apple + iCloud) — needs the paid Apple Developer Program
- ✅ Apple Watch redesign (sized for Ultra): Now (big rings, rest progress), Buttons (large tiles), Coming up (next break, rest deadlines, days left), Card & cab

## V3.6 (3.6.0) — Wake-up alarm, leave home, calculator
- ✅ Assistant talk-mode crash fixed
- ✅ Wake-up alarm (AlarmKit) and leave-home reminder with traffic, all adjustable, per-job overrides
- ✅ Calculator with km ↔ mi and ft ↔ m converters

## V3.4 (3.4.0) — Earnings kept, truck navigation, harsh braking, AI agent
- ✅ Earnings and mileage stay until midnight after the shift ends; rest timer counts down to the next planned job
- ✅ Cancel a job; change trailer mid-shift; newest records first
- ✅ Lorry marker with heading, motorway-first routes, road-number signs, road speed limits (OpenStreetMap), speed limiter
- ✅ Harsh braking detection
- ✅ Assistant agent with app tools and photo reading
- ✅ On-device model (Qwen 3.5 with Apple MLX) — released in 3.5.0

## V3.3 (3.3.0) — Vehicles in the shift & 3D navigation
- ✅ Vehicle selection and change on Today; per-vehicle mileage in reports; rules and overspeed per vehicle and country
- ✅ Sub-activities with their own times; detailed addresses; vehicle service stops
- ✅ 3D follow-behind navigation with view modes
- ✅ Scenario test suite across all supported countries
- ⬜ Truck-specific road speed limits per road (needs a paid map data service)

## V3.2 (3.2.0) — Tile layout, planner & tables, bigger widgets
- ✅ Today and Hours as switchable, draggable tile grids grouped by meaning; date tile; card toast
- ✅ New activities: yard check, waiting for shift/job, spare
- ✅ Postcode lookup for the job start, map pinpointing for every address, custom stops, edit/delete for stops and lines
- ✅ Planner calendar mini charts and shifts under the calendar; week numbers in Earnings; fleet list
- ✅ Spreadsheet-style tables (freeze, headers, colours, rearrange)
- ✅ All widget sizes and a more detailed Lock Screen widget

## V3.1 (3.1.0) — Reorganisation, driver log, navigation & voice
- ✅ Tabs: Today · Hours · Driver log · Jobs · Earnings, with per-tab settings
- ✅ Driver log with change records; sub-activities (loading, unloading, waiting…) with map pins
- ✅ Customisable Today, keep screen on, ⓘ info buttons, tap-to-edit start time, end-of-shift reset
- ✅ Redesigned stops, postcode/address search, DVLA registration lookup
- ✅ Map with plan stops and planned route; in-app voice navigation with traffic delays and parking suggestions
- ✅ Assistant voice mode and voice commands
- ⬜ Live road-incident feed (closures, accidents) — needs a paid traffic data service
- ⬜ Verified HGV parking database and truck-legal routing — needs a paid truck service
- ⬜ Royal Mail address list per postcode — needs a paid postcode service

## V3.0 (3.0.0) — AI & International Expansion
- ✅ Assistant: offline answers from your records (driving left, breaks, rest, next start, 15h/10h days, earnings, weekly rest, height); optional Claude AI for any question with your own Anthropic API key (stored in the Keychain)
- ✅ Country & rules: UK, EU/EEA/Switzerland, AETR, USA (FMCSA), Canada (south of 60°), Australia (NHVR standard hours), New Zealand — live limits, alerts and infringements; rules matrix and country list
- ⬜ More countries (e.g. Canada north of 60°, Australian BFM/AFM, India, South Africa, Brazil…) and US/Canada sleeper-berth splits

### Beta testing note
Public beta testing through TestFlight needs a paid Apple Developer Program membership (£79/year). Until then the app is installed from Xcode with a free Apple ID (re-install every 7 days).
