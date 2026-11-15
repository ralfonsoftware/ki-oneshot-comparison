---
title: Energy Tracker for iOS & iPadOS — Product Requirements
created: 2026-11-07
updated: 2026-11-07
status: draft
owner: Ralf Ehlert
---

# Energy Tracker for iOS & iPadOS — Product Requirements

This document is self-contained. It specifies everything needed to design, build and test the app without access to any other document or code base.

## 0. Purpose and scope

Energy Tracker is a personal electricity tracker for a person who has no smart main meter. The person reads the meter by hand every day or two. The app turns these irregular readings into one calm, glanceable signal: is this year's consumption on track? It also answers whether the current electricity tariff is still competitive.

An earlier version of the product existed as a self-hosted web application (server, database, identity provider, multi-member households). This app replaces it completely. The only link to the old product is a one-time data import from its JSON export file. The file format is fully specified in §8.

This document defines:

- product principles and decisions (§1–§3),
- the domain model and all calculations with worked examples (§4–§5),
- functional requirements (§6),
- the sync and conflict model (§7),
- the import/export file format (§8),
- UX, visual identity and voice (§9),
- distribution, non-functional requirements, non-goals, metrics and open questions (§10–§15).

## 1. Vision and product principles

**Thesis.** A household without a smart meter should know, in seconds, whether its electricity use is on track and whether its tariff is still worth keeping. It should get this from honest, irregular manual readings, without precision theater.

**Principles.** Every requirement in this document follows these rules.

1. **The Main Meter reading is the only truth for total consumption.** Nothing is ever summed or reconciled against it. There is no "residual" or room-by-room attribution anywhere.
2. **Say less, on purpose.** The Status on the home screen is the product. Detail views may exist, but trusting the Status must never require opening them. More time in the app is a regression, not a success.
3. **Honest about uncertainty.** Gaps are shown as gaps, never interpolated. Old data is flagged as low confidence. Ties resolve to the calmer state.
4. **Calm tone.** No alarms, no gamification, no streaks. Red is reserved for real errors.
5. **Never lose or silently rewrite data.** Corrections keep the original value visible. Settings changes affect the future only; stored history is never recomputed.
6. **Private by construction.** Data lives on the user's Apple devices and in the user's private iCloud database. No server, no account, no telemetry.

## 2. Target user

**Sam**, one person, power user. Sam rents a flat with a mechanical or simple electronic main meter. Sam reads the meter every 1–2 days, usually on an iPhone while standing at the meter, often with no mobile signal. Sam reviews trends and tariffs on an iPad. All of Sam's Apple devices use the same Apple Account. Sam has several years of history in the old web app and imports it once.

Not a target: people who share one data set between several Apple Accounts.

## 3. Decisions

| # | Topic | Decision |
|---|---|---|
| D1 | Relation to the old web app | Standalone replacement. No server, no ongoing sync with the web app. History moves over once through the JSON export file (§8). |
| D2 | Platforms | iPhone and iPad, iOS/iPadOS 26 or later. SwiftUI, SwiftData, CloudKit private database. No macOS, watchOS or visionOS target in v1. |
| D3 | Identity | No login. The Apple Account signed in on the Apple device is the only identity. |
| D4 | Users | Single user. No members, invites, roles or sharing. |
| D5 | Storage and sync | Local store on each Apple device, synced through the user's CloudKit private database. |
| D6 | Conflicts | Readings and corrections are append-only. Settings, tariffs, events and structure items use last-write-wins. Exact duplicate readings are merged automatically. |
| D7 | AI | No AI features in v1. Event context uses a deterministic deviation calculation only (§5.6). |
| D8 | Smart Plug data | Smart Plug import is deferred. Smart Plug readings inside an imported file are stored, kept and exported again, but not shown. |
| D9 | Visual direction | Native iOS controls, Liquid Glass, Dynamic Type and SF Symbols, plus the Energy Tracker teal accent and Status color triad (§9.3). |
| D10 | Native extras in v1 | Local notifications, Home Screen and Lock Screen widgets, App Intents (Siri, Shortcuts, Action button, Spotlight). |
| D11 | Distribution | Personal builds and TestFlight first. App Store later, so v1 must already meet App Store rules (§10). |

## 4. Glossary and domain model

### 4.1 Glossary

- **Apple device** — an iPhone or iPad. Always written in full, so it is never confused with **Device** (below).
- **Data set** — all of the user's records for this app, stored in one Apple Account's private CloudKit database and mirrored on each Apple device signed in to that account.
- **Household** — the single settings record of a data set (Yearly Baseline, threshold, currency and similar). Exactly one per data set.
- **Main Meter** — the physical electricity meter. Its readings are the sole source of truth for total consumption. The model allows more than one Main Meter, but v1 UI and calculations use exactly one.
- **Meter Reading** — a cumulative kWh value read off the Main Meter, plus the instant it was read. Several readings per day are valid if their timestamps differ.
- **Yearly Baseline** — the user's target annual consumption in kWh. Set by the user, never derived from readings.
- **Trending threshold** — how far above the Yearly Baseline the user tolerates per year, in kWh (default 100). The Status uses it scaled to the elapsed period (§5.3).
- **Low-confidence gap** — number of days without a new reading after which the Status is flagged low confidence (default 45).
- **Pace-to-date** — kWh actually consumed over the analysis window (§5.2).
- **Baseline-to-date** — Yearly Baseline prorated to the same elapsed period.
- **Status** — one of *within range*, *below baseline*, *trending*, or undefined (§5.3).
- **Status Snapshot** — a stored record of a computed Status at one point in time. Trend History is built from snapshots.
- **Gap** — a period with no reading. The pace calculation absorbs gaps; Trend History shows long gaps as visible breaks.
- **Regression** — a reading lower than its chronological predecessor. The user classifies it as a **reset** (meter replaced or reset to zero) or a **rollover** (mechanical digits wrapped, e.g. 99 999 → 00 000).
- **Digit capacity** — the value at which a rolling-over meter wraps, e.g. 100 000 kWh.
- **Tariff** — an electricity contract entry: monthly base fee, price per kWh, currency, contract start date, Contract Period. Flat rate only.
- **Contract Period** — the minimum contract term in months.
- **Candidate tariff** — a tariff the user is considering. Scratch input; never stored in the tariff history.
- **Switching bonus** — a one-time bonus a supplier offers for switching.
- **Bonus-Decay Normalization** — the shared formula that prorates an annual figure to an elapsed period and decays a one-time bonus linearly to zero over one year (§5.4).
- **Tariff Check** — a reminder to compare tariffs, which becomes due 3 months before the current tariff's minimum term ends.
- **Event** — a short note about something that affects consumption and that no meter sees, e.g. "away 2 weeks" or "sauna 3h". It may be tagged to a Room, Power Point or Device.
- **Observed deviation** — whether consumption in the ±7 days around an Event was clearly above (Bump), clearly below (Dip), or near (none) the baseline pace (§5.6).
- **Room → Power Point → Device** — a three-level tree for labeling Events. A Power Point is a socket. A Device is an appliance. The tree is a label system, never an attribution system.
- **Audit Correction** — an append-only record of a changed value: entity, field, old value, new value, time.
- **Data set generation** — an id that changes each time the whole data set is replaced by an import (§7.5).

### 4.2 Entities

All entities have `id` (UUID) and `createdAt` (instant) unless noted. Every entity also has `generation` (UUID, §7.5). Decimal means exact decimal (§11, Exactness).

| Entity | Fields |
|---|---|
| Household | `locale` (string, kept for file compatibility only), `currency` (ISO 4217, e.g. "EUR"), `yearlyBaselineKwh` (decimal, optional), `trendingThresholdKwh` (decimal, default 100), `lowConfidenceGapDays` (int, default 45), `tariffCheckCadenceMonths` (int, default 3), `tariffCheckDoneAt` (instant, optional), `generation` |
| MainMeter | `digitCapacityKwh` (decimal, optional) |
| MeterReading | `mainMeterId`, `kwhValue` (decimal, original value, never changed), `readingTimestamp` (instant) |
| MeterRegressionPrompt | `mainMeterId`, `meterReadingId` (the lower reading), `previousMeterReadingId`, `resolvedAt` (optional), `classification` (`reset` / `rollover` / none), `digitCapacityKwh` (decimal, rollover only) |
| Tariff | `monthlyBaseFee` (decimal, 2 places), `pricePerKwh` (decimal, 4 places), `currency`, `contractStartDate` (calendar date), `contractPeriodMonths` (int) |
| Event | `description` (string, 1–500 chars), `occurredAt` (instant), `taggedEntityType` (`Room` / `PowerPoint` / `Device` / none), `taggedEntityId` (optional), `taggedEntityName` (optional, copied at tag time), `updatedAt` |
| Room | `name`, `archivedAt` (optional) |
| PowerPoint | `roomId`, `name`, `archivedAt` |
| Device | `powerPointId`, `name`, `archivedAt` |
| StatusSnapshot | `status`, `paceToDateKwh`, `baselineToDateKwh`, `isLowConfidence`, `computedAt`, `causeId` (id of the record change that triggered it) |
| AuditCorrection | `entityType` (`MeterReading` / `Tariff`), `entityId`, `fieldName`, `oldValue`, `newValue` (invariant-culture strings), `correctedAt` |
| SmartPlugReading | `powerPointId` (optional), `roomName`, `powerPointName`, `deviceName` (≤ 200 chars), `intervalStart`, `intervalEnd`, `kwhValue`. Stored from import only (D8). |

The **effective value** of a Meter Reading is the `newValue` of its newest `KwhValue` Audit Correction (newest `correctedAt`, ties by highest id), or its original `kwhValue` if it has none. All calculations use effective values.

## 5. Calculations

All calculations live in a pure Swift package with no UI, persistence or sync code (§11, Testability). The worked examples in this section are mandatory unit tests.

### 5.1 Conventions

- A year is always **365 days**, also in leap years.
- Elapsed time is exact: `elapsedDays = seconds / 86 400`, fractional.
- Readings are ordered by `readingTimestamp`, then by `id` (ascending, byte order of the UUID string in lowercase).
- Ties always resolve to the calmer outcome.
- Money results are rounded only for display and for the worth-switching decision (§5.5). Intermediate values are not rounded.

### 5.2 Pace-to-date

Input: the Main Meter's readings (effective values), the open regression prompt (if any), and resolved prompts.

1. Order the readings (§5.1).
2. **Open-prompt exclusion.** If a regression prompt is open, drop its triggering reading and every reading ordered at or after it.
3. **Window.** Keep readings with `readingTimestamp ≥ latest.readingTimestamp − 365 days`. If fewer than 2 remain, pace is **undefined**.
4. **Pairwise walk.** For each consecutive pair (previous, current):
   - If `current` triggered a resolved prompt classified **rollover**: add `(digitCapacity − previous) + current` kWh and the pair's elapsed time.
   - If classified **reset**: add nothing (neither kWh nor time).
   - Otherwise: add `current − previous` kWh and the pair's elapsed time.
5. If total elapsed time ≤ 0, pace is **undefined**.
6. Result: `paceToDateKwh` and `elapsed`.

**Low confidence:** `daysSinceLastReading = now − (latest included reading).readingTimestamp`. Low confidence when `daysSinceLastReading > lowConfidenceGapDays`.

### 5.3 Status

Undefined when pace is undefined or `yearlyBaselineKwh` is not set. Otherwise:

- `baselineToDate = yearlyBaseline × elapsedDays / 365`
- `thresholdToDate = max( min(annualThreshold, 1), annualThreshold × elapsedDays / 365 )`
  (The 1 kWh floor stops rounding noise from deciding the Status over a day or two. It never exceeds the annual figure, so a threshold of 0 still means "any overshoot".)
- `difference = paceToDate − baselineToDate`
- **trending** if `difference > thresholdToDate`
- **below baseline** if `difference < 0`
- otherwise **within range**

There is deliberately no threshold band for *below baseline*: it is good news, so it may show early.

### 5.4 Bonus-Decay Normalization

One shared function, used by the Status (bonus = 0) and the tariff comparison:

```
normalizeToDate(annualRate, bonus, elapsed) =
    annualRate × (elapsedDays / 365) + bonus × max(0, 1 − elapsedDays / 365)
```

`elapsed` must not be negative. Baseline-to-date and the prorated threshold both use this function with `bonus = 0`.

### 5.5 Tariff comparison

Requires a current tariff (§6, FR-12) and a defined pace.

- `annualPace = paceToDate × 365 / elapsedDays`
- `currentAnnualCost = current.monthlyBaseFee × 12 + current.pricePerKwh × annualPace`
- `candidateCostNoBonus = cand.monthlyBaseFee × 12 + cand.pricePerKwh × annualPace`
- **Bonus-normalized:** `candidateNormalized = normalizeToDate(candidateCostNoBonus, bonus, 365 days)`; `normalizedSavings = currentAnnualCost − candidateNormalized`
- **Bonus-included:** `candidateIncluded = candidateCostNoBonus − bonus`; `includedSavings = currentAnnualCost − candidateIncluded`
- Each signal is **worth switching** only if its savings, rounded to 2 decimals (half away from zero), is **> 0**. Exactly 0.00 means "not worth switching".
- The comparison carries the pace's low-confidence flag.

### 5.6 Observed deviation around an Event

Window: readings with `readingTimestamp` in `[occurredAt − 7 days, occurredAt + 7 days]`.

1. Order the window's readings. Apply the open-prompt exclusion (drop the prompt's triggering reading and everything ordered at or after it, even when the trigger is outside the window).
2. Fewer than 2 readings → **none**.
3. Pairwise walk exactly as §5.2 step 4 → `actual`, `elapsed`. Elapsed ≤ 0 → **none**.
4. Yearly Baseline not set → **none**.
5. `expected = normalizeToDate(yearlyBaseline, 0, elapsed)`; `threshold = thresholdToDate` as in §5.3 for this elapsed.
6. **Bump** if `actual − expected > threshold`; **Dip** if `actual − expected < −threshold`; otherwise **none**.

### 5.7 Tariff Check due date

- `minimumTermEnd = contractStartDate + contractPeriodMonths` (calendar months).
- `gateOpens = minimumTermEnd − 3 months`.
- No current tariff → no Tariff Check ever.
- **Due** when `today ≥ gateOpens` and (`tariffCheckDoneAt` is empty or `today ≥ tariffCheckDoneAt + cadenceMonths`).
- `tariffCheckDoneAt` is ignored if it is earlier than `gateOpens` (so a new tariff starts a fresh cycle).
- The Contract Period is a minimum term, not an end date. The gate stays open after the term ends, whether the contract ends or rolls on.

### 5.8 Worked examples (mandatory test cases)

Readings use 00:00 UTC timestamps. Yearly Baseline 3000 kWh, threshold 100 kWh unless stated.

| # | Input | Expected |
|---|---|---|
| E1 | 1 Jan = 10 000; 31 Jan = 10 300 | elapsed 30 d, pace 300, baseline 246.5753…, thresholdToDate 8.2191…, difference 53.42 → **trending** |
| E2 | 1 Jan = 10 000; 31 Jan = 10 245 | difference −1.5753… → **below baseline** |
| E3 | 1 Jan 2025 = 0; 1 Jan 2026 = 3 100 (365 d) | difference 100 = thresholdToDate 100 → **within range** (tie) |
| E4 | 1 Jan = 10 000; 2 Jan = 10 010 | thresholdToDate = max(1, 0.2739…) = 1; baseline 8.2191…; difference 1.78 → **trending** |
| E5 | Threshold 0; 1 Jan = 10 000; 2 Jan = 10 009 | thresholdToDate = max(min(0,1), 0) = 0; difference 0.7808… → **trending** |
| E6 | 1 Jan = 99 950; 11 Jan = 30, resolved rollover, capacity 100 000 | pair adds 80 kWh, 10 d |
| E7 | 1 Jan = 5 000; 11 Jan = 100, resolved reset; 21 Jan = 200 | first pair adds nothing; total 100 kWh over 10 d |
| E8 | 1 Jan = 5 000; 11 Jan = 100, prompt open; 21 Jan = 200 | only the 1 Jan reading remains → pace **undefined** |
| E9 | Only one reading | **undefined** |
| E10 | Two readings with the same timestamp | elapsed 0 → **undefined** |
| E11 | Readings 400 d and 10 d before latest, plus latest | the 400-day reading is outside the window and ignored |
| E12 | Latest reading 46 d ago, gap setting 45 | **low confidence** |
| T1 | Annual pace 3 000. Current 10.00/month, 0.3000/kWh. Candidate 12.00/month, 0.2800/kWh, bonus 100 | current 1 020.00; candidate no-bonus 984.00; normalized savings 36.00 → worth; included savings 136.00 → worth |
| T2 | As T1, candidate 12.00/month and 0.2880/kWh, bonus 0 | candidate 1 008.00… → savings 12.00 → worth. Candidate price 0.2920 → candidate 1 020.00, savings 0.00 → **not worth** |
| V1 | Baseline 3 650; Event 8 Jan; readings 1 Jan = 1 000, 15 Jan = 1 150 | elapsed 14 d, expected 140, threshold 3.8356…, actual 150, difference 10 → **Bump** |
| V2 | As V1, 15 Jan = 1 130 | difference −10 → **Dip** |
| V3 | As V1, 15 Jan = 1 142 | difference 2 < 3.84 → **none** |
| R1 | Tariff starts 2026-01-01, 12 months, cadence 3, never checked | gate opens 2026-10-01; due from 2026-10-01 |
| R2 | R1, check done 2026-10-05 | next due 2027-01-05 |

## 6. Functional requirements

Each requirement lists testable consequences.

### 6.1 Access and data home

#### FR-1: No-login launch

Opening the app shows the Today screen, or onboarding for an empty data set. There is no login, account creation, password or sign-out.

- No screen asks for credentials, an email address or a server URL.
- The app works fully when the Apple device is signed out of iCloud or iCloud is disabled for the app. Data is then local only.
- When iCloud is unavailable, Settings shows a quiet line with the reason ("iCloud sync off — data stays on this iPad. Reason: not signed in to iCloud."). Today shows nothing about it.
- When iCloud becomes available later, local data uploads without any user step.

#### FR-2: iCloud account change

- Data from one Apple Account never appears in, or uploads to, another Apple Account's data set.
- After an account change, the app shows the new account's data set, or onboarding if it is empty.
- Export (FR-19) is always available, so the user can save data before signing out.

#### FR-3: First launch and onboarding

- With iCloud available, first launch shows "Looking for your data in iCloud…" until the first CloudKit import finishes, at most 15 seconds. If data arrives, the app opens on Today with no onboarding.
- An empty data set offers **Start fresh** or **Import from export file** (FR-20).
- Start fresh asks for the Yearly Baseline and the currency. Household-size presets are suggestions only, never pre-selected: 1 person ≈ 1 500 kWh, 2 ≈ 2 500, 3 ≈ 3 500, 4 ≈ 4 250. Currency is suggested from the device region. Both steps can be skipped and set later.
- If the user starts fresh before sync finished and data arrives later, the duplicate merge (§7.4) combines both without losing records.

### 6.2 Meter readings and Status

#### FR-4: Log a reading

A sheet over the current screen: date and time pre-set to now (editable for backfill), one kWh field with a decimal keypad and "kWh" inside the field, one Save button.

- Save-to-confirmation takes under a minute on the default path, with no network.
- Saving is local and immediate. No pending-sync state is shown.
- Several readings per day are accepted if timestamps differ. A reading earlier than the latest one (backfill) is accepted.
- kWh must be > 0 and < 10^15, at most 2 decimal places.
- Saving a reading with the same timestamp and the same value as an existing reading creates nothing and confirms "Already saved" (exact-duplicate rule, §7.4).
- After saving: regression check (FR-11), Status Snapshot (FR-9), widget reload (FR-22).
- The confirmation shows the new Status in one line, e.g. "Saved · Within range".

#### FR-5: Pattern settings

Settings holds Yearly Baseline (kWh/year), trending threshold (kWh/year, default 100, ≥ 0), low-confidence gap (days, default 45, 1–365).

- Changes apply going forward. Stored snapshots are never recomputed.
- Clearing the Yearly Baseline makes the Status undefined.

#### FR-6: Pace and Status computation

Pace, low confidence and Status follow §5.2–§5.3 exactly.

- Status is computed live whenever a screen, widget or intent needs it, and never on a timer.
- Undefined is never shown as one of the three states.

#### FR-7: Today screen

- The Status card is the primary element and is visible without scrolling at default text size on the smallest supported iPhone.
- The card shows the state label in its Status color, one plain sentence with the actual number ("42 kWh under baseline pace so far"), and a low-confidence note when flagged ("Last reading 52 days ago — status is less certain").
- Undefined shows "Log your first reading to get started" (fewer than 2 readings) or "Set your yearly target to see your status" (no baseline), never blank space.
- Below the card, attention cards appear only when needed, in this order: open regression decision (FR-11), held-back records after a restore (§7.5), duplicate tariff start date (FR-12), Tariff Check due (FR-14).
- Primary action: Log reading. Secondary action: Log event.

#### FR-8: Calculation detail

Tapping the Status card opens a detail view with: pace-to-date, baseline-to-date with the period it covers (dates and days), the difference, the threshold per year and as scaled to the period, and — when flagged — the low-confidence reason (days since last reading vs. setting).

- Text only, no chart.
- Not offered when the Status is undefined.

#### FR-9: Status Snapshots and Trend History

A Status Snapshot is stored when **this** Apple device creates a reading, corrects a reading, or resolves a regression prompt, and the Status is defined.

- Changes received through sync never create snapshots. Only the Apple device that made the change writes one.
- `causeId` is the id of the reading, correction or prompt that caused it. Snapshots with the same `causeId` are merged (§7.4).
- Trend History charts `paceToDate − baselineToDate` (or pace and baseline as two lines) over `computedAt`, with point color by Status.
- When two consecutive snapshots are more than `lowConfidenceGapDays` apart, the line breaks and a labeled band shows the gap: "No reading between 3 Apr and 17 Apr". Gaps are never interpolated.
- Ranges: 1 month, 3 months, 1 year, all.
- Snapshots are never rewritten by settings changes or corrections.

#### FR-10: Reading history and correction

A list of readings, newest timestamp first, showing effective value and time.

- Correcting a reading appends an Audit Correction (`MeterReading`, `KwhValue`, old effective value, new value). The original record never changes.
- A corrected row shows a note: "Corrected from 12 345.6 kWh on 4 Nov 2026". The detail view lists all corrections.
- A correction to the current effective value writes nothing.
- A reading under an open regression prompt shows "Needs a decision".
- Readings cannot be deleted. Correction is the only edit.
- After a correction: regression check, snapshot, widget reload. Events within ±7 days show the new deviation automatically (computed live).

#### FR-11: Regression classification

A reading lower than its chronological predecessor (by effective value) creates a regression prompt.

- The predecessor is found by timestamp order, not entry order. A backfilled reading is compared with its chronological neighbor.
- The prompt replaces the Log Reading sheet (sheets never stack). It asks: "This reading is lower than the one before (12 400 → 120 kWh). What happened?" with **Meter was replaced or reset** and **Meter rolled over (digits wrapped)**.
- Rollover asks for the digit capacity, pre-filled from the Main Meter when known, and stores it on the Main Meter.
- An unresolved prompt excludes its reading and everything after it from the pace (§5.2). It never expires or defaults.
- Only one prompt is open at a time: the one whose reading is earliest. Others queue and open in order.
- Closing the prompt without a choice keeps it open. Today shows "1 reading needs a decision" until resolved.
- A resolved classification can be changed from the reading's detail view. The change re-runs the calculations and writes a snapshot.
- A reading logged through Siri or Shortcuts that triggers a regression is saved, and the intent answers "Saved. This reading is lower than the previous one — open Energy Tracker to classify it."

### 6.3 Tariffs

#### FR-12: Tariff history

The user adds and edits tariff entries.

- **Current tariff:** the entry with the latest contract start date that is not in the future (ties: newest `createdAt`, then highest id).
- Each entry applies until the next entry's start date. History is kept, never overwritten by a new entry.
- Validation: base fee ≥ 0 and < 10^15; price per kWh > 0 and < 10^13; currency a 3-letter upper-case code; Contract Period 1–1 200 months; start date between 1900-01-01 and 2200-01-01.
- Currency is required per tariff and defaults to the Household currency.
- Two entries may not share a start date. The app blocks it on entry. If sync produces it anyway, Today shows "Two tariffs start on 1 Jan 2026 — keep one", and the user picks which to keep; the other is deleted after confirmation.
- Once the start date has passed, changing base fee, price per kWh or start date needs an explicit confirmation: "This contract already started. Change its prices anyway?"
- Every changed field appends an Audit Correction (`Tariff`, field name, old, new). The detail view shows these as correction notes.
- Tariffs can be deleted with confirmation. Deleting keeps its Audit Corrections.

#### FR-13: Compare a candidate tariff

The user enters candidate base fee, price per kWh and optional switching bonus. The app shows the result of §5.5.

- Both signals show side by side, always together, never as a toggle: "With bonus: saves 136.00 € / year — worth switching" and "Without bonus effect: saves 36.00 € / year — worth switching".
- Each signal is a clear yes/no with a symbol and a label, not color alone. Worth switching uses the below-baseline green; not worth switching uses a neutral gray, never red.
- Candidate input never changes the tariff history. The last candidate is remembered on the Apple device only, not synced.
- No current tariff: "Add your current tariff to compare." Undefined pace: "Log at least two readings to compare tariffs." Never a zero result.
- Low-confidence pace shows a note under the result.

#### FR-14: Tariff Check

- Due logic follows §5.7.
- When due, Today shows "Time to check your tariff — your minimum term ends on 1 Jan 2027" with **Compare** and **Done**.
- **Done** sets `tariffCheckDoneAt` = today.
- Not due: the Tariffs screen shows "Tariff check — nothing due until 1 Oct 2026". Never a made-up recommendation.
- Cadence (default 3 months, 1–24) is editable in Settings.
- Editing the current tariff's start date or Contract Period recomputes the due date.

### 6.4 Events

#### FR-15: Log an event

A sheet with one text field, date/time (default now, editable), optional tag picker, Save.

- Same effort as logging a reading.
- The 5 most recent distinct descriptions appear as one-tap suggestions.
- The tag stores type, id and the name at tagging time. Renaming, moving or archiving the item later never changes the Event's tag text.
- Events can be edited and deleted (with confirmation).

#### FR-16: Observed deviation

Each Event shows the result of §5.6.

- Bump: "Usage was above baseline pace in the two weeks around this event." Dip: "… below baseline pace …". None: no line at all, never an error or "no match".
- Wording never claims cause.
- Computed live when shown.
- No AI, model, or network call is involved.

#### FR-17: Event list

The History screen has an Events list, newest first, with description, date, tag and deviation.

### 6.5 Rooms, Power Points, Devices

#### FR-18: Structure management

Settings holds the Room → Power Point → Device tree, used for Event tags.

- Add, rename, move to another parent, archive at each level.
- Archive is a soft delete. Archived items are hidden from the tag picker and shown in the tree only with "Show archived" on. Archived items can be restored.
- An archived parent cannot get new children.
- Names: 1–200 characters after trimming.
- No screen ever sums or attributes consumption by this tree.

### 6.6 Export and import

#### FR-19: Export

Settings → Export creates one JSON file in the format of §8 and opens the share sheet / Files save dialog.

- File name: `energy-tracker-export-YYYY-MM-DD.json`.
- The file contains every entity of the data set, including archived structure items and stored Smart Plug readings.
- `meterReadings[].kwhValue` is the effective value; corrections are in `auditCorrections`.
- `householdMembers` is an empty array; `aiPlausibilityEnabled` and `aiPlausibilityBackendConfigured` are `false`; `aiPlausibilityBackendLabel` is `null`.
- Exporting then importing gives an identical data set (round trip), apart from merged exact duplicates.

#### FR-20: Import (restore)

Onboarding and Settings → Import accept a file from Files or the share sheet.

- The whole file is validated (§8.4) before anything is written. Any failure rejects the file and lists the failures (first 200, then "… and N more"). Nothing is partly applied.
- Fields the app does not use are accepted and ignored.
- A summary shows counts per entity type before confirming.
- Into an empty data set: one confirmation.
- Into a non-empty data set: an explicit **Replace all data** step that states, in plain words, "This deletes all current data on all your devices signed in to this Apple Account and replaces it with the file", shows the counts to be deleted, and offers **Export current data first**. There is no merge mode.
- Replace-all starts a new data set generation (§7.5).
- Ids in the file are kept. Exact duplicate readings in the file are merged (§7.4) and the result names how many.
- Status Snapshots from the file are kept as history. The import itself writes no new snapshot.
- 10 years of data (≈ 3 700 readings, 100 events, 30 tariffs, 1 000 snapshots) imports in under 30 s on the oldest supported iPhone, with progress shown.
- A file with Smart Plug readings is accepted up to 250 MB. Smart Plug readings are stored but not shown.

### 6.7 System integration

#### FR-21: Notifications

- Permission is requested only when the user turns on a reminder, never at launch.
- **Tariff Check notification:** one local notification at 10:00 local time on the next due date (§5.7). Tapping it opens Tariffs.
- Schedules are rebuilt at launch and after every local or synced change to tariffs or the Household.
- A per-Apple-device toggle "Tariff reminders on this iPhone/iPad" avoids the same reminder on every Apple device. Default off; Settings explains why it is per Apple device.
- No other notifications in v1. Status changes are never pushed.

#### FR-22: Widgets

- **Status widget** (small, medium): Status label and color, one short sentence, days since last reading, low-confidence mark. Undefined shows "Log a reading".
- **Lock Screen widgets** (circular, rectangular, inline): Status symbol and label.
- The medium widget has a **Log reading** button that opens the app on the Log Reading sheet.
- Widgets compute the Status with the same calculation package and the shared store (§11, Shared store).
- The app reloads widget timelines after every local write and after every sync import it processes.
- Timelines also refresh at least daily so "days since last reading" stays true.

#### FR-23: App Intents

- **Log Meter Reading** (parameter: kWh). Runs without opening the app, saves with timestamp now, answers with the value and new Status. Assignable to the Action button and Control Center.
- **Get Energy Status**: answers in one sentence, e.g. "Within range — 42 kWh under baseline pace."
- **Log Event** (parameter: text).
- Intents use the same validation, duplicate and regression rules as the app.
- App Shortcuts phrases in English and German for all three.

### 6.8 Preferences

#### FR-24: Currency

The Household currency is a synced setting, set at onboarding and editable. Money shows in the tariff's currency, formatted for the app's language and region.

#### FR-25: Language and formats

- English and German at launch, via a String Catalog. A new language is a catalog addition, not a code change.
- Language follows the iOS per-app language setting. There is no in-app language switch.
- Numbers, dates and currency follow the active language and region. Copy and formats never mix languages.
- Stored data is locale-neutral. The Household `locale` field is kept for file compatibility only and does not drive the UI.

#### FR-26: Appearance

- System / Light / Dark, stored per Apple device, default System, applied immediately.
- Light and Dark are both fully designed; neither is a fallback.

## 7. Sync and conflict model

### 7.1 Transport

SwiftData mirrors the local store to the CloudKit private database. v1 uses this automatic mirroring; no custom sync engine. Sync is eventually consistent. An Apple device may stay offline for any length of time and catch up later.

If testing shows the automatic mirroring cannot meet the rules below, the architecture may switch to `CKSyncEngine`. The requirements stay the same.

### 7.2 Model rules required by CloudKit

- No unique constraints in the schema.
- Every attribute optional or with a default.
- Every relationship optional and with an inverse; no `deny` delete rules.
- Schema changes after the first production deployment are additive only: never rename or delete an attribute or entity.

All uniqueness rules in this document are therefore enforced by app logic and by the merge in §7.4.

### 7.3 Record classes

| Class | Entities | Rule | Conflict result |
|---|---|---|---|
| Append-only | MeterReading, AuditCorrection, StatusSnapshot | Created once, never changed | None possible |
| Decision | MeterRegressionPrompt | Created once per reading; resolution fields may change | Last `resolvedAt` wins (see below) |
| Settings | Household, MainMeter | Mutable | Last write wins per record |
| Contract | Tariff | Mutable, every change also appends Audit Corrections | Last write wins; the corrections keep the trail |
| Note | Event | Mutable, deletable | Last write wins |
| Structure | Room, PowerPoint, Device | Mutable, soft-delete | Last write wins |
| Passive | SmartPlugReading | Written by import only | None possible |

If two Apple devices resolved the same prompt differently while offline, the later `resolvedAt` wins, and the app shows a one-time notice: "This reading was classified differently on another device. It is now: rollover." The user can change it in the reading's detail.

### 7.4 Automatic duplicate merge

Runs at launch, after each sync import, and after import. It is deterministic and idempotent, so every Apple device reaches the same result. "Keep the earliest" means earliest `createdAt`, ties by lowest id.

| Duplicate | Rule |
|---|---|
| Household | Keep the earliest. For each settings field, take the value from the record that changed it last. Delete the others. |
| MainMeter | Keep the earliest. Move readings and prompts of the others to it. Keep any known digit capacity. Delete the others. |
| MeterReading — exact duplicates (same `mainMeterId`, same `readingTimestamp` to the second, same original `kwhValue`) | Keep the earliest. Move its duplicates' Audit Corrections, prompts and snapshot causes to it. Delete the duplicates. No user step. |
| Regression prompts for the same reading | Keep a resolved one over an open one; between resolved ones, keep the latest `resolvedAt`. Delete the others. |
| StatusSnapshot with the same `causeId` | Keep the earliest. Delete the others. |
| AuditCorrection with identical entity, field, old value, new value and `correctedAt` | Keep one. |

Readings with the same timestamp but different values are **not** duplicates. Both stay. The ordering rule (§5.1) handles them.

### 7.5 Data set generation and replace-all

Replace-all (FR-20) deletes all records and writes the imported ones with a new `generation` id, also stored on the Household. Every new record gets the Household's current generation.

An Apple device that was offline during the replace may later upload records with an older generation. These records are not used in any calculation or list. Today shows: "3 readings and 1 event from before the restore arrived from another device." with **Keep** and **Discard**. Keep rewrites them into the current generation (and runs the merge). Discard deletes them. Nothing is dropped silently.

### 7.6 After a sync import

The app runs the merge, re-checks regression ordering (FR-11), refreshes the UI, reschedules notifications if tariffs or settings changed, and reloads widgets. It writes no Status Snapshot for remote changes.

## 8. Export file format

One UTF-8 JSON document. This is the format of the old web app's export; the app reads and writes it so history moves in, and data can always be read with any JSON tool.

### 8.1 Encoding rules

- Instants: ISO 8601 with explicit offset, e.g. `2026-09-22T10:00:00+00:00`. The app writes UTC (`+00:00`) and reads any offset.
- `tariffs[].contractStartDate` is an instant in the file. The app writes the calendar date at `T00:00:00+00:00` and reads the calendar date of the value in its own offset.
- Decimals: JSON numbers. Read without loss of precision (parse as decimal, never as binary floating point).
- Ids: UUID strings.
- Enums: as listed per field.
- Unknown properties are ignored.

### 8.2 Top level

```json
{
  "formatVersion": "v2",
  "exportedAtUtc": "2026-09-22T10:00:00+00:00",
  "household": { },
  "householdMembers": [ ],
  "mainMeter": { },
  "meterReadings": [ ],
  "meterRegressionPrompts": [ ],
  "tariffs": [ ],
  "events": [ ],
  "rooms": [ ],
  "powerPoints": [ ],
  "devices": [ ],
  "smartPlugReadings": [ ],
  "statusSnapshots": [ ],
  "auditCorrections": [ ]
}
```

`formatVersion` is always the string `"v2"`. `mainMeter` is `null` when no reading exists.

### 8.3 Fields

**household**

| Field | Type | Notes |
|---|---|---|
| id | uuid | |
| createdAtUtc | instant | |
| locale | string | e.g. `"de-DE"`; stored, not used for UI |
| currency | string | ISO 4217 |
| yearlyBaselineKwh | decimal or null | |
| trendingThresholdKwh | decimal | annual kWh |
| lowConfidenceGapDays | int | |
| tariffCheckCadenceMonths | int | |
| aiPlausibilityEnabled | bool | written `false`, ignored on read |
| aiPlausibilityBackendConfigured | bool | written `false`, ignored on read |
| aiPlausibilityBackendLabel | string or null | written `null`, ignored on read |

**householdMembers[]** — `id` (uuid), `displayName` (string or null). Written as `[]`. Ignored on read, including any extra identity fields older files carry.

**mainMeter** — `id`, `createdAtUtc`, `digitCapacityKwh` (decimal or null).

**meterReadings[]**

| Field | Type | Notes |
|---|---|---|
| id | uuid | |
| mainMeterId | uuid | must reference `mainMeter.id` |
| kwhValue | decimal | effective value |
| readingTimestamp | instant | |
| idempotencyKey | uuid | written equal to `id`; ignored on read |
| createdAtUtc | instant | |

On import, the reading's original `kwhValue` is set so that its effective value after applying the file's corrections equals the file's `kwhValue`: original = `oldValue` of its earliest `KwhValue` correction if any, else `kwhValue`.

**meterRegressionPrompts[]** — `id`, `mainMeterId`, `meterReadingId`, `previousMeterReadingId` (both must reference readings), `createdAtUtc`, `resolvedAtUtc` (instant or null), `classification` (`"reset"`, `"rollover"` or null), `digitCapacityKwh` (decimal or null; set only for rollover).

**tariffs[]** — `id`, `monthlyBaseFee` (decimal), `pricePerKwh` (decimal), `currency` (string), `contractStartDate` (instant), `contractPeriodMonths` (int), `createdAtUtc`.

**events[]**

| Field | Type | Notes |
|---|---|---|
| id | uuid | |
| description | string | |
| occurredAt | instant | |
| createdAtUtc | instant | |
| taggedEntityType | string or null | `"Room"`, `"PowerPoint"`, `"Device"` |
| taggedEntityId | uuid or null | |
| taggedEntityName | string or null | name at tagging time |
| correlationDirection | string or null | `"Bump"`, `"Dip"` or null. Written from §5.6 at export time; ignored on read |
| correlationComputedAtUtc | instant or null | export time when direction is set, else null |

**rooms[]** — `id`, `name`, `createdAtUtc`, `archivedAt` (instant or null).
**powerPoints[]** — as rooms, plus `roomId` (must reference a room).
**devices[]** — as rooms, plus `powerPointId` (must reference a power point).

**smartPlugReadings[]** — `id`, `powerPointId` (uuid or null), `roomName`, `powerPointName`, `deviceName` (≤ 200 chars), `intervalStart`, `intervalEnd` (instants), `kwhValue` (decimal).

**statusSnapshots[]** — `id`, `status` (`"withinrange"`, `"belowbaseline"`, `"trending"`), `paceToDateKwh`, `baselineToDateKwh` (decimals), `isLowConfidence` (bool), `computedAtUtc`. `causeId` is not in the file; imported snapshots get their own `id` as `causeId`.

**auditCorrections[]** — `id`, `entityType` (string, e.g. `"MeterReading"`, `"Tariff"`), `entityId` (uuid), `fieldName` (string), `oldValue`, `newValue` (strings, invariant culture), `correctedAtUtc`.

### 8.4 Validation on import

The file is rejected, with every failure listed, if any of these fails:

1. `formatVersion` is missing or not `"v2"` (checked first; if it fails, nothing else is reported).
2. A required property is missing or has the wrong JSON type.
3. An enum value is not one of the listed values (case-insensitive for `status` and `classification`).
4. An id appears twice within one array.
5. A reference does not resolve within the file (`mainMeterId`, `meterReadingId`, `previousMeterReadingId`, `roomId`, `powerPointId` on devices; `powerPointId` on smart plug readings when not null; `taggedEntityId` when not null, against the array named by `taggedEntityType`).
6. A value breaks a domain rule: reading kWh ≤ 0; tariff rules of FR-12; `deviceName` longer than 200; name empty; `digitCapacityKwh` set on a non-rollover prompt.

Failure messages name the location and the problem, e.g. `meterReadings[2]: 'kwhValue' must be a number.`

### 8.5 Minimal example

```json
{
  "formatVersion": "v2",
  "exportedAtUtc": "2026-09-22T10:00:00+00:00",
  "household": {
    "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000001",
    "createdAtUtc": "2026-01-05T08:00:00+00:00",
    "locale": "de-DE",
    "currency": "EUR",
    "yearlyBaselineKwh": 3500.0,
    "trendingThresholdKwh": 100.0,
    "lowConfidenceGapDays": 45,
    "tariffCheckCadenceMonths": 3,
    "aiPlausibilityEnabled": false,
    "aiPlausibilityBackendConfigured": false,
    "aiPlausibilityBackendLabel": null
  },
  "householdMembers": [],
  "mainMeter": {
    "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000003",
    "createdAtUtc": "2026-01-05T09:00:00+00:00",
    "digitCapacityKwh": null
  },
  "meterReadings": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000004",
      "mainMeterId": "b6f1f6b0-6b8b-4d3a-9b1a-000000000003",
      "kwhValue": 12345.6,
      "readingTimestamp": "2026-09-01T18:00:00+00:00",
      "idempotencyKey": "b6f1f6b0-6b8b-4d3a-9b1a-000000000004",
      "createdAtUtc": "2026-09-01T18:00:05+00:00"
    }
  ],
  "meterRegressionPrompts": [],
  "tariffs": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000006",
      "monthlyBaseFee": 8.50,
      "pricePerKwh": 0.32,
      "currency": "EUR",
      "contractStartDate": "2026-01-01T00:00:00+00:00",
      "contractPeriodMonths": 12,
      "createdAtUtc": "2026-01-05T08:30:00+00:00"
    }
  ],
  "events": [],
  "rooms": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000007",
      "name": "Kitchen",
      "createdAtUtc": "2026-01-05T08:15:00+00:00",
      "archivedAt": null
    }
  ],
  "powerPoints": [
    {
      "id": "b6f1f6b0-6b8b-4d3a-9b1a-000000000008",
      "roomId": "b6f1f6b0-6b8b-4d3a-9b1a-000000000007",
      "name": "Counter outlet",
      "createdAtUtc": "2026-01-05T08:16:00+00:00",
      "archivedAt": null
    }
  ],
  "devices": [],
  "smartPlugReadings": [],
  "statusSnapshots": [],
  "auditCorrections": []
}
```

## 9. UX

### 9.1 Navigation — iPhone

A tab bar with three tabs. Settings opens from a toolbar button on Today.

| Tab | Content |
|---|---|
| Today | Status card, attention cards (FR-7), Log reading (primary), Log event (secondary) |
| History | Segmented: Trend (chart) · Readings · Events |
| Tariffs | Tariff Check line, current tariff, Compare, tariff history |

Settings: Yearly Baseline, threshold, low-confidence gap, currency, Rooms & Devices, Tariff reminders, iCloud status, Export, Import, Appearance, About (version, build, privacy statement).

### 9.2 Navigation — iPad

`NavigationSplitView` with a sidebar (Today, History, Tariffs, Settings).

- History in landscape: chart on top, Readings and Events lists side by side below.
- Tariffs in landscape: current tariff and history on the left, Compare on the right, both comparison signals side by side.
- Works in all window sizes (Split View, Slide Over, Stage Manager) and both orientations.
- Keyboard shortcuts: ⌘N log reading, ⌘E log event, ⌘, Settings, ⌘F search in lists.

### 9.3 Visual identity

Native SwiftUI controls and Liquid Glass materials. Custom color only where it carries meaning.

| Token | Light | Dark | Use |
|---|---|---|---|
| Brand accent (app tint) | `#1E7A61` | `#2FB397` | Buttons, links, selection, app icon. **Never** a Status color. |
| Within range | `#6B8656` | `#9FBB8A` | Status dot, chart points, accents |
| Within range — label text | `#41603A` | `#C7DCBB` | Badge text on a 14–16 % tint of the Status color |
| Below baseline | `#2F9E52` | `#4FCA72` | As above; the only saturated green, because it is good news |
| Below baseline — label text | `#1F7038` | `#B9EFC7` | |
| Trending | `#B87A1E` | `#E2A542` | Amber: "worth a look", not an alarm |
| Trending — label text | `#8A5A14` | `#F5CE93` | |
| Error | system red | system red | Only for real failures (save failed, import rejected). Never for Status, tariffs or gaps |

Rules:

- Status is never shown by color alone: always a label and an SF Symbol (within range `checkmark.circle`, below baseline `arrow.down.circle`, trending `arrow.up.right.circle`).
- Gap bands and "uncertain" marks use the trending amber at low opacity, never red.
- Dense, compact layouts: icon buttons in rows rather than text pills; units inside number fields ("kWh", "€/kWh", "€/month").
- One sheet at a time. A follow-up (e.g. regression prompt) replaces the current sheet.
- Respect Reduce Motion and Reduce Transparency.

### 9.4 Voice and tone

Plain, specific, human. Name the actual number and the actual thing. No exclamation marks, streaks or praise.

| Do | Don't |
|---|---|
| "Quiet week — 240 kWh under pace." | "Great job! You're crushing your energy goals! 🎉" |
| "Worth a look. You're 60 kWh above your yearly pace." | "Warning: high consumption detected." |
| "Tariff check — nothing due until 1 Oct." | A recommendation when nothing is due |
| "Usage was above baseline pace in the two weeks around this event." | "Confirmed: your sauna caused this spike." |
| "No reading between 3 Apr and 17 Apr, so this stretch is shown as a gap." | A line drawn through the gap |
| "Log your first reading to get started." | A blank screen or a default Status |

## 10. Distribution and environments

**v1 channels:** personal builds installed from Xcode on the owner's Apple devices, and TestFlight. App Store submission comes later; v1 must not block it.

- An Apple Developer Program membership is required (CloudKit and TestFlight need it).
- One bundle id, one App Group, one CloudKit container `iCloud.<bundle id>`.
- **CloudKit environments.** TestFlight and App Store builds always use the CloudKit **Production** environment. The **Personal** build configuration also sets `com.apple.developer.icloud-container-environment = Production`, so personal and TestFlight builds see the same real data. The **Debug** configuration uses the **Development** environment and holds only test data.
- **Schema deployment.** Before any Personal or TestFlight build that adds model fields is installed, the Development schema is deployed to Production in the CloudKit Console. Production schema changes are additive only (§7.2). A release checklist step enforces this.
- TestFlight builds expire after 90 days. Data is not affected, because it lives in the store and iCloud, not in the build.
- **App Store readiness from v1:** privacy manifest present; App Privacy label "Data Not Collected"; `ITSAppUsesNonExemptEncryption = NO`; no private APIs; all permission prompts have purpose strings; a support URL and privacy policy URL can be supplied without code changes.
- Versioning: semantic marketing version; build number increases with each build.

## 11. Non-functional requirements

- **Performance.** On the oldest supported iPhone with 10 years of data: cold launch to visible Status < 1 s; save reading to updated Status < 0.5 s; Trend "all" chart < 1 s; export < 10 s.
- **Offline.** Every feature works without network. Sync is never a precondition.
- **Durability.** No user-entered value is lost through sync, merge, app update or crash. A save is committed to disk before confirmation shows.
- **Exactness.** kWh and money are exact decimals (`Decimal`, or scaled integers if `Decimal` does not round-trip exactly through CloudKit). Binary floating point is never used for stored values or money. Display rounding: kWh 1 place (2 when the value has 2), money 2 places, price per kWh 4 places.
- **Time.** Instants stored as absolute time. Calendar-only values (tariff start date) stored as a calendar date so a time-zone change never moves them.
- **Privacy.** No network traffic except Apple iCloud services. No analytics, tracking or third-party SDK. Apple's opt-in crash reports are the only diagnostics.
- **Security.** File protection "complete until first user authentication" so widgets work on the Lock Screen after the first unlock. The app holds no secrets.
- **Shared store.** The store lives in the App Group container. The app, widget extension and intents use the same store and the same calculation package.
- **Accessibility.** VoiceOver labels everywhere, including an accessibility description and Audio Graph for the trend chart; Dynamic Type up to the largest accessibility sizes without truncating the Status; 44 pt minimum hit targets; Status never by color alone; WCAG AA contrast for all text.
- **Localization.** English and German complete; no hard-coded user-facing text.
- **Testability.** The calculation package has unit tests for every example in §5.8 and for each rule in §5. The merge (§7.4) and generation rules (§7.5) have unit tests with simulated two-device record sets. Import has tests for every validation rule in §8.4 and an export→import round trip. UI tests cover: log reading, regression prompt, correction, tariff compare, import, export.
- **Footprint.** 10 years of data stays well under the free iCloud quota (target < 10 MB without Smart Plug data).
- **Schema evolution.** The SwiftData schema is versioned from the first release with an explicit migration plan.

## 12. Non-goals (v1)

- Multi-user, invites, sharing between Apple Accounts.
- Any server or web app, and sync with one.
- AI features of any kind.
- Real-time monitoring, room or device attribution, any "residual" figure.
- Tiered or time-of-use tariffs; market tariff rankings.
- More than one Main Meter in the UI.
- Deleting meter readings.
- Push notifications about Status, reading reminders, streaks.
- macOS, watchOS, visionOS apps.

## 13. Deferred (later versions)

- Smart Plug file import (Eve Home `.xlsx`, Meross `.csv`), per-plug views, gap handling within imports, and using plug coverage to soften the low-confidence flag. Imported Smart Plug readings are already stored for this.
- A weekly "anything unusual?" prompt after a trending episode.
- On-device AI help for Events.
- Native Mac app; Apple Watch quick entry.
- Sharing a data set with another Apple Account.
- App Store release.

## 14. Success metrics

- **SM-1** The old web app and any spreadsheet are retired: all readings for 3 months are logged in this app.
- **SM-2** The reading habit holds: median interval between readings ≤ 2 days over a quarter (from the user's own data, never telemetry).
- **SM-3** At least one trending Status noticed early enough to change behavior before the annual bill, and at least one tariff decision made with the bonus-normalized figure.
- **SM-4** No data loss across two Apple devices over 3 months: reading counts and effective values match on both after sync.
- **Counter-metric** More time in the app or more frequent checking is a regression.

## 15. Open questions

1. **iOS mockups.** Which design workflow produces the §9.5 mockups, and do they extend the old web app's visual system or start fresh from §9.3?
2. **Old web deployment.** After migration, is the old server shut down, kept read-only, or kept running for a while? The app has no dependency on it either way.

## 16. Assumptions

- **A1** One Apple Account on all of the user's Apple devices.
- **A2** SwiftData's automatic CloudKit mirroring is reliable enough for one user's low write volume (§7.1 names the fallback).
- **A3** Language per Apple device (iOS per-app language) is acceptable for a single user.
- **A4** Events are notes, so edit and delete without an audit trail is acceptable.
- **A5** 10:00 local for notifications and the 15-second first-launch iCloud wait are tunable defaults.
- **A6** Exact duplicate readings (same meter, timestamp to the second, same original value) are always the same reading entered twice and are safe to merge without asking.
