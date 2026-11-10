# HGV Hours — iPhone app for UK HGV drivers' hours and working time

A native SwiftUI app (iOS 17+) that tracks driving, other work, POA and rest the way your tachograph mode switch does. It shows live countdowns and warnings against UK rules, and keeps history, weekly totals, pay estimates and exportable timesheets.

> **Planning aid only.** The tachograph and your employer's records are the legal record.

## What it covers

| Rules | What's checked |
|---|---|
| **Assimilated rules (retained EU 561/2006) and AETR** | 4h30 driving then a 45 min break (or 15 + 30). 9h daily driving, 10h twice a week. 56h weekly and 90h fortnightly. Daily rest of 11h, or 9h reduced (max 3 between weekly rests), or split 3h + 9h, all within 24h. Double-manned: 9h within 30h. Weekly rest of 45h, or 24h reduced, started within 6×24h; two reduced in a row only with the international option. Compensation tracking. |
| **Road Transport (Working Time) Regulations 2005** | No more than 6h of work without a break. 30 min of breaks for 6–9h, 45 min for 9h+, taken in pieces of 15 min or more. 60h maximum in a week. 48h average over a rolling 17 or 26 weeks. 10h limit on night shifts (00:00–04:00), which you can raise if you have an agreement. POA and breaks are excluded from working time. |
| **GB domestic** | 10h driving and 11h duty per working day. Choose these rules as your main rules or for individual activities (mixed days). |

## Features

- **Today:** live pay counter, **Start shift**, Drive / Other work / POA / Break, and **End shift** (choose daily or weekly rest). Every button shows a help message: how long a break must be, when to finish, what's next. The status card always shows the next deadline. Current vehicle (with a height sign) and today's planned job are shown too. Settings is the gear at the top left.
- **In cab (automatic):** like the tachograph's motion sensor. Driving starts when GPS shows the vehicle moving above the set speed for 8 seconds (confirmed by the motion chip at low speed); stopping for the set delay records Other work from the moment it stopped. Carrying or shaking the phone does nothing. Off = walking/manual.
- **Hours:** driving left, working left, rest-by time, shift length against 13h/15h, 10h driving days left (2 a week), 15h days left (3 reduced 9h rests between weekly rests), and every limit.
- **History:** shifts by week; ⋯ menus and swipes to edit or delete activities or whole shifts.
- **Calendar:** month view with daily bars, holidays, bank holidays and **planned work**. Plan a day with times, company, vehicle, trailer, start location, stops (collection/delivery with time, reference, pallets), load, references and custom lines. Plans are checked against rest rules (9h/11h before and after, 13h/15h length, reduced rests left, weekly rest due).
- **Notebook:** notes and editable tables, pinning, search, sharing, and templates (including ready-made fuel log, delivery sheet and defect check).
- **Vehicles & trailers:** saved with registration, make/model, height, width, length, weight, axles, fuel (diesel, AdBlue, HVO, LNG/CNG gas, electric…) and body type; select, edit or delete.
- **Pay:** hourly or day rate; Saturday, Sunday, bank holiday and overtime as normal, ×1.25, ×1.5, ×2, a custom multiplier or a custom £ rate; holiday pay **included in the rate** (UK 12.07%) or **paid separately** (holiday days at the 52-week average day's pay, worked out automatically); regular and one-off bonuses; night premium and night-out allowance.
- **Widgets:** Home Screen (small, medium) and Lock Screen (circular, rectangular, inline) with driving/working time left, rest-by time and earnings.
- **Apple Watch:** status and countdowns, activity buttons, start/end shift, in-cab switch.
- **Lock Screen Live Activity, alerts before limits, and PDF/CSV export.**
- All data is stored on the device. There is no account, no tracking, and no network access.

## Build and run on your iPhone

You need a Mac with **Xcode 16 or newer** (the project uses Xcode 16 folder-synced groups) and an iPhone on iOS 17+.

1. Open `HGVTime.xcodeproj`.
2. Select the **HGVTime** project → **Signing & Capabilities**. For both the **HGVTime** and **HGVTimeWidgetExtension** targets, choose your Team.
3. Change the bundle identifiers from `com.example.hgvhours` / `com.example.hgvhours.widget` to your own, for example `uk.co.yourname.hgvhours` and the same with `.widget`. The widget's ID must start with the app's ID.
4. Plug in your iPhone. Turn on **Settings → Privacy & Security → Developer Mode** on the phone, then pick the phone as the run destination and press ▶︎.
5. The first time, trust the developer on the phone: **Settings → General → VPN & Device Management**.

With a free Apple ID the app has to be re-installed from Xcode every 7 days. A paid Apple Developer Program membership (£79/yr) removes that limit and lets you publish.

Run the unit tests with ⌘U. They cover breaks, split breaks, extensions, rest deadlines, double manning, working-time breaks, night work, GB domestic rules and pay.

## Publishing to the App Store later

- Join the Apple Developer Program, create the app in App Store Connect with your bundle ID, then use **Product → Archive** → Distribute.
- Already included: an app icon (1024px), a privacy manifest (`PrivacyInfo.xcprivacy`, no data collected), `ITSAppUsesNonExemptEncryption = NO`, and a first-launch disclaimer.
- For the App Privacy questionnaire, answer **Data Not Collected**.
- Before submitting, consider adding a short privacy policy URL, screenshots, and reviewing the wording of the disclaimer with your own adviser.

## Project layout

```
HGVTime/               App target
  App/                 Entry point and tab layout
  Models/              SwiftData models (ActivityEntry, NightOut) and settings
  Rules/               Pure-Swift rules engine, limits, pay calculator, formatting
  Services/            Activity switching, notifications, Live Activity, export
  Views/               SwiftUI screens
Shared/                Code used by both the app and the widget (DutyKind, Live Activity attributes)
HGVTimeWidget/         Live Activity (Lock Screen and Dynamic Island)
HGVTimeWatch/          Apple Watch app (talks to the iPhone over WatchConnectivity)
HGVTimeTests/          Unit tests for the rules engine and pay
```

All the legal limits live in `Rules/Limits.swift`. If the law changes, update them there.

## Known limits (not modelled yet)

- Ferry and train interruptions of daily rest, and the 2-hour "return home" extension.
- Fixed RT(WT)R reference periods (the app uses a rolling average). Holiday days are paid but not yet counted as 8h of working time.
- Scottish and Northern Irish bank holidays (England & Wales dates are used).
- The 4-weekly "return home" requirement for international drivers.
- Exemptions and derogations (e.g. 100 km radius, specialised vehicles).
- Tachograph card download or import. The app relies on you tapping the modes.
