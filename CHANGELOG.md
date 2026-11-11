# Changelog

Versioning: Major.Minor.Patch — see ROADMAP.md.

## 3.2.0 — Tile layout, planner and table upgrades, bigger widgets
- Today and Hours are grids of square tiles (driving left, working left, rest by, break due, limits…), grouped by meaning. Tap Edit to drag tiles around, hide them with −, or add hidden ones back; each Hours group has its own on/off switches.
- Today's date tile, in the format you choose (long, with week number, short, ISO…).
- Driver card tile: one tap records insert/withdraw and shows a short "Card inserted / Card withdrawn" message that disappears.
- New activities: Yard check (other work); Waiting for shift, Waiting for job and Spare / standby (POA). Voice commands too.
- Planner: start location / depot searched by postcode with an address list; every address can be pinpointed on the map (drag the map under the pin, satellite view). The route on the map starts from the depot.
- Stops: new types (Fuel, Parking / rest, Trailer swap) and custom stops with your own name; ⋯ menu on every stop and custom line to edit, duplicate, move or delete.
- Planner calendar shows each day as a mini bar chart (driving, other work, POA, breaks — height by time), planned days outlined; shifts listed under the calendar (moved from the Driver log).
- Earnings: week number with start and end dates.
- Vehicles is now a plain fleet list (no selection ticks); pick today's vehicle on Today or in a plan.
- Notebook tables: freeze rows/columns, header rows/columns, row/column/cell colours, column widths, insert/move/delete, and drag to rearrange rows and columns.
- Widgets: every widget comes in small, medium, large and extra-large (iPad), plus all three Lock Screen sizes; the Lock Screen widget now shows both countdowns with bars, the next break and the rest deadline.

## 3.1.0 — Reorganised app, driver log, navigation & voice
- New layout: Today · Hours · Driver log · Jobs · Earnings. Each tab has its own ⚙︎ for its settings; Settings (gear on Today) keeps the general ones.
- Driver log: all activity tracking kept separately from planning — Days (chart, activities, events, overspeed), Shifts, Events, and Changes (every edit, addition and deletion is recorded and can't be removed).
- Sub-activities: Loading, Unloading, Vehicle check, Fuelling, Paperwork, Cleaning, Waiting to load/unload, Ferry/train, Double-manned — chips on Today, logged with their own map pins.
- Today is customisable: switch each block on/off and drag to reorder; keep the screen on (always / on shift / never).
- Help and rule explanations moved into ⓘ buttons in the corner of cards.
- Correct a start time by tapping the time on the status card (replaces the "Wrong time?" bar).
- End shift now clears the vehicle/trailer in use and completes the day's job; earnings, route and debrief stay.
- Jobs: planner calendar (plans, holidays, bank holidays only), vehicles, fuel and notes in one tab.
- Stops redesigned: site, address search by postcode/company (Apple Maps), booking time and reference, collection/delivery reference, pallets, weight, contact, notes.
- DVLA registration lookup (with your free DVLA key) fills make, fuel, weight, colour, year, MOT and tax.
- Map: every plan stop (addresses looked up), planned route with distance and time, numbered stop pins.
- Navigation mode: spoken turn-by-turn, rerouting, traffic delay announcements and route notices; warns when your driving time won't reach the destination and offers services/lorry parks within reach.
- Assistant voice: speak questions, hands-free talk mode, and voice commands (start shift, drive, break, loading, waiting, insert card, end shift…).

## 3.0.0 — AI assistant & worldwide rules
- Assistant (✨ on Today): ask about driving left, breaks, rest, next start, 15h/10h days, earnings, weekly rest, infringements or vehicle height — answered offline from your records. Turn on Claude AI with your own Anthropic API key (kept in the iPhone Keychain) for any question; it's sent with a summary of your hours and pay, never your name, locations or notes.
- Country & rules: choose UK, EU/EEA/Switzerland, AETR, USA (FMCSA 11h/14h/30-min/60-70h), Canada south of 60° (13h/14h/16h/70h), Australia (NHVR standard hours) or New Zealand (5½h/13h/70h). Hours, alerts, widgets, the Watch and the event log follow your choice.
- Rules matrix: key limits side by side, and a searchable list of countries and the rules they use.

## 2.1.0 — Driver profile, app lock, backup & Apple Watch redesign
- Driver profile: registration on first launch (name, employer, phone, licence categories, card number) and expiry dates for driving licence, tacho card, Driver CPC and D4 medical, with a warning on Today and reminders before each expires.
- App lock with Face ID (or your iPhone passcode), locking again after a time you choose.
- Backup & restore: everything in one file to save or send, and restore on a new iPhone.
- Apple Watch redesign, sized for Ultra: Now (big Drive/Work rings, rest progress, when you can start), Buttons (large tiles), Coming up (next break, rest deadlines, 10h/15h days left, week totals, earnings) and Card & cab (insert/withdraw card from the watch).
- Fix: reminders could be cleared straight after being scheduled.

## 2.0.0 — Map & location event log
- Map: your route for any day (recorded in in-cab mode), a coloured pin for every event, job stops, and day-by-day browsing. Open it from the map button on Today, a Calendar day, or History.
- Navigate to the next job stop in Apple Maps, Google Maps or Waze, with a reminder of your vehicle height (those apps don't route by lorry size).
- Event log: shift start and end, activity changes, card in/out, arrived/departed, fuel, overspeed (top speed and duration) and infringements, each saved with where it happened. Filter by type and export as CSV.
- Settings → In-cab automatic: choose whether to save your route and event locations (kept only on your iPhone).

## 1.3.0 — Personalisation, notifications & beta prep
- Custom reminders: at a time (once, daily, weekdays, weekly), on a button press (start/end shift, Arrived, card inserted), or a set time before a driving break, working-time break, daily rest or weekly rest. Two starter reminders included (walk-round check, end of shift).
- Spoken alerts: activity changes, warnings before limits, overspeed and reminders, with voice, speed and lead-time settings. Works while the app is open or in-cab mode is running.
- Customisable widgets: HGV Countdown (one number of your choice, Home and Lock Screen) and HGV Dashboard (choose each block, medium and large).
- Report a problem / suggest a feature, and an About page with version and ways to support development.
- Limit alerts no longer wipe other scheduled notifications.

## 1.2.0 — Earnings, vehicles & working records
- Fix: the night-out button added another night out on every tap.
- Salary pay type; guaranteed hours per week and month.
- Earnings screen (week / month / year) with chart and estimates.
- Number-plate scanning, metres and feet, odometer, GPS mileage, fuel & resources log.
- Arrived / Departed for job stops, day debrief, Summary table with CSV export.

## 1.1.0 — Fixes, compliance & core improvements
- Driver card button; correct a start time after pressing too early/late; recovered data hidden by the widget update.
- Driving left respects working-time limits; combined next-break advice; estimated time for every limit; next shift start.
- Overspeed recording (over 60 s = infringement) and the tachograph minute rule.
- Today and Hours reorganised.

## 1.0.0 — First version
- iPhone app: Today, Hours, History, Calendar with planner, Notebook, vehicles, pay, widgets, Live Activity and Apple Watch app.
