# HGV Hours — Roadmap

Status key: ✅ done · 🚧 in progress · ⬜ planned

## V1.1 — Fixes, Compliance & Core Improvements

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

## V1.2 — Earnings, Vehicles & Working Records
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

## V1.3 — Personalisation, Notifications & Beta Release
- ⬜ Multiple and custom reminders
- ⬜ Spoken notifications, customisable by parameter or action
- ⬜ More widget types and customisable widgets
- ⬜ Report-a-problem button
- ⬜ About page: version, support the development

## V2.0 — Smart Navigation & Advanced Event Tracking
- ⬜ Map
- ⬜ Location-based event log: infringements, overspeed and other events with place, date, time and details
- ✅ Card inserted (done in V1.1)

## V2.1 — Accounts & Wearable Integration
- ⬜ Driver account with login and registration
- ⬜ Apple Watch (incl. Ultra) interface redesign

## V3.0 — AI & International Expansion
- ⬜ AI assistant
- ⬜ Rules for all countries, with their own limits matrix
