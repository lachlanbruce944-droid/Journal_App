# Journal app: build review

A personal iPhone app that keeps a daily record of your life in one place: journal, health, finance, and reports on weather, surf, markets and news. Each day on the calendar pulls all of it together.

| | |
|---|---|
| Platform | iPhone, iOS 17 or later |
| Built with | Swift and SwiftUI, data saved with SwiftData (on the phone only) |
| Version | 2.0 |
| Code | `Sources/JournalApp.swift`, one file, about 6,450 lines |
| Repository | `lachlanbruce944-droid/Journal_App` |
| Latest build | Releases › **Latest simulator build** › `Journal-simulator.zip` |
| Try it online | Upload that zip to appetize.io (iPhone, newest iOS) |

---

## 1. How to review a build

1. Open the repository's **Actions** tab. Every change runs **Build simulator app** on a GitHub Mac (about 1–2 minutes).
2. A green tick means Xcode reported `BUILD SUCCEEDED`. A red cross means the code didn't compile; open the failed step and copy the lines starting with `error:`.
3. Download **Journal-simulator.zip** from **Releases › Latest simulator build**. The link always points to the newest build:
   `https://github.com/lachlanbruce944-droid/Journal_App/releases/download/latest/Journal-simulator.zip`
4. Upload it to Appetize as it is (don't unzip it), pick an iPhone and press play.
5. Work through the checklist in section 8.

---

## 2. First launch

A one-time setup, moved through with round arrow buttons (back on the left, forward on the right):

1. **Welcome**
2. **Name**: required to continue
3. **Birthday**: date wheel, kept on the phone
4. **Location**: "Use my current location" or search for a town or suburb. **Australian locations only.** Can be skipped.

The answers can be changed later in **Profile** (person icon on the Calendar and Journal tabs).

---

## 3. Navigation

Five tabs on a solid floating tab bar (black in light mode, white in dark mode). Each tab switches its sections with a capsule control at the top.

| Tab | Sections |
|---|---|
| **Calendar** | Month grid → tap a day for the daily report |
| **Journal** | Entries · Notes · Reminders |
| **Reports** | Weather (Forecast · Surf) · Markets (Global · ASX · Crypto) · News |
| **Health** | Diet · Sleep |
| **Finance** | Savings · Goals · Expenses |

**Design:** style B, "Solid Mono": black and white only, capsule buttons (solid for the main action, outlined for secondary, red outline for delete), bold titles, and cards on a grey background.

**Appearance (Profile):** System · Light · Dark · **Auto**. Auto is dark from sunset to sunrise at your saved location, calculated on the phone (no internet), or 6 pm to 6 am if no location is saved.

---

## 4. Features by section

### Calendar: daily record
- Month grid. Black dots are journal entries (up to 3), a grey dot is highlighted news, and today has a ring.
- Tap a day to open the **daily report**: four cards in this order, each with a one-line summary. Tap a card to expand it.
  1. **Health**: calories logged, hours slept, each meal and sleep log
  2. **Journal**: entries, notes and reminders due that day, plus "New entry for this day"
  3. **Reports**: high and low temperature and rain, **surf at each of your breaks** (rating, height, period, direction, dawn wind, water temperature), highlighted headlines, and your watchlist's closing prices
  4. **Finance**: money spent, money added to goals
- Rule for future changes: **any new feature in a section is added to that section's card in the daily report.**

### Journal
- **Entries**: title, date, mood (5 faces), text. Searchable; swipe to delete.
- **Notes**: searchable and pinnable (swipe right). Blank notes are removed automatically.
- **Reminders** (your own to-dos): grouped as Overdue, Upcoming and Completed, with an optional phone alert at the due time.

### Reports
- **Weather › Forecast**: current conditions plus a 7-day forecast (temperature range bar, rain chance and mm, wind speed and direction, gusts, UV). Australia only.
- **Weather › Surf**: South East Queensland only (NSW border to Noosa).
  - 26 built-in breaks across the Gold Coast, the Brisbane bay islands and the Sunshine Coast, plus your own (name, search, which way the beach faces).
  - Today card: swell height, period, direction, dawn wind (5–9 am) as offshore, cross-shore or onshore, water temperature, afternoon wind.
  - 7 days, each with a 5-bar rating. Tap a day for total sea, wind chop, afternoon wind and best swell direction.
  - The rating is a rough guide combining swell size, period, swell angle and dawn wind.
- **Markets**: detail cards (design B).
  - Name and exchange top left; ticker over price top right; change badge (solid ▲ up, outlined ▼ down).
  - Wide chart with a dotted line at yesterday's close (for crypto, the price 7 days ago).
  - Figures: Open · High · Low · Prev close for shares and indices; 24h high · 24h low · Volume · Market cap for crypto.
  - **Watchlist** (outlined button, top right): Favourites list (ASX, global, crypto) or a custom ticker (`TLS` tries the ASX first, `AAPL`, `SOL-AUD`). Only watchlist items are recorded in the daily report.
- **News**: your RSS feeds (ABC, BBC and Hacker News suggested), managed with the sliders icon.
  - Tap the square on a headline to highlight it; it moves into a pinned **Highlighted** section.
  - **Only highlighted headlines appear in the daily report.** Every headline is still saved, so you can highlight older stories from a day's "All saved" list.

### Health
- **Diet**: log meals by type (breakfast, lunch, dinner, snack) with kcal and optional protein, against a daily target (default 2,000 kcal, changeable). Day arrows to look back.
- **Sleep**: bedtime, wake time and a 1–5 star rating; 7-night bar chart, average and history.

### Finance
- **Savings**: account balances you type in, with a total. There's no bank connection.
- **Goals**: target, amount saved and an optional date. "Add money" records a deposit, which shows as **Saved** on that calendar day.
- **Expenses**: amount, description, category and date. Today, this week and this month totals, top 4 categories this month, and a list by day.

### Profile
- Name, birthday, location, appearance.
- **Reminders**: see section 5.
- Done is a solid capsule; Cancel is an outlined capsule.

---

## 5. Reminders (newest feature)

**Profile › Reminders** shows one card per category. A closed card lists what's on; tap it to open it in place.

| Category | Reminder | What it asks | Default |
|---|---|---|---|
| Health | How did you sleep? | Log it | Daily 7:00 am, on |
| Health | Log today's meals | Log it | Daily 7:30 pm, on |
| Journal | Write today's entry | Only if behind | Daily 9:00 pm, on |
| Reports | Morning surf and weather | Check & update | Daily 5:15 am, on |
| Reports | Watchlist at the close | Check & update | Weekdays 4:15 pm, off |
| Finance | Log today's spending | Log it | Daily 8:00 pm, on |
| Finance | Update account balances | Check & update | Weekly, Sunday 6:00 pm, on |
| Finance | Goal check-in | Only if behind | Monthly, 1st, 6:00 pm, off |

- Each reminder has an on/off switch, frequency (Daily · Weekdays · Weekly · Monthly), day of week or month, and time.
- **Send a test reminder** fires one in about 5 seconds.
- **Timeline** (button next to the heading) opens a separate window:
  - **Today**: your reminders in time order, with a "now" line; earlier ones are faded and ticked. Tap one to jump back to its card.
  - **This week**: a grid of reminder times against the next 7 days, plus the total and busiest day.
- **On the Lock Screen and in Notification Centre:**
  - *Log it*: buttons such as **Log a meal** or **In 1 hour** (snooze). Spending and journal reminders let you **type a reply** straight into the notification, for example `18.50 lunch`, which is saved as an expense with a guessed category.
  - *Check & update*: tapping opens the right screen (Savings, Surf, Markets…).
  - *Only if behind*: skipped automatically if you've already done the task that day (or month).
  - Tapping any reminder opens the matching tab and section, and the add sheet where it makes sense.
- iOS asks for notification permission the first time you turn reminders on or send a test.

---

## 6. Data and privacy

- **All your records stay on the phone** (SwiftData). There are no accounts, no server and no analytics.
- Your location is only used for weather, surf distance suggestions and Auto appearance. Only the town or suburb name and its coordinates are kept.
- Online sources (free, no keys):

| Data | Source | Notes |
|---|---|---|
| Weather forecast and history | Open-Meteo (forecast and archive) | Includes Bureau of Meteorology models |
| Swell, wave period and water temperature | Open-Meteo Marine | Coastal points are nudged out to sea if needed |
| Share and index prices | Yahoo Finance chart data (unofficial) | Can be about 20 minutes delayed; could change without notice |
| Crypto prices | CoinGecko public API | About 5 requests a minute; credit shown |
| News | Your RSS feeds | Headlines saved on the phone |
| Place search | Apple Maps (MapKit) | Australia only; SE QLD only for surf breaks |

The free tiers of Open-Meteo and the CoinGecko keyless API are for **non-commercial use**. Selling the app would need paid plans or other sources.

---

## 7. How the code is organised

Everything is in `Sources/JournalApp.swift`, in `// MARK:` sections in roughly this order:

1. **App entry**: `JournalApp` (shared data store, notification handler), `RootView` (floating tab bar, appearance, first-launch setup)
2. **Calendar**: `CalendarView` month grid
3. **Journal**: `EntryListView`, `EntryEditorView`, `NotesView`, `RemindersView`
4. **News**: feed parsing, archive, highlighting, `DayNewsView`
5. **Profile and setup**: `UserProfile`, `LocationPicker`, `OnboardingView`, `ProfileView`
6. **Weather**: `WeatherService`, `WeatherView`; **Surf**: `SurfBreak`, `SEQLD` presets, `SurfService`, `SurfView`, `ManageBreaksView`
7. **Markets**: `StockService`, `CryptoService`, `MarketsView`, `QuoteCard`, `Sparkline`, `WatchlistView`, `TickerLookup`
8. **Category tabs**: `JournalTab`, `ReportsTab`, `HealthTab`, `FinanceTab`
9. **Health**: `DietView`, `SleepView`; **Finance**: `SavingsView`, `GoalsView`, `ExpensesView`
10. **Daily report**: `DayDetailView`, `SnapshotCard`
11. **Style B controls**: `CapsuleButtonStyle`, `MonoSegment`, `FloatingTabBar`; `SunTimes` for Auto appearance
12. **Reminders**: `ReminderRule`, `ReminderPlan`, `ReminderScheduler`, `ReminderActions`, `AppRouter`, `RemindersSection`, `ReminderTimelineView`

**Saved data types (15):** JournalEntry, Note, Reminder, Meal, SleepLog, BankAccount, SavingsGoal, GoalDeposit, Expense, NewsFeed, SavedHeadline, WatchItem, SurfBreak, UserProfile, ReminderRule.

**Other files:**
- `project.yml`: project settings (bundle ID `com.lachlanbruce.journal`, iOS 17, location permission text). XcodeGen turns it into `Journal.xcodeproj`.
- `.github/workflows/build.yml`: builds for the iPhone simulator, checks the zip contains `Journal.app`, and publishes it to Releases.
- `README.md`: setup steps.

**On a Mac:** `git clone` the repo, `brew install xcodegen`, `xcodegen generate`, `open Journal.xcodeproj`, then ⌘R. See the README for details.

---

## 8. Review checklist

**Setup and appearance**
- [ ] Fresh install shows Welcome → Name (can't continue blank) → Birthday → Location
- [ ] Location search only offers Australian places
- [ ] Profile › Appearance: Light, Dark and Auto switch the theme; Auto shows today's sunset and sunrise times

**Daily record**
- [ ] Calendar dots appear for entries and highlighted news
- [ ] Day report order is Health, Journal, Reports, Finance; each card expands
- [ ] Reports card shows a surf line once you've saved a break

**Reports**
- [ ] Weather loads for your suburb; tap a day for gusts and UV
- [ ] Surf: add the 3 suggested breaks; the rating and 7 days load; adding a custom break works
- [ ] Markets cards show Open/High/Low/Prev (or 24h figures for crypto) without "–"
- [ ] Watchlist: add from Favourites and by typing `TLS`
- [ ] News: highlighting moves a story to the top; it shows on today's calendar report

**Health and finance**
- [ ] Log a meal and a sleep; both show in today's report
- [ ] Add an account, a goal with "Add money", and an expense; they show under Finance and in the report

**Reminders**
- [ ] Profile › Reminders: turning on asks for notification permission
- [ ] "Send a test reminder" pops up after about 5 seconds
- [ ] Timeline: Today shows the "now" line; This week shows the grid
- [ ] Long-press the spending test reminder, reply `18.50 lunch`, and check Finance › Expenses

On Appetize, notifications and location can behave differently from a real iPhone. If something there looks wrong, try it on a device through Xcode before treating it as a bug.

---

## 9. Known limits

- **Built from one file**: easy to share and build, but it'll be worth splitting into several files as the app grows.
- **Live data checks**: the weather, surf, market and news sources were wired up from their documentation. Each build compiles cleanly, but their real responses can only be confirmed by running the app.
- **Tides** aren't shown: the free source isn't accurate enough near the shore.
- **Reminder text** (for example "1,240 kcal so far") reflects what you'd logged when the app last scheduled reminders, which happens when you open or leave the app. iOS doesn't let a reminder fetch live surf or prices at the moment it appears.
- **iOS keeps at most 64 upcoming reminders.** With everything on, this app schedules about 50 (a week of daily ones), and they're topped up each time you open the app.
- **The web test version** (Journal Test App in Claude) has every screen, including Surf, the market cards and Reminders with the timeline. It uses sample weather, swell, market and news data, and test reminders pop up as a preview at the top of the page instead of on a Lock Screen.

---

## 10. Change history

| Commit | Change |
|---|---|
| `fc14b0d` | First upload: journal, calendar, reports, health, finance, onboarding, style B, Auto appearance, simulator build workflow |
| `75f3787` | Build publishes `Journal-simulator.zip` to Releases for Appetize |
| `1159f76` | Weather › Surf: South East Queensland swell forecast and custom breaks |
| `4f7e141` | Markets: detail cards with chart under the name and ticker above the price |
| `7cda3f7` | Daily report: Health moved first; surf at your breaks added to Reports |
| `9c3222f` | Profile reminders: category cards, timeline window, notification replies and snooze | (build passed)

A backup of the version before the five-tab navigation is in the IOS App project: `backups/JournalApp-v1-backup-2026-11-04.swift`.
