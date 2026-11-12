# Changelog

Versioning: Major.Minor.Patch — see ROADMAP.md.

## 3.15.0 — Smoother navigation, lorry pin, clearer panel
- The map glides with the lorry: position and heading are eased 5 times a second and the camera follows the smoothed position, so turns and movement are smooth instead of jumpy.
- The map always follows you: if you pan around, it goes back to following after 6 seconds; it re-centres when you reopen navigation or come back to the app. No more looking for the pin.
- Pin position: the pin sits higher, clear of the bottom panel — and you can set exactly where (Settings → Navigation → Lorry pin).
- New lorry pin: an artic seen from above whose trailer swings out on bends and straightens behind you, tilted in 3D with the map. Also rigid, van, navigation arrow and dot styles; size, colour, 3D and animation on/off.
- Speed limit: a white circle with a red ring on the speedometer corner you choose (top/bottom, left/right). When the road's limit isn't known it shows your vehicle's limit, faded.
- Bottom panel redesigned: Arrive, Time left and Distance in big type, the destination, and large Hide / End buttons.
- Main map (from Today) opens on today's journey: start, all stops, finish and your activities — no events (change it with the filter).
- 1 new test (104 in total).

## 3.14.0 — Trailer/vehicle stops, height check
- New stop types: Pick up trailer, Drop off trailer, Pick up vehicle, Drop off vehicle — add, edit, move, swap or delete them like any stop. Choose the trailer or vehicle from your list (or type its number). Tapping Departed at a pick-up makes it your current trailer/vehicle; at a drop-off it's taken off.
- Today: "Vehicle height checked" tile, like the driver card — shows your height (vehicle or trailer, whichever is taller); one tap records the check with the time (logged as an event). It resets each shift and when you change vehicle or trailer.
- 2 new tests (103 in total).

## 3.13.2 — Map filters per map, with sensible defaults
- Activities and events are back on every map, controlled by the filter. Each map remembers its own choice and starts from a default that fits where you opened it:
  - Main map (Today) and the general day map: activities and events off.
  - Map from the driver log's Events section (and the event log): events on, activities off.
  - Map from the driver log's Activities section: activity changes on, events off.
- New Map buttons next to the Activities and Events headings in the driver log day.
- Filter buttons: All on, All off and Default for the whole map, plus All on / All off for events.
- 1 new test (102 in total).

## 3.13.1 — Info (ⓘ) texts checked
- Every ⓘ explanation now matches the tile it's on. Driving left explains the 4h30 period (and that it doesn't drop to zero on a break); Working left the 6-hour working-time period (any 15-minute break resets it).
- New explanations for Driven today, Worked today, Shift working time, Shift time left, Next shift can start, Break due in and Resting for.
- Separate texts for GB driving (10 h) and GB duty (11 h); clearer weekly rest and compensation wording.
- Fixed: for other countries' rules, "On duty (14h)" showed the UK GB-domestic text. Their limits now explain themselves.
- All ⓘ texts are translated into Polish, Romanian, Russian and Ukrainian.
- 3 new tests (101 in total).

## 3.13.0 — Map filters
- Every map has a filter (the ☰ button on the day/main map, "Show on map" in the navigation view menu). Choices are remembered.
- Driver log day map: route driven, planned route, job start and stops, "problems only", and each event type on its own — shift start/end, activity changes, card in/out, arrived/departed, fuel, overspeed, infringements, harsh braking, notes, record changes — with how many there are that day, plus All / None. The filter icon fills in when something is hidden.
- Main map: route driven, planned route, job start and stops.
- Navigation: speed cameras, traffic lights, your road reports and parking suggestions (also in Settings → Navigation).

## 3.12.1 — Edit, reorder, swap and delete stops
- Today's job: each stop's ⋯ menu now has Edit stop, Move up, Move down, Swap with… (pick any other stop) and Delete stop, as well as cancelled / failed / rejected.
- Job editor: Swap with… on every stop, and a Reorder button that shows drag handles so you can drag stops into a new order (or delete them).

## 3.12.0 — Languages, smoother map, safety warning
- Settings → Language: English, Polski, Română, Русский, Українська, or follow the iPhone. About 1,150 screens, buttons, settings and messages are translated; some help texts and calculated hints are still in English. The language can also be changed in iPhone Settings → Apps → HGV Hours → Language.
- Map no longer lags or freezes: the main map loads only the day shown (not every GPS point ever recorded) and no longer redraws on every camera movement; the navigation route line is built once; the lorry marker updates 5 times a second instead of 10; at most 40 nearby traffic lights are drawn.
- Events are no longer shown on the main map — only activities, your route, jobs and stops. Events (and problems) are on the driver log's day map.
- Navigation: the see-through turn arrow sits lower, on the right just above the bottom bar.
- Safety: a "Use only when parked" notice (UK law — Highway Code rule 149) in the welcome screen, a reminder when you open navigation, a red "Driving — don't use the phone" bar on Today while the lorry is moving (in-cab mode), and navigation settings, directions list and road reports are blocked while moving.
- Fixed: the "Now" pill on the status card was empty.

## 3.11.0 — Adjustable navigation view, clearer widgets, CarPlay screens
- Navigation: choose the view (3D behind, heading up, north up, overview), the 3D tilt (flat to behind the cab) and zoom (very close to very far) from the view button, or set them exactly in Settings → Navigation. Your choice is remembered.
- Widgets redesigned so every number says what it is: "Driving till break" (4h30) and "Working till break" (6h) as rings, plus driving left today, next break (length and time), start rest by, worked this shift, week driving/working, 10h days and 9h rests left, and earnings. Countdowns tick live while you drive. New "Driving left today" option for the custom widgets. The large size is the third option in the widget gallery.
- CarPlay screens (Hours, Activity buttons, Route): your hours, Drive / Other work / POA / Break / End shift buttons, and the next turn while navigating. They work in Xcode's CarPlay Simulator now; to appear in your car, Apple has to approve the app for CarPlay (needs a paid developer account).
- Fixed: the "Now" button next to the time on the status card showed as an empty grey pill.
- All calculations use your activities in the driver log (drive, other work, POA, breaks); events are only a record.

## 3.10.1 — GPS position fixes
- Fixed: after a reroute the lorry marker could jump to a random point further along the new route (it used your progress along the old route).
- Rough positions are ignored: when GPS is weak (yards, buildings, tunnels) the iPhone falls back to Wi-Fi / mobile-mast positions that can be hundreds of metres or kilometres out. Fixes worse than 65 m are skipped while a good fix is recent, and impossible jumps (faster than 200 km/h) are dropped — on the navigation screen, the main map and the lorry marker.
- The route position no longer snaps to the opposite carriageway or to a later part of the route that passes close by (e.g. coming back along the same road).
- Arrived / Departed and event locations only reuse a recent fix if it's a proper GPS one.
- 1 new test (98 in total).

## 3.10.0 — Lorry routing, lane guidance, new navigation screen
- Fixed: a 15 min break didn't reset the 6h working-time clock. Under the working-time rules any break of 15 min or more interrupts the 6h run; the daily total (30 min for 6–9h, 45 min over 9h) is still checked separately. Driving still needs the 30 min after a 15.
- Lorry routing: routes are now built for your vehicle (height, width, length, weight, axles, speed limiter) with the free OpenStreetMap Valhalla service — avoiding low bridges, weight and width limits and lorry bans, preferring motorways and A-roads (optional: avoid tolls). Apple Maps is used if it can't be reached (marked "not checked for lorries"). Live traffic delays still come from Apple Maps.
- Lane guidance: lane arrows for the next junction from 2 km out, the lanes you need highlighted.
- Correct turn arrows from the route data (incl. roundabout exit number), and spoken prompts at the right distances; each said once.
- Navigation screen: bigger speedometer with the speed limit sign on its corner (the lower of the road and your vehicle's limit, no caption); the road you're on always shown, with space under the speedometer; big see-through turn arrow on the right; arrival time, time left, distance and traffic delay; smooth lorry marker that glides along the road.
- Speed cameras and traffic lights from OpenStreetMap on the map, with a spoken "Speed camera ahead". Report accidents, closures, roadworks, police/DVSA, hazards, jams, low bridges and check sites with the ⚠︎ button — kept on your iPhone and you're warned when you come back that way.
- Navigation keeps going when you leave the screen, switch app or lock the phone: directions are still spoken, and the next turn, distance, road and arrival show on the Lock Screen. Reopen it from the green banner on the map or the Today tiles.
- Today tiles while navigating (choose them in Customise Today): mini map, next turn, road, speed limit, arrival time, voice on/off.
- Settings → Navigation: routing, motorways, tolls, voice (all prompts or turns only), camera warnings, speedometer size and side, banner size, lanes, big arrow and its transparency, map style, traffic lights, reports.
- The main map (from Today) shows activities and events but not problems; problems stay on the driver log day map.
- 6 new tests (97 in total).

## 3.9.0 — Shift checks, reports by company/vehicle, loaded/empty, alarm snooze
- Today's two circles now show the current period, as on a tacho: Driving left = what's left of the 4h30 before a break (or less if the daily/weekly limit is nearer); Working left = what's left of the 6h before a working-time break. They're independent (driving is no longer capped by the 6h clock), don't drop to 0 during a break, and refill when the break counts. Daily, weekly and fortnight totals stay on the Hours page.
- Shift checks: your own start- and end-of-shift checks — agency forms, licence checks, card and tacho downloads, signing the register — every shift, on chosen days, weekly, every 2 weeks or monthly, optionally only for one company, with a link to open (e.g. an online form). Tick them off on Today; ending a shift lists any end checks not done. Settings → Shift checks.
- Loaded / Empty switch on the vehicle card: records loaded and empty distance per shift (shown on the card and in reports).
- Reports (Summary): group by day, company, vehicle, trailer, start place, weekday or month, and filter by company and vehicle — days, hours, distance (loaded/empty), fuel, nights out, pay, average pay per day and infringements. CSV export follows the view.
- Assistant screen now matches the rest of the app (light/dark system look, app colours and cards).
- Alarms: snooze button (5–30 min, set in Wake-up & leave home) with a snooze countdown on the Lock Screen; the leave-home reminder can ring as a real alarm.
- Quiet during daily & weekly rest (Settings → Notifications): no limit alerts, repeating reminders or spoken alerts while you rest; breaks on shift and your alarms still work.
- 3 new tests (91 in total).

## 3.8.0 — Hours fixes, navigation voice fixes, stop outcomes
- Fixed: "Driving left" showed 0 during a break. It now shows the driving you have left today (9h/10h, weekly and GB limits); when the next break is due is shown underneath and on the "Break due" tile.
- Fixed: "Driving left" and "Working left" were often identical, because both were capped by the 6h working-time clock. "Working left" now means working time left in the shift (until your daily rest must start, the 60h week, night and GB duty limits), with the 6h break shown underneath.
- Fixed: pressing Drive during a break said it was "an infringement". Stopping a break early is allowed — it just doesn't reset the 4h30. The message now says so, and a break of 15 min or more counts as the first part of a split break.
- Break guidance: when you press Break you see both options with clock times — full 45 min (done at …) or split (15 min part done at …, then 30 min later). After a 15, further short breaks don't reset; the next 30 min does.
- Fixed navigation voice: instructions were repeated after every 3-minute traffic check and reroute, and could play late (a queued "turn left" heard when the next turn was right). Prompts are now said once per junction, a new one cuts off an old one, and your position is tracked along the road for correct turn timing. Earlier warnings on fast roads.
- Fixed turn arrows picking the wrong side from road names (e.g. "Turn right onto Leftwich Road").
- Mute button for navigation directions; the same spoken alert is no longer repeated within 90 s anywhere in the app.
- Navigation tracks your position far more efficiently (no longer scans the whole route on every GPS update).
- Jobs: end location — same as start, somewhere else, or not known yet (for trunking/tramping).
- Stops: mark a single stop cancelled, failed or rejected (with a reason) from ⋯ on Today's job; shown in the plan and debrief. Cancelling the whole job moved into the job editor.
- Newest first in the driver log, events, calendar day, vehicles and overspeed lists; the driver log day shows one combined events list instead of two.
- Settings → Units: miles or km, feet or metres, or both.
- "Now" button next to start, end and other time pickers.
- 5 new tests (88 in total).

## 3.7.0 — Reset & erase, new assistant look
- Settings → Reset & erase replaces the old "Erase all activity data" button. Quick choices: factory reset (erase everything and go back to all defaults, as if newly installed), reset all settings but keep your records, or erase all records but keep your settings.
- Or choose exactly what to do. Records to erase: driver log, jobs and debriefs, earnings extras and nights out, vehicles/mileage/fuel, notes, reminders, event log/speed/routes, assistant keys and AI models (each shows how many items it holds). Settings to reset: driver profile and home, pay, country and hours rules, alerts/voice/alarm, in-cab and navigation, layout and units, assistant, app lock, everything else.
- You type ERASE to confirm, with a "Make a backup first" link. Alarms and notifications are cleared and set again from what's left.
- New assistant look: a dark, moving aurora background; a glowing AI orb that pulses while listening and spins while thinking (tap it to speak); a personal greeting; suggestion cards; glass chat bubbles; a floating input bar where the mic turns into a send button when you type.
- 5 new tests (83 in total).

## 3.6.0 — Wake-up alarm, leave-home reminder, calculator
- Fixed: the app crashed when you turned on talk mode or tapped the microphone in the assistant. It tried to listen while it was still speaking. It now waits for the answer to finish, checks the microphone is ready, and shows a message instead of crashing.
- Wake-up alarm for your next planned job. On iOS 26 it's a real alarm that rings on silent and shows full screen; on older iOS it's a notification with sound. Wake-up time = leave time − time to get ready. You can add a second alarm a few minutes later, rename the alarm, test it, and set a one-off alarm for days with no job planned.
- "Time to leave" notification, plus an optional heads-up before it. The drive from your home address to the job's start place (or first stop) is worked out by Apple Maps with traffic, or uses a journey time you set. You choose how early you want to arrive.
- Everything is adjustable in Settings → Wake-up & leave home. For each job you can set the wake-up or leave time yourself, or turn both off. Tap the ⏰ / 🚗 strip on Today to change them.
- Calculator (± / % button on Today): a normal calculator, km ↔ miles, and feet ↔ metres (type heights like 16'6; shows feet and inches).
- 5 new tests (78 in total).

## 3.5.0 — On-device AI agent
- The assistant can run entirely on your iPhone: Qwen 3.5 2B (Alibaba, Apache-2.0) with Apple's MLX on the phone's GPU. Free, private, works offline once downloaded (about 1.3 GB, once, from Hugging Face). Lighter Qwen 3 1.7B and 0.6B models are also offered.
- It uses the same app tools as before: plan, change, cancel or delete jobs, add stops, notes, reminders, fuel, activities, vehicle and trailer — and asks before deleting anything or ending a shift. Photos are read on the phone.
- Turn it on in Assistant → ⚙︎ → On-device AI → Download / load model. Claude stays available as an option.
- Tested with the real model: it creates jobs with the right date, time and stops from a plain request, and checks your hours with get_status.

## 3.4.0 — Earnings kept, truck navigation, harsh braking, AI agent tools
- Fixed: ending a shift no longer clears "Earned today" or the mileage card. They stay until midnight and start again at zero the next day (a night shift counts on the day it finishes).
- Resting between shifts: the big timer counts down to your next planned job (within 24 h), warns if you won't have 9 h rest by then, and is hidden when nothing is planned.
- Today's job: "Job cancelled" button (optional reason), with Restore. Cancelled jobs stay in your records with a CANCELLED badge.
- Change the trailer mid-shift as well as the vehicle: each part of the shift records which trailer was on, shown in the vehicle card and mileage.
- Driver log, shift details, weeks and reminders list the newest first.
- Navigation: a small lorry marker that points the way you're heading (also on the main map); routes prefer motorways and A-roads; big road-number signs (blue motorway, green primary); the road's speed limit as a round sign (OpenStreetMap, lower lorry limit shown when it applies); arrival times allow for your speed limiter.
- Vehicles: speed limiter setting (default 90 km/h / 56 mph for lorries over 3.5 t).
- Harsh braking detection in in-cab mode (adjustable sensitivity), saved in the event log with time and place, and counted on Today.
- Assistant is now an agent: it can plan, change, cancel or delete jobs, add stops, read and write notes, set reminders, log fuel, switch activity, vehicle or trailer, and mark the card — asking you first before deleting anything or ending a shift. 📷 reads the text in a photo (delivery notes, booking sheets) on the phone and turns it into jobs or notes.
- 7 new tests (73 in total).

## 3.3.0 — Vehicles in the shift, 3D navigation, deeper rule checks
- Today: choose, change, edit or add your vehicle and trailer at any time. Changing vehicle mid-shift keeps each vehicle's mileage separately.
- Mileage per vehicle: start reading from the vehicle, end reading worked out from GPS (in-cab mode) and editable; goes into the day debrief and the summary table (with the number of vehicles used).
- Vehicles: set the drivers' hours rules per vehicle — tacho, GB domestic, or exempt (no drivers' hours rules; time still counts as working time) — and an overspeed threshold. Choosing the vehicle applies its rules.
- Overspeed threshold automatic from the vehicle type and country (UK/EU lorries 90 km/h, vans road limit, Australia 100, North America 105), or set your own.
- Sub-activities (loading, unloading, waiting, yard check…) are now separate activities with their own start and end time, editable like any other activity.
- Addresses: business name, house number, house/building name and flat for stops and the job start. New stop type: Vehicle service.
- Number boxes start empty instead of 0.
- Today's job no longer lists the stops twice.
- Navigation: 3D view from behind the lorry that turns with you (like Apple Maps), heading-up, north-up and route-overview modes, re-centre, speedometer, turn arrows and a full list of directions.
- Rules fixes found by new scenario tests: a rest after the last work no longer counts as a working-day break; with two drivers, 45 min as co-driver counts as the driving break; a missing weekly rest is flagged even when no earlier weekly rest is recorded.
- 23 new whole-day and whole-week scenario tests across UK/EU, GB domestic, exempt vehicles, USA, Canada, Australia and New Zealand (66 tests in total).

## 3.2.2 — Freeze both ways, keeps working when closed
- Tables: freeze any number of rows and columns at the same time — frozen rows stay at the top, frozen columns (and row numbers) stay on the left.
- In-cab mode keeps working after you close the app: with location set to "Always", iOS relaunches HGV Hours in the background when the lorry moves and recording carries on. Everything is saved when the app goes to the background, and alerts, widgets and the Live Activity stay up to date.

## 3.2.1 — Table fixes
- Tables scroll sideways properly again (left and right), including with a frozen header row.
- Freeze either rows (stay at the top while you scroll down) or columns (stay on the left while you scroll sideways) — one direction at a time.
- Table notes are back, always shown under the table.

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
