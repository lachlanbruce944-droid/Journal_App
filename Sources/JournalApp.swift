// JournalApp.swift
// A simple iOS journal app using SwiftUI + SwiftData (iOS 17+).
// In Xcode: File > New > Project > iOS App (Interface: SwiftUI, Storage: None).
// Delete the generated ContentView.swift and <YourApp>App.swift, then add this file.

// The setup flow asks for location. In Xcode, select your app target > Info tab, and add the key
// "Privacy - Location When In Use Usage Description" with text such as
// "Your location is used to show local weather." (the app crashes on the location prompt without it).

import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UserNotifications
import Combine

// MARK: - Model

@Model
final class JournalEntry {
    var title: String
    var body: String
    var mood: String
    var createdAt: Date

    init(title: String = "", body: String = "", mood: String = "🙂", createdAt: Date = .now) {
        self.title = title
        self.body = body
        self.mood = mood
        self.createdAt = createdAt
    }
}

// MARK: - App entry point

@main
struct JournalApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.primary)   // black and white theme: black in light mode, white in dark mode
        }
        .modelContainer(for: [JournalEntry.self, NewsFeed.self, SavedHeadline.self, UserProfile.self, WatchItem.self, SurfBreak.self,
                         Note.self, Reminder.self, Meal.self, SleepLog.self,
                         BankAccount.self, SavingsGoal.self, GoalDeposit.self, Expense.self]) // all saved on-device
    }
}

// MARK: - Tabs

enum AppTab: String, CaseIterable {
    case calendar, journal, reports, health, finance

    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .journal: return "book"
        case .reports: return "chart.bar.doc.horizontal"
        case .health: return "heart"
        case .finance: return "creditcard"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @State private var tab: AppTab = .calendar
    @State private var now = Date.now

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// nil follows the phone's own setting.
    private var colorScheme: ColorScheme? {
        guard let profile = profiles.first else { return nil }
        switch profile.appearance {
        case "light": return .light
        case "dark": return .dark
        case "auto": return SunTimes.isNight(at: now, latitude: profile.latitude, longitude: profile.longitude) ? .dark : .light
        default: return nil
        }
    }

    var body: some View {
        tabs
            .preferredColorScheme(colorScheme)
            .onReceive(minuteTimer) { now = $0 }
            // First launch: run the setup flow until a profile has been saved
            .fullScreenCover(isPresented: .constant(profiles.isEmpty)) {
                OnboardingView().tint(.primary)
            }
            // Record today's headlines every time the app is opened
            .task { await NewsSync.refresh(context: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    now = .now
                    Task { await NewsSync.refresh(context: context) }
                }
            }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            CalendarView().floatingTabContent().tag(AppTab.calendar)
            JournalTab().floatingTabContent().tag(AppTab.journal)
            ReportsTab().floatingTabContent().tag(AppTab.reports)
            HealthTab().floatingTabContent().tag(AppTab.health)
            FinanceTab().floatingTabContent().tag(AppTab.finance)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $tab)
                .ignoresSafeArea(.keyboard)
        }
    }
}

// MARK: - Calendar

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }
}

struct CalendarView: View {
    @Query(sort: \JournalEntry.createdAt) private var entries: [JournalEntry]
    @Query(filter: #Predicate<SavedHeadline> { $0.isHighlighted == true }) private var savedNews: [SavedHeadline]

    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDay: Date?
    @State private var path = NavigationPath()
    @State private var showingProfile = false

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var entryCountByDay: [Date: Int] {
        Dictionary(grouping: entries) { cal.startOfDay(for: $0.createdAt) }.mapValues(\.count)
    }

    private var newsDays: Set<Date> { Set(savedNews.map(\.day)) }

    // Days of the displayed month, padded with blanks so day 1 lands on the right weekday
    private var gridDays: [Date?] {
        let count = cal.range(of: .day, in: .month, for: month)!.count
        let leading = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let days = (0..<count).map { cal.date(byAdding: .day, value: $0, to: month) }
        return Array(repeating: nil, count: leading) + days
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        let counts = entryCountByDay
        let news = newsDays

        NavigationStack(path: $path) {
            List {
                Section {
                    monthHeader
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(weekdaySymbols.indices, id: \.self) { i in
                            Text(weekdaySymbols[i])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day, entryCount: counts[day] ?? 0, hasNews: news.contains(day))
                            } else {
                                Color.clear.frame(height: 40)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Tap a day for a snapshot of your journal, reports, health and finance.")
                }
            }
            .navigationTitle("Calendar")
            .navigationDestination(for: DayRoute.self) { route in
                DayDetailView(day: route.date) { entry in path.append(entry) }
            }
            .navigationDestination(for: JournalEntry.self) { entry in
                EntryEditorView(entry: entry)
            }
            .navigationDestination(for: NewsDay.self) { newsDay in
                DayNewsView(day: newsDay.date)
            }
            .navigationDestination(for: Note.self) { note in
                NoteEditorView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { month = cal.startOfMonth(for: .now) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingProfile = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Profile")
                }
            }
            .sheet(isPresented: $showingProfile) { ProfileView().tint(.primary) }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless) // keeps the buttons tappable inside a List row
    }

    private func dayCell(_ day: Date, entryCount count: Int, hasNews: Bool) -> some View {
        let isSelected = selectedDay.map { cal.isDate(day, inSameDayAs: $0) } ?? false
        let isToday = cal.isDateInToday(day)

        return Button {
            selectedDay = day
            path.append(DayRoute(date: day))
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.body.weight(isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isSelected ? Color.primary : Color.clear))
                    .overlay(Circle().stroke(isToday && !isSelected ? Color.primary : Color.clear, lineWidth: 1))
                // Black dots = journal entries (up to three), grey dot = highlighted news
                HStack(spacing: 2) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle().fill(Color.primary).frame(width: 4, height: 4)
                    }
                    if hasNews {
                        Circle().fill(Color.secondary).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(height: 44)
        }
        .buttonStyle(.borderless)
    }

    private func changeMonth(by value: Int) {
        if let next = cal.date(byAdding: .month, value: value, to: month) {
            month = next
        }
    }
}

struct DayRoute: Hashable { let date: Date }

// MARK: - List of entries

struct EntryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]
    @State private var searchText = ""
    @State private var showingProfile = false

    private var filtered: [JournalEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {   // sits inside its category tab's NavigationStack
            List {
                ForEach(filtered) { entry in
                    NavigationLink(value: entry) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(entry.mood).font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                                    .font(.headline)
                                Text(entry.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(entry.createdAt, format: .dateTime.day().month().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(filtered[index]) }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No entries yet",
                                           systemImage: "book.closed",
                                           description: Text("Tap + to write your first entry."))
                }
            }
            .navigationDestination(for: JournalEntry.self) { entry in
                EntryEditorView(entry: entry)
            }
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let entry = JournalEntry()
                        context.insert(entry)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingProfile = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            .sheet(isPresented: $showingProfile) { ProfileView().tint(.primary) }
        }
    }
}

// MARK: - Editor

struct EntryEditorView: View {
    @Bindable var entry: JournalEntry
    private let moods = ["😄", "🙂", "😐", "😔", "😡"]

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $entry.title)
                    .font(.headline)
                DatePicker("Date", selection: $entry.createdAt)
            }
            Section("Mood") {
                MonoSegment(options: moods.map { ($0, $0) }, selection: $entry.mood)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section("Entry") {
                TextEditor(text: $entry.body)
                    .frame(minHeight: 250)
            }
        }
        .navigationTitle(entry.title.isEmpty ? "New Entry" : entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [JournalEntry.self, NewsFeed.self, SavedHeadline.self, UserProfile.self, WatchItem.self, SurfBreak.self,
                         Note.self, Reminder.self, Meal.self, SleepLog.self,
                         BankAccount.self, SavingsGoal.self, GoalDeposit.self, Expense.self], inMemory: true)
}

// MARK: - News: saved feeds

@Model
final class NewsFeed {
    var name: String
    var urlString: String
    var addedAt: Date

    init(name: String, urlString: String, addedAt: Date = .now) {
        self.name = name
        self.urlString = urlString
        self.addedAt = addedAt
    }
}

struct Headline: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let link: URL?
    let date: Date?
    let source: String

    /// Same story = same key, so a highlight sticks to it across refreshes.
    var archiveKey: String { link?.absoluteString ?? "\(source)|\(title)" }
}

// MARK: - News: RSS / Atom parsing

final class FeedParser: NSObject, XMLParserDelegate {
    private var results: [(title: String, link: String, date: String)] = []
    private var inItem = false
    private var buffer = ""
    private var title = "", link = "", date = ""

    func parse(_ data: Data) -> [(title: String, link: String, date: String)] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return results
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" || name == "entry" {       // RSS uses <item>, Atom uses <entry>
            inItem = true
            title = ""; link = ""; date = ""
        }
        if inItem, name == "link", link.isEmpty, let href = attributes["href"] {
            link = href                               // Atom puts the link in an attribute
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        buffer += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        guard inItem else { return }
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": if title.isEmpty { title = text }
        case "link": if link.isEmpty, !text.isEmpty { link = text }
        case "pubDate", "published", "updated", "dc:date": if date.isEmpty { date = text }
        case "item", "entry":
            results.append((title, link, date))
            inItem = false
        default: break
        }
        buffer = ""
    }
}

enum NewsLoader {
    private static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z"] {
            f.dateFormat = format
            if let d = f.date(from: string) { return d }
        }
        return nil
    }

    static func fetch(name: String, url: URL) async -> [Headline]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let items = FeedParser().parse(data)
        guard !items.isEmpty else { return nil }
        return items.map {
            Headline(title: $0.title, link: URL(string: $0.link), date: parseDate($0.date), source: name)
        }
    }

    /// Fetches every feed at the same time; returns all headlines newest-first plus the names of any that failed.
    static func fetchAll(_ sources: [(name: String, url: URL)]) async -> (headlines: [Headline], failed: [String]) {
        await withTaskGroup(of: (String, [Headline]?).self) { group in
            for source in sources {
                group.addTask { (source.name, await fetch(name: source.name, url: source.url)) }
            }
            var all: [Headline] = []
            var failed: [String] = []
            for await (name, headlines) in group {
                if let headlines { all += headlines } else { failed.append(name) }
            }
            all.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            return (all, failed)
        }
    }
}

// MARK: - News: headlines screen

struct NewsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NewsFeed.addedAt) private var feeds: [NewsFeed]
    @Query(filter: #Predicate<SavedHeadline> { $0.isHighlighted == true }) private var highlightedItems: [SavedHeadline]
    @State private var headlines: [Headline] = []
    @State private var failed: [String] = []
    @State private var isLoading = false
    @State private var showingFeeds = false
    @State private var sourceFilter: String? = nil

    private var visible: [Headline] {
        guard let sourceFilter else { return headlines }
        return headlines.filter { $0.source == sourceFilter }
    }

    var body: some View {
        Group {   // sits inside its category tab's NavigationStack
            List {
                if !failed.isEmpty {
                    Label("Couldn't load: \(failed.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                let keys = Set(highlightedItems.map(\.key))
                let pinned = visible.filter { keys.contains($0.archiveKey) }
                let others = visible.filter { !keys.contains($0.archiveKey) }

                if !pinned.isEmpty {
                    Section("Highlighted · \(pinned.count)") {
                        ForEach(pinned) { item in headlineRow(item, isOn: true) }
                    }
                }
                Section {
                    ForEach(others) { item in headlineRow(item, isOn: false) }
                } header: {
                    if !pinned.isEmpty { Text("All headlines") }
                }
            }
            .overlay {
                if feeds.isEmpty {
                    ContentUnavailableView {
                        Label("No news feeds", systemImage: "newspaper")
                    } description: {
                        Text("Add the RSS feed URL of any news site to see its headlines here.")
                    } actions: {
                        Button("Add a feed") { showingFeeds = true }
                    }
                } else if isLoading && headlines.isEmpty {
                    ProgressView("Loading headlines…")
                }
            }
            .refreshable { await load(force: true) }
            .task { await load() }
            .onChange(of: feeds.map(\.urlString)) { Task { await load(force: true) } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All sources") { sourceFilter = nil }
                        ForEach(feeds) { feed in
                            Button(feed.name) { sourceFilter = feed.name }
                        }
                    } label: {
                        Image(systemName: sourceFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFeeds = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("News feeds")
                }
            }
            .sheet(isPresented: $showingFeeds) { ManageFeedsView().tint(.primary) }
        }
    }

    private func row(_ item: Headline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline)
            HStack(spacing: 6) {
                Text(item.source)
                if let date = item.date {
                    Text("·")
                    Text(date, style: .relative) + Text(" ago")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Headline text (opens the story) with the highlight square on the right.
    private func headlineRow(_ item: Headline, isOn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let link = item.link {
                    Link(destination: link) { row(item) }
                        .foregroundStyle(.primary)
                } else {
                    row(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { toggleHighlight(item) } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isOn ? "Remove highlight" : "Highlight as a personal interest")
        }
    }

    private func toggleHighlight(_ item: Headline) {
        let key = item.archiveKey
        var descriptor = FetchDescriptor<SavedHeadline>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        withAnimation(.easeInOut(duration: 0.25)) {
            if let saved = try? context.fetch(descriptor).first {
                saved.isHighlighted.toggle()
            } else {
                let saved = SavedHeadline(key: key, title: item.title, linkString: item.link?.absoluteString,
                                          source: item.source, publishedAt: item.date,
                                          day: Calendar.current.startOfDay(for: min(item.date ?? .now, .now)))
                saved.isHighlighted = true
                context.insert(saved)
            }
            try? context.save()
        }
    }

    private func load(force: Bool = false) async {
        isLoading = true
        let result = await NewsSync.refresh(context: context, force: force)
        headlines = result.headlines
        failed = result.failed
        isLoading = false
    }
}

// MARK: - News: add / remove feeds

struct ManageFeedsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \NewsFeed.addedAt) private var feeds: [NewsFeed]

    @State private var name = ""
    @State private var urlText = ""
    @State private var error: String?

    private let suggestions: [(String, String)] = [
        ("ABC News", "https://www.abc.net.au/news/feed/51120/rss.xml"),
        ("BBC World", "https://feeds.bbci.co.uk/news/world/rss.xml"),
        ("Hacker News", "https://hnrss.org/frontpage")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Add a feed") {
                    TextField("Name (e.g. ABC News)", text: $name)
                    TextField("https://example.com/rss.xml", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: urlText) { error = nil }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Add feed") { add(name: name, url: urlText) }
                }

                Section("Your feeds") {
                    if feeds.isEmpty {
                        Text("No feeds yet").foregroundStyle(.secondary)
                    }
                    ForEach(feeds) { feed in
                        VStack(alignment: .leading) {
                            Text(feed.name)
                            Text(feed.urlString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(feeds[index]) }
                    }
                }

                Section("Suggestions") {
                    ForEach(suggestions, id: \.1) { suggestion in
                        if !feeds.contains(where: { $0.urlString == suggestion.1 }) {
                            Button {
                                add(name: suggestion.0, url: suggestion.1)
                            } label: {
                                Label(suggestion.0, systemImage: "plus.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("News feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle()) }
            }
        }
    }

    private func add(name: String, url: String) {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let parsed = URL(string: text), parsed.host != nil else {
            error = "That doesn't look like a valid URL."
            return
        }
        guard !feeds.contains(where: { $0.urlString == parsed.absoluteString }) else {
            error = "You've already added that feed."
            return
        }
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? (parsed.host ?? "Feed") : name
        context.insert(NewsFeed(name: finalName, urlString: parsed.absoluteString))
        self.name = ""
        urlText = ""
    }
}

// MARK: - News archive (historical headlines, organised by day)

@Model
final class SavedHeadline {
    var key: String            // link (or source + title) used to avoid saving duplicates
    var title: String
    var linkString: String?
    var source: String
    var publishedAt: Date?
    var day: Date              // start of the day the story was published
    var savedAt: Date
    var isHighlighted: Bool = false   // ticked as a personal interest; only these show on the day screen

    init(key: String, title: String, linkString: String?, source: String,
         publishedAt: Date?, day: Date, savedAt: Date = .now) {
        self.key = key
        self.title = title
        self.linkString = linkString
        self.source = source
        self.publishedAt = publishedAt
        self.day = day
        self.savedAt = savedAt
    }
}

@MainActor
enum NewsArchive {
    static func save(_ headlines: [Headline], in context: ModelContext) {
        guard !headlines.isEmpty else { return }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -60, to: .now) ?? .distantPast
        let recent = FetchDescriptor<SavedHeadline>(predicate: #Predicate { $0.savedAt >= cutoff })
        var known = Set(((try? context.fetch(recent)) ?? []).map(\.key))

        for h in headlines where !h.title.isEmpty {
            let key = h.archiveKey
            guard !known.contains(key) else { continue }
            known.insert(key)
            let day = cal.startOfDay(for: min(h.date ?? .now, .now))
            context.insert(SavedHeadline(key: key, title: h.title, linkString: h.link?.absoluteString,
                                         source: h.source, publishedAt: h.date, day: day))
        }
        try? context.save()
    }
}

/// Fetches all feeds and archives the results. Skips re-fetching if it ran in the last 2 minutes (unless forced).
@MainActor
enum NewsSync {
    private static var lastRun: Date?
    private static var lastResult: (headlines: [Headline], failed: [String]) = ([], [])

    @discardableResult
    static func refresh(context: ModelContext, force: Bool = false) async -> (headlines: [Headline], failed: [String]) {
        if !force, let lastRun, Date.now.timeIntervalSince(lastRun) < 120 { return lastResult }
        lastRun = .now
        let feeds = (try? context.fetch(FetchDescriptor<NewsFeed>())) ?? []
        let sources = feeds.compactMap { feed in
            URL(string: feed.urlString).map { (name: feed.name, url: $0) }
        }
        guard !sources.isEmpty else { lastResult = ([], []); return lastResult }
        let result = await NewsLoader.fetchAll(sources)
        NewsArchive.save(result.headlines, in: context)
        lastResult = result
        return result
    }
}

// MARK: - A single day's saved news (opened from the calendar)

struct NewsDay: Hashable { let date: Date }

struct DayNewsView: View {
    let day: Date
    @Query private var items: [SavedHeadline]
    @State private var search = ""
    @State private var sourceFilter: String?
    @State private var showAll = false

    init(day: Date) {
        self.day = day
        _items = Query(filter: #Predicate<SavedHeadline> { $0.day == day })
    }

    private var sources: [String] { Array(Set(items.map(\.source))).sorted() }
    private var highlightedCount: Int { items.filter(\.isHighlighted).count }

    private var visible: [SavedHeadline] {
        items
            .filter { showAll || $0.isHighlighted }
            .filter { sourceFilter == nil || $0.source == sourceFilter }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.publishedAt ?? $0.savedAt) > ($1.publishedAt ?? $1.savedAt) }
    }

    var body: some View {
        List {
            Section {
                MonoSegment(options: [(false, "Highlighted · \(highlightedCount)"), (true, "All saved · \(items.count)")],
                            selection: $showAll)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            ForEach(visible) { item in
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let url = item.linkString.flatMap(URL.init(string:)) {
                            Link(destination: url) { row(item) }
                                .foregroundStyle(.primary)
                        } else {
                            row(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        withAnimation { item.isHighlighted.toggle() }
                    } label: {
                        Image(systemName: item.isHighlighted ? "checkmark.square.fill" : "square")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(item.isHighlighted ? "Remove highlight" : "Highlight as a personal interest")
                }
            }
        }
        .overlay {
            if visible.isEmpty && search.isEmpty {
                ContentUnavailableView(showAll ? "No news saved for this day" : "Nothing highlighted",
                                       systemImage: "newspaper",
                                       description: Text(showAll
                                           ? "Headlines are saved automatically whenever the app is opened and checks your feeds."
                                           : "Switch to All saved and tap a square to highlight a headline."))
            }
        }
        .searchable(text: $search, prompt: "Search headlines")
        .navigationTitle(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All sources") { sourceFilter = nil }
                    ForEach(sources, id: \.self) { source in
                        Button(source) { sourceFilter = source }
                    }
                } label: {
                    Image(systemName: sourceFilter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    private func row(_ item: SavedHeadline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline)
            HStack(spacing: 6) {
                Text(item.source)
                if let date = item.publishedAt {
                    Text("·")
                    Text(date, format: .dateTime.hour().minute())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - User profile (filled in by the first-launch setup)

@Model
final class UserProfile {
    var name: String
    var birthday: Date
    var placeName: String      // e.g. "Burleigh Heads, QLD" — empty if skipped
    var latitude: Double?      // kept for weather reports
    var longitude: Double?
    var createdAt: Date
    var calorieTarget: Int = 2000   // daily energy target used by Health › Diet
    var appearance: String = "system"   // system, light, dark or auto (dark from sunset to sunrise)

    init(name: String, birthday: Date, placeName: String = "",
         latitude: Double? = nil, longitude: Double? = nil, createdAt: Date = .now) {
        self.name = name
        self.birthday = birthday
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}

struct PlaceChoice: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
}

// MARK: - Location helpers

/// Asks for permission (if needed) and returns the phone's current location once.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func currentLocation() async -> CLLocation? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // suburb-level is plenty for weather
        return await withCheckedContinuation { c in
            continuation = c
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: finish(nil)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}

/// "Use my current location" button plus a town/suburb search. Shared by setup and the Profile screen.
struct LocationPicker: View {
    @Binding var place: PlaceChoice?

    @State private var fetcher = LocationFetcher()
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isLocating = false
    @State private var isSearching = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let place {
                HStack {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(Color.primary).font(.title2)
                    Text(place.name).font(.headline)
                    Spacer()
                    Button("Change") { self.place = nil }
                        .buttonStyle(.borderless)
                }
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    HStack {
                        if isLocating { ProgressView() } else { Image(systemName: "location.fill") }
                        Text("Use my current location")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MonoButtonStyle())

                Text("or search for your town or suburb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                HStack {
                    TextField("e.g. Burleigh Heads", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                        .onChange(of: query) { message = nil }
                    Button {
                        Task { await search() }
                    } label: {
                        if isSearching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    }
                    .buttonStyle(.bordered)
                }

                ForEach(results, id: \.self) { item in
                    Button {
                        let c = item.placemark.coordinate
                        place = PlaceChoice(name: Self.label(for: item.placemark, fallback: item.name),
                                            latitude: c.latitude, longitude: c.longitude)
                        results = []
                        query = ""
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Unknown place").foregroundStyle(.primary)
                            if let title = item.placemark.title {
                                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    Divider()
                }
            }

            if let message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private static func label(for placemark: CLPlacemark, fallback: String?) -> String {
        let parts = [placemark.locality ?? placemark.name, placemark.administrativeArea].compactMap { $0 }
        return parts.isEmpty ? (fallback ?? "Selected location") : parts.joined(separator: ", ")
    }

    private func useCurrentLocation() async {
        message = nil
        isLocating = true
        defer { isLocating = false }
        guard let location = await fetcher.currentLocation() else {
            message = "Couldn't get your location. Check that location access is allowed in Settings, or search instead."
            return
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let inAustralia = placemark?.isoCountryCode.map { $0 == "AU" }
            ?? AustraliaRegion.contains(latitude: location.coordinate.latitude,
                                        longitude: location.coordinate.longitude)
        guard inAustralia else {
            message = "Only Australian locations are supported. Search for an Australian town or suburb instead."
            return
        }
        place = PlaceChoice(name: placemark.map { Self.label(for: $0, fallback: nil) } ?? "Current location",
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            message = "Type a town or suburb to search."
            return
        }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        request.region = AustraliaRegion.searchRegion   // bias results to Australia
        let response = try? await MKLocalSearch(request: request).start()
        let australian = (response?.mapItems ?? []).filter { $0.placemark.isoCountryCode == "AU" }
        results = Array(australian.prefix(5))
        if results.isEmpty { message = "No Australian places found. Try a different spelling." }
    }
}

// MARK: - First-launch setup flow

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var step = 0
    @State private var name = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var place: PlaceChoice?
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private let lastStep = 3   // 0 welcome · 1 name · 2 birthday · 3 location

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                ProgressView(value: Double(step), total: Double(lastStep))
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0: welcome
                    case 1: nameStep
                    case 2: birthdayStep
                    default: locationStep
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.primary)
            Text("Welcome to your journal")
                .font(.largeTitle.bold())
            Text("A few quick questions to set things up. You can change any of this later from your profile.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("What should we call you?", "Your name is used to greet you in the app.")
            TextField("Your name", text: $name)
                .font(.title2)
                .textContentType(.givenName)
                .submitLabel(.next)
                .focused($nameFocused)
                .onSubmit { next() }
                .onChange(of: name) { error = nil }
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .onAppear { nameFocused = true }
    }

    private var birthdayStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("When's your birthday?", "This stays private on your phone.")
            DatePicker("Birthday", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Location")
            LocationPicker(place: $place)
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 24)
    }

    // Arrow navigation: back on the left, forward on the right (forward on the last step finishes setup)

    private var footer: some View {
        HStack {
            if step > 0 {
                Button { step -= 1 } label: { Image(systemName: "arrow.left") }
                    .buttonStyle(ArrowButtonStyle(filled: false))
                    .accessibilityLabel("Back")
            }
            Spacer()
            Button { next() } label: { Image(systemName: "arrow.right") }
                .buttonStyle(ArrowButtonStyle(filled: true))
                .accessibilityLabel(step == lastStep ? "Finish" : "Next")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func next() {
        if step == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Enter your name to continue."
            return
        }
        if step < lastStep { step += 1 } else { finish() }
    }

    private func finish() {
        context.insert(UserProfile(name: name.trimmingCharacters(in: .whitespaces),
                                   birthday: birthday,
                                   placeName: place?.name ?? "",
                                   latitude: place?.latitude,
                                   longitude: place?.longitude))
        try? context.save()   // saving the profile closes the setup screen automatically
    }
}

// MARK: - Profile (edit setup details later)

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    ProfileForm(profile: profile)
                } else {
                    ContentUnavailableView("No profile yet", systemImage: "person.crop.circle")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle()) }
            }
        }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: UserProfile
    @State private var place: PlaceChoice?

    private var appearanceNote: String {
        switch profile.appearance {
        case "light": return "Always light."
        case "dark": return "Always dark."
        case "auto":
            let times = SunTimes.today(latitude: profile.latitude, longitude: profile.longitude)
            let where_ = profile.placeName.isEmpty ? "" : " at \(profile.placeName)"
            return "Dark from sunset (\(times.sunset.formatted(date: .omitted, time: .shortened))) to sunrise (\(times.sunrise.formatted(date: .omitted, time: .shortened)))\(where_). Without a location it switches at 6 pm and 6 am."
        default: return "Matches your iPhone's light or dark setting."
        }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Your name", text: $profile.name)
            }
            Section("Birthday") {
                DatePicker("Birthday", selection: $profile.birthday, in: ...Date.now, displayedComponents: .date)
            }
            Section {
                LocationPicker(place: $place)
            } header: {
                Text("Location")
            } footer: {
                Text("Used for local weather reports and Auto appearance.")
            }
            Section {
                MonoSegment(options: [("system", "System"), ("light", "Light"), ("dark", "Dark"), ("auto", "Auto")],
                            selection: $profile.appearance)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Appearance")
            } footer: {
                Text(appearanceNote)
            }
        }
        .onAppear {
            if let lat = profile.latitude, let lon = profile.longitude {
                place = PlaceChoice(name: profile.placeName, latitude: lat, longitude: lon)
            }
        }
        .onChange(of: place) { _, newPlace in
            profile.placeName = newPlace?.name ?? ""
            profile.latitude = newPlace?.latitude
            profile.longitude = newPlace?.longitude
        }
    }
}

// MARK: - Black and white button styles

/// Full-width solid button: black with white text in light mode, white with black text in dark mode.
struct MonoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(.systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.primary, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Round arrow button used to move between setup steps.
struct ArrowButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(filled ? Color(.systemBackground) : Color.primary)
            .frame(width: 56, height: 56)
            .background(Circle().fill(filled ? Color.primary : Color.clear))
            .overlay(Circle().stroke(Color.primary, lineWidth: filled ? 0 : 1.5))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Weather: Australia-only helpers

enum AustraliaRegion {
    /// Rough bounding box around mainland Australia and Tasmania.
    static func contains(latitude: Double, longitude: Double) -> Bool {
        (-44.5 ... -9.5).contains(latitude) && (112.0 ... 154.5).contains(longitude)
    }

    static let searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -25.3, longitude: 133.8),
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 45))
}

enum Compass {
    static func label(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8
        return points[(index + 8) % 8]
    }
}

/// Converts WMO weather codes into an SF Symbol and a short description.
enum WeatherCode {
    static func describe(_ code: Int) -> (symbol: String, text: String) {
        switch code {
        case 0: return ("sun.max", "Sunny")
        case 1: return ("sun.max", "Mostly sunny")
        case 2: return ("cloud.sun", "Partly cloudy")
        case 3: return ("cloud", "Cloudy")
        case 45, 48: return ("cloud.fog", "Fog")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle", "Drizzle")
        case 61, 63, 66: return ("cloud.rain", "Rain")
        case 65, 67: return ("cloud.heavyrain", "Heavy rain")
        case 71, 73, 75, 77, 85, 86: return ("cloud.snow", "Snow")
        case 80, 81: return ("cloud.sun.rain", "Showers")
        case 82: return ("cloud.heavyrain", "Heavy showers")
        case 95: return ("cloud.bolt.rain", "Thunderstorms")
        case 96, 99: return ("cloud.bolt.rain", "Storms with hail")
        default: return ("cloud", "Unknown")
        }
    }
}

// MARK: - Weather: data (Open-Meteo, free, no account needed)

struct CurrentConditions {
    let temperature: Double
    let feelsLike: Double
    let humidity: Double
    let code: Int
    let windSpeed: Double
    let windDirection: Double
    let gusts: Double
    let precipitation: Double
}

struct DayForecast: Identifiable {
    let id: String            // yyyy-MM-dd
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    let rainChance: Int?
    let rainTotal: Double
    let windMax: Double
    let gustMax: Double
    let windDirection: Double
    let uv: Double?
}

struct Forecast {
    let current: CurrentConditions
    let days: [DayForecast]
}

enum WeatherService {
    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let relative_humidity_2m: Double
            let weather_code: Int
            let wind_speed_10m: Double
            let wind_direction_10m: Double
            let wind_gusts_10m: Double
            let precipitation: Double
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_sum: [Double?]
            let precipitation_probability_max: [Double?]
            let wind_speed_10m_max: [Double?]
            let wind_gusts_10m_max: [Double?]
            let wind_direction_10m_dominant: [Double?]
            let uv_index_max: [Double?]
        }
        let timezone: String
        let current: Current
        let daily: Daily
    }

    static func fetch(latitude: Double, longitude: Double) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant,uv_index_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7"),
            .init(name: "wind_speed_unit", value: "kmh")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        let r = try JSONDecoder().decode(Response.self, from: data)

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: r.timezone) ?? .current

        let d = r.daily
        let days: [DayForecast] = d.time.indices.compactMap { i in
            guard let date = parser.date(from: d.time[i]),
                  let high = d.temperature_2m_max[i], let low = d.temperature_2m_min[i] else { return nil }
            return DayForecast(
                id: d.time[i], date: date,
                code: d.weather_code[i] ?? 3,
                high: high, low: low,
                rainChance: d.precipitation_probability_max[i].map { Int($0.rounded()) },
                rainTotal: d.precipitation_sum[i] ?? 0,
                windMax: d.wind_speed_10m_max[i] ?? 0,
                gustMax: d.wind_gusts_10m_max[i] ?? 0,
                windDirection: d.wind_direction_10m_dominant[i] ?? 0,
                uv: d.uv_index_max[i])
        }

        let c = r.current
        return Forecast(
            current: CurrentConditions(
                temperature: c.temperature_2m, feelsLike: c.apparent_temperature,
                humidity: c.relative_humidity_2m, code: c.weather_code,
                windSpeed: c.wind_speed_10m, windDirection: c.wind_direction_10m,
                gusts: c.wind_gusts_10m, precipitation: c.precipitation),
            days: days)
    }
}

// MARK: - Weather: screen

struct WeatherView: View {
    @Query private var profiles: [UserProfile]
    @State private var forecast: Forecast?
    @State private var errorMessage: String?
    @State private var loadedKey: String?
    @State private var loadedAt: Date?
    @State private var expandedDay: String?
    @State private var showingProfile = false
    @State private var mode = "forecast"

    var body: some View {
        VStack(spacing: 0) {   // sits inside its category tab's NavigationStack
            MonoSegment(options: [("forecast", "Forecast"), ("surf", "Surf")], selection: $mode)
                .padding(.horizontal)
                .padding(.bottom, 8)
            if mode == "surf" {
                SurfView()
            } else {
                forecastSection
            }
        }
    }

    private var forecastSection: some View {
        Group {
            Group {
                if let profile = profiles.first, let lat = profile.latitude, let lon = profile.longitude {
                    if AustraliaRegion.contains(latitude: lat, longitude: lon) {
                        forecastView(place: profile.placeName, lat: lat, lon: lon)
                    } else {
                        ContentUnavailableView {
                            Label("Australia only", systemImage: "globe.asia.australia")
                        } description: {
                            Text("The forecast is available for Australian locations. Choose an Australian town or suburb in your profile.")
                        } actions: {
                            Button("Change location") { showingProfile = true }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Set your location", systemImage: "location.slash")
                    } description: {
                        Text("Add your town or suburb to see the weekly forecast.")
                    } actions: {
                        Button("Set location") { showingProfile = true }
                    }
                }
            }
            .sheet(isPresented: $showingProfile) { ProfileView().tint(.primary) }
        }
    }

    private func forecastView(place: String, lat: Double, lon: Double) -> some View {
        let key = "\(lat),\(lon)"
        return ScrollView {
            VStack(spacing: 16) {
                if let forecast {
                    currentCard(forecast.current, place: place)
                    weekCard(forecast.days)
                    Text("Weather data by Open-Meteo.com")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let errorMessage {
                    ContentUnavailableView("Forecast unavailable", systemImage: "cloud.slash",
                                           description: Text(errorMessage))
                        .padding(.top, 60)
                } else {
                    ProgressView("Loading forecast…").padding(.top, 80)
                }
            }
            .padding()
        }
        .refreshable { await load(lat: lat, lon: lon, key: key, force: true) }
        .task(id: key) { await load(lat: lat, lon: lon, key: key) }
    }

    private func load(lat: Double, lon: Double, key: String, force: Bool = false) async {
        // Reuse a forecast fetched in the last 15 minutes when just switching tabs
        if !force, loadedKey == key, let loadedAt, Date.now.timeIntervalSince(loadedAt) < 900 { return }
        if loadedKey != key { forecast = nil }
        errorMessage = nil
        do {
            forecast = try await WeatherService.fetch(latitude: lat, longitude: lon)
            loadedKey = key
            loadedAt = .now
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if forecast == nil {
                errorMessage = "Couldn't load the forecast. Check your connection and pull down to try again."
            }
        }
    }

    // Current conditions

    private func currentCard(_ c: CurrentConditions, place: String) -> some View {
        let info = WeatherCode.describe(c.code)
        return VStack(alignment: .leading, spacing: 14) {
            Label(place.isEmpty ? "Your location" : place, systemImage: "location.fill")
                .font(.subheadline.weight(.medium))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(c.temperature.rounded()))°")
                        .font(.system(size: 72, weight: .thin))
                    Text(info.text).font(.title3)
                    Text("Feels like \(Int(c.feelsLike.rounded()))°")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: info.symbol)
                    .font(.system(size: 56, weight: .light))
                    .symbolRenderingMode(.monochrome)
            }

            Divider()

            HStack(alignment: .top) {
                metric("Wind", "\(Compass.label(c.windDirection)) \(Int(c.windSpeed.rounded())) km/h", arrow: c.windDirection)
                Spacer()
                metric("Gusts", "\(Int(c.gusts.rounded())) km/h")
                Spacer()
                metric("Rain", String(format: "%.1f mm", c.precipitation))
                Spacer()
                metric("Humidity", "\(Int(c.humidity.rounded()))%")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
    }

    private func metric(_ label: String, _ value: String, arrow: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                if let arrow { WindArrow(degrees: arrow) }
                Text(value).font(.subheadline.weight(.medium))
            }
        }
    }

    // 7-day forecast

    private func weekCard(_ days: [DayForecast]) -> some View {
        let weekLow = days.map(\.low).min() ?? 0
        let weekHigh = days.map(\.high).max() ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            Label("7-day forecast", systemImage: "calendar")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index > 0 { Divider() }
                dayRow(day, isToday: index == 0, weekLow: weekLow, weekHigh: weekHigh)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
    }

    private func dayRow(_ day: DayForecast, isToday: Bool, weekLow: Double, weekHigh: Double) -> some View {
        let info = WeatherCode.describe(day.code)
        let expanded = expandedDay == day.id
        let chance = day.rainChance ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.body.weight(.medium))
                    .frame(width: 52, alignment: .leading)
                Image(systemName: info.symbol)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 26)
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill").font(.caption2)
                    Text("\(chance)%").font(.caption.monospacedDigit())
                }
                .foregroundStyle(chance >= 30 ? Color.primary : Color.secondary)
                .frame(width: 44, alignment: .leading)
                Text("\(Int(day.low.rounded()))°")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                TempRangeBar(low: day.low, high: day.high, weekLow: weekLow, weekHigh: weekHigh)
                Text("\(Int(day.high.rounded()))°")
                    .frame(width: 30, alignment: .leading)
            }

            // Wind and rain summary under each day
            HStack(spacing: 6) {
                Image(systemName: "wind")
                WindArrow(degrees: day.windDirection)
                Text("\(Compass.label(day.windDirection)) \(Int(day.windMax.rounded())) km/h")
                Text("·")
                Image(systemName: "drop")
                Text(day.rainTotal < 0.1 ? "0 mm" : String(format: "%.1f mm", day.rainTotal))
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 62)

            if expanded {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { detail("Conditions", info.text); detail("Rain chance", "\(chance)%") }
                    GridRow { detail("Wind gusts", "\(Int(day.gustMax.rounded())) km/h"); detail("UV index", uvLabel(day.uv)) }
                }
                .padding(.leading, 62)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { expandedDay = expanded ? nil : day.id }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.medium))
        }
    }

    private func uvLabel(_ uv: Double?) -> String {
        guard let uv else { return "–" }
        let level: String
        switch uv {
        case ..<3: level = "Low"
        case ..<6: level = "Moderate"
        case ..<8: level = "High"
        case ..<11: level = "Very high"
        default: level = "Extreme"
        }
        return "\(Int(uv.rounded())) \(level)"
    }
}

/// Arrow pointing the way the wind is blowing (wind direction is where it comes *from*).
struct WindArrow: View {
    let degrees: Double
    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 9))
            .rotationEffect(.degrees(degrees + 180))
    }
}

/// Bar showing a day's low-to-high range against the whole week's range.
struct TempRangeBar: View {
    let low: Double
    let high: Double
    let weekLow: Double
    let weekHigh: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(weekHigh - weekLow, 1)
            let start = (low - weekLow) / span * geo.size.width
            let width = max((high - low) / span * geo.size.width, 6)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.primary)
                    .frame(width: width)
                    .offset(x: start)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Markets: data

enum QuoteKind: String { case index, fx, commodity, stock, crypto }

struct Quote: Identifiable {
    let id: String
    let name: String
    let symbol: String          // shown under the name, e.g. "BHP", "AXJO", "BTC"
    let kind: QuoteKind
    let price: Double
    let changePercent: Double
    let currency: String
    let sparkline: [Double]
    let link: URL?
    var open: Double? = nil
    var high: Double? = nil
    var low: Double? = nil
    var previousClose: Double? = nil
    var volume: Double? = nil
    var marketCap: Double? = nil
    var exchange: String? = nil
    var baseline: Double? = nil      // dotted line on the chart: previous close (shares) or price 7 days ago (crypto)
}

enum MarketLists {
    // (Yahoo symbol, display name, kind)
    static let global: [(String, String, QuoteKind)] = [
        ("^GSPC", "S&P 500", .index),
        ("^DJI", "Dow Jones", .index),
        ("^IXIC", "Nasdaq", .index),
        ("^FTSE", "FTSE 100", .index),
        ("^GDAXI", "DAX", .index),
        ("^N225", "Nikkei 225", .index),
        ("^HSI", "Hang Seng", .index),
        ("AUDUSD=X", "AUD/USD", .fx),
        ("GC=F", "Gold", .commodity)
    ]

    static let asx: [(String, String, QuoteKind)] = [
        ("^AXJO", "S&P/ASX 200", .index),
        ("^AORD", "All Ordinaries", .index),
        ("BHP.AX", "BHP Group", .stock),
        ("CBA.AX", "Commonwealth Bank", .stock),
        ("CSL.AX", "CSL", .stock),
        ("NAB.AX", "NAB", .stock),
        ("WBC.AX", "Westpac", .stock),
        ("ANZ.AX", "ANZ", .stock),
        ("MQG.AX", "Macquarie Group", .stock),
        ("WES.AX", "Wesfarmers", .stock),
        ("FMG.AX", "Fortescue", .stock),
        ("WDS.AX", "Woodside Energy", .stock)
    ]
}

enum MarketError: Error { case busy, failed }

/// Index and share prices from Yahoo Finance's public chart data (prices may be delayed ~20 minutes).
enum StockService {
    private struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable { let meta: Meta; let indicators: Indicators? }
        struct Meta: Decodable {
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
            let currency: String?
            let regularMarketDayHigh: Double?
            let regularMarketDayLow: Double?
            let regularMarketVolume: Double?
            let exchangeName: String?
            let fullExchangeName: String?
        }
        struct Indicators: Decodable { let quote: [QuoteData]? }
        struct QuoteData: Decodable {
            let close: [Double?]?
            let open: [Double?]?
            let high: [Double?]?
            let low: [Double?]?
            let volume: [Double?]?
        }
        let chart: Chart
    }

    private static func exchangeLabel(_ symbol: String, _ meta: ChartResponse.Meta) -> String? {
        if symbol.hasSuffix(".AX") || symbol == "^AXJO" || symbol == "^AORD" { return "ASX" }
        if symbol.hasSuffix("=X") { return "FX" }
        return meta.fullExchangeName ?? meta.exchangeName
    }

    static func fetch(symbol: String, name: String, kind: QuoteKind) async -> Quote? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: ".-="))),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=5m")
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let result = decoded.chart.result?.first,
              let price = result.meta.regularMarketPrice
        else { return nil }

        let previous = result.meta.chartPreviousClose ?? result.meta.previousClose ?? price
        let bars = result.indicators?.quote?.first
        let closes = (bars?.close ?? []).compactMap { $0 }
        let highs = (bars?.high ?? []).compactMap { $0 }
        let lows = (bars?.low ?? []).compactMap { $0 }
        let volumes = (bars?.volume ?? []).compactMap { $0 }
        let display = symbol.replacingOccurrences(of: "^", with: "")
                            .replacingOccurrences(of: ".AX", with: "")
                            .replacingOccurrences(of: "=X", with: "")
                            .replacingOccurrences(of: "=F", with: "")
        return Quote(id: symbol, name: name, symbol: display, kind: kind,
                     price: price,
                     changePercent: previous == 0 ? 0 : (price - previous) / previous * 100,
                     currency: result.meta.currency ?? "AUD",
                     sparkline: closes,
                     link: URL(string: "https://finance.yahoo.com/quote/\(encoded)"),
                     open: (bars?.open ?? []).compactMap { $0 }.first,
                     high: result.meta.regularMarketDayHigh ?? highs.max(),
                     low: result.meta.regularMarketDayLow ?? lows.min(),
                     previousClose: previous,
                     volume: result.meta.regularMarketVolume ?? (volumes.isEmpty ? nil : volumes.reduce(0, +)),
                     exchange: exchangeLabel(symbol, result.meta),
                     baseline: previous)
    }

    /// Fetches a whole list at once and keeps the list's order.
    static func fetchAll(_ list: [(String, String, QuoteKind)]) async throws -> [Quote] {
        let found = await withTaskGroup(of: Quote?.self) { group in
            for (symbol, name, kind) in list {
                group.addTask { await fetch(symbol: symbol, name: name, kind: kind) }
            }
            var byID: [String: Quote] = [:]
            for await quote in group { if let quote { byID[quote.id] = quote } }
            return byID
        }
        let ordered = list.compactMap { found[$0.0] }
        if ordered.isEmpty { throw MarketError.failed }
        return ordered
    }
}

/// Top cryptocurrencies by market cap, priced in AUD, from CoinGecko's free keyless API.
enum CryptoService {
    private struct Coin: Decodable {
        struct Sparkline: Decodable { let price: [Double]? }
        let id: String
        let symbol: String
        let name: String
        let current_price: Double?
        let price_change_percentage_24h: Double?
        let sparkline_in_7d: Sparkline?
        let high_24h: Double?
        let low_24h: Double?
        let total_volume: Double?
        let market_cap: Double?
        let market_cap_rank: Int?
    }

    static func fetch() async throws -> [Quote] {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            .init(name: "vs_currency", value: "aud"),
            .init(name: "order", value: "market_cap_desc"),
            .init(name: "per_page", value: "20"),
            .init(name: "page", value: "1"),
            .init(name: "sparkline", value: "true"),
            .init(name: "price_change_percentage", value: "24h")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 429 { throw MarketError.busy }
        let coins = try JSONDecoder().decode([Coin].self, from: data)
        return coins.compactMap { coin in
            guard let price = coin.current_price else { return nil }
            return Quote(id: coin.id, name: coin.name, symbol: coin.symbol.uppercased(), kind: .crypto,
                         price: price, changePercent: coin.price_change_percentage_24h ?? 0,
                         currency: "AUD", sparkline: coin.sparkline_in_7d?.price ?? [],
                         link: URL(string: "https://www.coingecko.com/en/coins/\(coin.id)"),
                         high: coin.high_24h, low: coin.low_24h,
                         volume: coin.total_volume, marketCap: coin.market_cap,
                         exchange: coin.market_cap_rank.map { "Rank #\($0)" },
                         baseline: coin.sparkline_in_7d?.price?.first)
        }
    }
}

// MARK: - Markets: screen

enum MarketSection: String, CaseIterable, Identifiable {
    case global = "Global"
    case asx = "ASX"
    case crypto = "Crypto"
    var id: Self { self }
}

struct MarketsView: View {
    @State private var section: MarketSection = .asx
    @State private var quotes: [MarketSection: [Quote]] = [:]
    @State private var updated: [MarketSection: Date] = [:]
    @State private var errors: [MarketSection: String] = [:]
    @State private var showingWatchlist = false

    var body: some View {
        Group {   // sits inside its category tab's NavigationStack
            VStack(spacing: 0) {
                MonoSegment(options: MarketSection.allCases.map { ($0, $0.rawValue) }, selection: $section)
                .padding(.horizontal)
                .padding(.bottom, 8)

                List {
                    Section {
                        if let list = quotes[section], !list.isEmpty {
                            ForEach(list) { quote in
                                Group {
                                    if let link = quote.link {
                                        Link(destination: link) { QuoteCard(quote: quote) }
                                            .foregroundStyle(.primary)
                                    } else {
                                        QuoteCard(quote: quote)
                                    }
                                }
                                .cardRow()
                            }
                        } else if let error = errors[section] {
                            ContentUnavailableView("Prices unavailable", systemImage: "chart.line.downtrend.xyaxis",
                                                   description: Text(error))
                        } else {
                            HStack { Spacer(); ProgressView("Loading prices…"); Spacer() }
                                .padding(.vertical, 40)
                        }
                    } header: {
                        if let time = updated[section] {
                            Text("Updated \(time.formatted(date: .omitted, time: .shortened))")
                        }
                    } footer: {
                        Text(section == .crypto
                             ? "Prices in AUD · 7-day trend · Data provided by CoinGecko"
                             : "Today's trend · dotted line is yesterday's close · Prices may be delayed · Data from Yahoo Finance")
                    }
                }
                .listStyle(.insetGrouped)
                .listRowSpacing(8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingWatchlist = true } label: { Label("Watchlist", systemImage: "star").labelStyle(.titleAndIcon) }
                        .buttonStyle(CapsuleButtonStyle(kind: .outlined))
                }
            }
            .sheet(isPresented: $showingWatchlist) { WatchlistView().tint(.primary) }
            .refreshable { await load(section, force: true) }
            .task(id: section) { await load(section) }
        }
    }

    private func load(_ section: MarketSection, force: Bool = false) async {
        // Don't refetch when just flicking between sections
        let maxAge: TimeInterval = section == .crypto ? 120 : 60
        if !force, let last = updated[section], Date.now.timeIntervalSince(last) < maxAge { return }
        errors[section] = nil
        do {
            let result: [Quote]
            switch section {
            case .global: result = try await StockService.fetchAll(MarketLists.global)
            case .asx: result = try await StockService.fetchAll(MarketLists.asx)
            case .crypto: result = try await CryptoService.fetch()
            }
            quotes[section] = result
            updated[section] = .now
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            guard quotes[section]?.isEmpty ?? true else { return }   // keep showing older prices if we have them
            errors[section] = (error as? MarketError) == .busy
                ? "CoinGecko is busy right now. Wait a minute, then pull down to try again."
                : "Couldn't load prices. Check your connection and pull down to try again."
        }
    }
}

/// Market card (design B): name and exchange top left, ticker over price top right,
/// a wide chart with a dotted line at the previous close, then four figures.
struct QuoteCard: View {
    let quote: Quote

    private var kindLabel: String {
        switch quote.kind {
        case .index: return "Index"
        case .fx: return "Currency"
        case .commodity: return "Commodity"
        case .stock: return "Share"
        case .crypto: return "Crypto"
        }
    }

    private var subtitle: String {
        var parts = [quote.exchange, kindLabel].compactMap { $0 }
        if quote.kind == .stock, let v = quote.volume { parts.append("Vol \(compact(v))") }
        return parts.joined(separator: " · ")
    }

    private var figures: [(String, String)] {
        let p: (Double?) -> String = { v in v.map { formatPrice($0, kind: quote.kind, currency: quote.currency) } ?? "–" }
        if quote.kind == .crypto {
            return [("24h high", p(quote.high)), ("24h low", p(quote.low)),
                    ("Volume", quote.volume.map { "$" + compact($0) } ?? "–"),
                    ("Mkt cap", quote.marketCap.map { "$" + compact($0) } ?? "–")]
        }
        return [("Open", p(quote.open)), ("High", p(quote.high)), ("Low", p(quote.low)), ("Prev close", p(quote.previousClose))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quote.name)
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(quote.symbol)
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(formatPrice(quote.price, kind: quote.kind, currency: quote.currency))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    ChangeBadge(percent: quote.changePercent)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Sparkline(values: quote.sparkline, baseline: quote.baseline, filled: true)
                .frame(height: 48)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                ForEach(figures.indices, id: \.self) { i in
                    let item = figures[i]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.caption2).foregroundStyle(.secondary)
                        Text(item.1)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(1)))
    }
}

extension View {
    /// Lets a card sit on the list background as its own rounded tile.
    func cardRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Black-and-white change indicator: solid for up, outlined for down.
struct ChangeBadge: View {
    let percent: Double

    var body: some View {
        let up = percent >= 0
        Text("\(up ? "▲" : "▼") \(abs(percent).formatted(.number.precision(.fractionLength(2))))%")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(up ? Color(.systemBackground) : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(up ? Color.primary : Color.clear))
            .overlay(Capsule().stroke(Color.primary, lineWidth: up ? 0 : 1))
    }
}

/// Line chart of recent prices, with an optional dotted reference line and soft fill.
struct Sparkline: View {
    let values: [Double]
    var baseline: Double? = nil
    var filled = false

    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let vMin = values.min(), let vMax = values.max() {
                let low = min(vMin, baseline ?? vMin)
                let high = max(vMax, baseline ?? vMax)
                let range = max(high - low, .ulpOfOne)
                let w = geo.size.width
                let h = geo.size.height
                let point: (Int) -> CGPoint = { i in
                    CGPoint(x: w * CGFloat(i) / CGFloat(values.count - 1),
                            y: 2 + (h - 4) * (1 - CGFloat((values[i] - low) / range)))
                }
                let line = Path { path in
                    for i in values.indices {
                        if i == 0 { path.move(to: point(i)) } else { path.addLine(to: point(i)) }
                    }
                }
                ZStack(alignment: .topLeading) {
                    if filled {
                        Path { path in
                            path.addPath(line)
                            path.addLine(to: CGPoint(x: w, y: h))
                            path.addLine(to: CGPoint(x: 0, y: h))
                            path.closeSubpath()
                        }
                        .fill(Color.primary.opacity(0.07))
                    }
                    if let baseline {
                        let y = 2 + (h - 4) * (1 - CGFloat((baseline - low) / range))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    }
                    line.stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    let end = point(values.count - 1)
                    Circle().fill(Color.primary).frame(width: 5, height: 5)
                        .position(end)
                }
            }
        }
    }
}

// MARK: - Day screen: weather for one date (temperature and rain)

struct DayWeather {
    let high: Double
    let low: Double
    let rain: Double
    let rainChance: Int?
    let isForecast: Bool
}

enum DayWeatherService {
    private struct Response: Decodable {
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_sum: [Double?]
            let precipitation_probability_max: [Double?]?
        }
        let daily: Daily
    }

    /// Recent past and the next 15 days come from the forecast API; older dates come from the historical archive.
    /// Returns nil when the date is too far in the future to forecast.
    static func fetch(latitude: Double, longitude: Double, day: Date) async throws -> DayWeather? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let offset = cal.dateComponents([.day], from: today, to: day).day ?? 0
        guard offset <= 15 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = formatter.string(from: day)

        let useArchive = offset < -60
        var daily = "temperature_2m_max,temperature_2m_min,precipitation_sum"
        if !useArchive { daily += ",precipitation_probability_max" }

        var components = URLComponents(string: useArchive
            ? "https://archive-api.open-meteo.com/v1/archive"
            : "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "daily", value: daily),
            .init(name: "start_date", value: date),
            .init(name: "end_date", value: date),
            .init(name: "timezone", value: "auto")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        let d = try JSONDecoder().decode(Response.self, from: data).daily
        guard let high = d.temperature_2m_max.first ?? nil,
              let low = d.temperature_2m_min.first ?? nil else { throw MarketError.failed }
        return DayWeather(high: high, low: low,
                          rain: (d.precipitation_sum.first ?? nil) ?? 0,
                          rainChance: (d.precipitation_probability_max?.first ?? nil).map { Int($0.rounded()) },
                          isForecast: offset >= 0)
    }
}

// MARK: - Day screen: market report for one date (closing prices)

struct DayMarket: Identifiable {
    let id: String
    let name: String
    let kind: QuoteKind
    let close: Double
    let changePercent: Double
    let currency: String
    let tradingDay: Date
    let isSameDay: Bool        // false when the market was closed and the last close is shown instead
    let link: URL?
}

enum DayMarketService {
    static let symbols: [(String, String, QuoteKind)] = [
        ("^AXJO", "S&P/ASX 200", .index),
        ("^AORD", "All Ordinaries", .index),
        ("^GSPC", "S&P 500", .index),
        ("AUDUSD=X", "AUD/USD", .fx),
        ("BTC-AUD", "Bitcoin", .crypto),
        ("ETH-AUD", "Ethereum", .crypto)
    ]

    private struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable { let meta: Meta; let timestamp: [Int]?; let indicators: Indicators? }
        struct Meta: Decodable { let currency: String?; let exchangeTimezoneName: String? }
        struct Indicators: Decodable { let quote: [QuoteData]? }
        struct QuoteData: Decodable { let close: [Double?]? }
        let chart: Chart
    }

    static func fetch(symbol: String, name: String, kind: QuoteKind, day: Date) async -> DayMarket? {
        let cal = Calendar.current
        guard let from = cal.date(byAdding: .day, value: -10, to: day),
              let to = cal.date(byAdding: .day, value: 2, to: day),
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: ".-="))),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?period1=\(Int(from.timeIntervalSince1970))&period2=\(Int(min(to, .now).timeIntervalSince1970))&interval=1d")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let result = try? JSONDecoder().decode(ChartResponse.self, from: data).chart.result?.first,
              let stamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close
        else { return nil }

        // Compare dates as yyyy-MM-dd: the trading day in the exchange's time zone vs the chosen day locally
        let exchangeDay = DateFormatter()
        exchangeDay.dateFormat = "yyyy-MM-dd"
        exchangeDay.locale = Locale(identifier: "en_US_POSIX")
        exchangeDay.timeZone = result.meta.exchangeTimezoneName.flatMap(TimeZone.init(identifier:)) ?? .current
        let localDay = DateFormatter()
        localDay.dateFormat = "yyyy-MM-dd"
        localDay.locale = Locale(identifier: "en_US_POSIX")
        let target = localDay.string(from: day)

        let bars: [(day: String, date: Date, close: Double)] = zip(stamps, closes).compactMap { stamp, close in
            guard let close else { return nil }
            let date = Date(timeIntervalSince1970: TimeInterval(stamp))
            return (exchangeDay.string(from: date), date, close)
        }
        guard let index = bars.lastIndex(where: { $0.day <= target }) else { return nil }
        let bar = bars[index]
        let previous = index > 0 ? bars[index - 1].close : bar.close

        return DayMarket(id: symbol, name: name, kind: kind, close: bar.close,
                         changePercent: previous == 0 ? 0 : (bar.close - previous) / previous * 100,
                         currency: result.meta.currency ?? "AUD",
                         tradingDay: bar.date, isSameDay: bar.day == target,
                         link: URL(string: "https://finance.yahoo.com/quote/\(encoded)"))
    }

    static func fetchAll(day: Date, symbols list: [(String, String, QuoteKind)]) async -> [DayMarket] {
        let found = await withTaskGroup(of: DayMarket?.self) { group in
            for (symbol, name, kind) in list {
                group.addTask { await fetch(symbol: symbol, name: name, kind: kind, day: day) }
            }
            var byID: [String: DayMarket] = [:]
            for await item in group { if let item { byID[item.id] = item } }
            return byID
        }
        return list.compactMap { found[$0.0] }
    }
}

func formatPrice(_ price: Double, kind: QuoteKind, currency: String) -> String {
    switch kind {
    case .index: return price.formatted(.number.precision(.fractionLength(2)))
    case .fx: return price.formatted(.number.precision(.fractionLength(4)))
    case .stock, .commodity, .crypto:
        return price.formatted(.currency(code: currency).precision(.fractionLength(price < 1 ? 4 : 2)))
    }
}

// MARK: - Day screen

/// Rounded section card used on the day screen (same style as the Weather tab).
struct DayCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, systemImage: String,
         @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
    }
}

extension DayCard where Accessory == EmptyView {
    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Markets: watchlist

@Model
final class WatchItem {
    var symbol: String          // Yahoo Finance symbol, e.g. "TLS.AX", "^GSPC", "BTC-AUD"
    var name: String
    var kindRaw: String
    var addedAt: Date

    var quoteKind: QuoteKind { QuoteKind(rawValue: kindRaw) ?? .stock }

    init(symbol: String, name: String, kind: QuoteKind, addedAt: Date = .now) {
        self.symbol = symbol
        self.name = name
        self.kindRaw = kind.rawValue
        self.addedAt = addedAt
    }
}

struct FavouriteGroup {
    let title: String
    let items: [(String, String, QuoteKind)]
}

extension MarketLists {
    /// Choices offered in the Favourites dropdown.
    static let favourites: [FavouriteGroup] = [
        FavouriteGroup(title: "ASX", items: asx + [
            ("RIO.AX", "Rio Tinto", .stock),
            ("TLS.AX", "Telstra", .stock),
            ("WOW.AX", "Woolworths", .stock),
            ("COL.AX", "Coles", .stock),
            ("QAN.AX", "Qantas", .stock),
            ("XRO.AX", "Xero", .stock)
        ]),
        FavouriteGroup(title: "Global", items: global + [
            ("AAPL", "Apple", .stock),
            ("MSFT", "Microsoft", .stock),
            ("NVDA", "Nvidia", .stock),
            ("AMZN", "Amazon", .stock),
            ("GOOGL", "Alphabet", .stock),
            ("TSLA", "Tesla", .stock)
        ]),
        FavouriteGroup(title: "Crypto", items: [
            ("BTC-AUD", "Bitcoin", .crypto),
            ("ETH-AUD", "Ethereum", .crypto),
            ("SOL-AUD", "Solana", .crypto),
            ("XRP-AUD", "XRP", .crypto),
            ("ADA-AUD", "Cardano", .crypto),
            ("DOGE-AUD", "Dogecoin", .crypto)
        ])
    ]
}

/// Checks a typed ticker against Yahoo Finance and returns its proper symbol, name and type.
enum TickerLookup {
    private struct Response: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable { let meta: Meta }
        struct Meta: Decodable {
            let symbol: String?
            let shortName: String?
            let longName: String?
            let instrumentType: String?
            let regularMarketPrice: Double?
        }
        let chart: Chart
    }

    static func find(_ raw: String) async -> (symbol: String, name: String, kind: QuoteKind)? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return nil }
        // Plain codes like "TLS" are tried on the ASX first, then as-is (e.g. "AAPL")
        let isPlain = !cleaned.contains(".") && !cleaned.contains("-") && !cleaned.contains("=") && !cleaned.hasPrefix("^")
        let candidates = isPlain ? [cleaned + ".AX", cleaned] : [cleaned]
        for candidate in candidates {
            if let hit = await lookup(candidate) { return hit }
        }
        return nil
    }

    private static func lookup(_ symbol: String) async -> (symbol: String, name: String, kind: QuoteKind)? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: ".-="))),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=1d")
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let meta = try? JSONDecoder().decode(Response.self, from: data).chart.result?.first?.meta,
              meta.regularMarketPrice != nil
        else { return nil }

        let kind: QuoteKind
        switch meta.instrumentType {
        case "INDEX": kind = .index
        case "CURRENCY": kind = .fx
        case "CRYPTOCURRENCY": kind = .crypto
        case "FUTURE": kind = .commodity
        default: kind = .stock
        }
        return (meta.symbol ?? symbol, meta.shortName ?? meta.longName ?? symbol, kind)
    }
}

struct WatchlistView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WatchItem.addedAt) private var items: [WatchItem]

    @State private var ticker = ""
    @State private var error: String?
    @State private var isChecking = false
    @State private var quotes: [String: Quote] = [:]
    @State private var favOpen = false
    @FocusState private var tickerFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                // Add bar: Favourites dropdown, then ticker box + Add
                Section {
                    VStack(spacing: 8) {
                        favouritesMenu
                        HStack(spacing: 8) {
                            TextField("Ticker e.g. TLS.AX", text: $ticker)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($tickerFocused)
                                .onSubmit { Task { await addCustom() } }
                                .onChange(of: ticker) { error = nil }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.4)))
                            Button {
                                Task { await addCustom() }
                            } label: {
                                Group {
                                    if isChecking { ProgressView().tint(Color(.systemBackground)) } else { Text("Add") }
                                }
                                .font(.headline)
                                .foregroundStyle(Color(.systemBackground))
                                .frame(width: 64, height: 40)
                                .background(Color.primary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section {
                    if items.isEmpty {
                        Text("Nothing here yet. Pick a favourite or type a ticker above.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in watchRow(item) }
                        .onDelete { offsets in
                            for index in offsets { context.delete(items[index]) }
                        }
                } footer: {
                    if !items.isEmpty {
                        Text("Swipe left to remove · Your watchlist is what's recorded on each day in the calendar · Prices may be delayed · Data from Yahoo Finance")
                    }
                }
            }
            .listRowSpacing(8)
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle()) }
            }
            .refreshable { await loadPrices() }
            .task(id: items.map(\.symbol)) { await loadPrices() }
        }
    }

    private var favouritesMenu: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { favOpen.toggle() }
            } label: {
                HStack {
                    Text("Favourites").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(favOpen ? 180 : 0))
                }
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.primary))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(favOpen ? "Hide favourites" : "Show favourites")

            if favOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MarketLists.favourites, id: \.title) { group in
                        Text(group.title.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(group.items, id: \.0) { option in
                            Divider()
                            Button {
                                add(symbol: option.0, name: option.1, kind: option.2)
                            } label: {
                                HStack {
                                    Text(option.1).fontWeight(contains(option.0) ? .bold : .medium)
                                    Spacer()
                                    if contains(option.0) { Image(systemName: "checkmark") }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary, lineWidth: 1.5))
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func watchRow(_ item: WatchItem) -> some View {
        Group {
            if let quote = quotes[item.symbol] {
                if let link = quote.link {
                    Link(destination: link) { QuoteCard(quote: quote) }
                        .foregroundStyle(.primary)
                } else {
                    QuoteCard(quote: quote)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.headline).lineLimit(1)
                        Text(item.symbol).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
        .cardRow()
    }

    private func contains(_ symbol: String) -> Bool {
        items.contains { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
    }

    private func add(symbol: String, name: String, kind: QuoteKind) {
        guard !contains(symbol) else {
            error = "\(name) is already on your watchlist."
            return
        }
        error = nil
        withAnimation { context.insert(WatchItem(symbol: symbol, name: name, kind: kind)) }
    }

    private func addCustom() async {
        let typed = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            error = "Type a ticker first, e.g. TLS.AX for Telstra."
            return
        }
        isChecking = true
        defer { isChecking = false }
        guard let hit = await TickerLookup.find(typed) else {
            error = "Couldn't find \"\(typed.uppercased())\". ASX shares end in .AX (TLS.AX), crypto in -AUD (SOL-AUD)."
            return
        }
        add(symbol: hit.symbol, name: hit.name, kind: hit.kind)
        if error == nil {
            ticker = ""
            tickerFocused = false
        }
    }

    private func loadPrices() async {
        let list = items.map { ($0.symbol, $0.name, $0.quoteKind) }
        guard !list.isEmpty else { quotes = [:]; return }
        let result = (try? await StockService.fetchAll(list)) ?? []
        quotes = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Category tabs (five tabs, segmented sub-tabs on top)

protocol TabSection: CaseIterable, Hashable, Identifiable, RawRepresentable
    where RawValue == String, AllCases: RandomAccessCollection {}

enum JournalSection: String, TabSection {
    case entries = "Entries", notes = "Notes", reminders = "Reminders"
    var id: Self { self }
}
enum ReportsSection: String, TabSection {
    case weather = "Weather", markets = "Markets", news = "News"
    var id: Self { self }
}
enum HealthSection: String, TabSection {
    case diet = "Diet", sleep = "Sleep"
    var id: Self { self }
}
enum FinanceSection: String, TabSection {
    case savings = "Savings", goals = "Goals", expenses = "Expenses"
    var id: Self { self }
}

struct SectionPicker<S: TabSection>: View {
    @Binding var selection: S

    var body: some View {
        MonoSegment(options: S.allCases.map { ($0, $0.rawValue) }, selection: $selection)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct JournalTab: View {
    @State private var section: JournalSection = .entries
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionPicker(selection: $section)
                switch section {
                case .entries: EntryListView()
                case .notes: NotesView()
                case .reminders: RemindersView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Journal")
        }
    }
}

struct ReportsTab: View {
    @State private var section: ReportsSection = .weather
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionPicker(selection: $section)
                switch section {
                case .weather: WeatherView()
                case .markets: MarketsView()
                case .news: NewsView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
        }
    }
}

struct HealthTab: View {
    @State private var section: HealthSection = .diet
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionPicker(selection: $section)
                switch section {
                case .diet: DietView()
                case .sleep: SleepView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Health")
        }
    }
}

struct FinanceTab: View {
    @State private var section: FinanceSection = .savings
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SectionPicker(selection: $section)
                switch section {
                case .savings: SavingsView()
                case .goals: GoalsView()
                case .expenses: ExpensesView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Finance")
        }
    }
}

// MARK: - Shared helpers

extension Double {
    var aud: String { formatted(.currency(code: "AUD")) }
}

func countText(_ n: Int, _ singular: String, _ plural: String) -> String {
    "\(n) \(n == 1 ? singular : plural)"
}

func hoursMinutes(_ interval: TimeInterval) -> String {
    let minutes = max(Int(interval / 60), 0)
    return "\(minutes / 60)h \(minutes % 60)m"
}

func dayLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
}

/// ‹ Today › control for moving between days.
struct DayStepper: View {
    @Binding var day: Date
    private let cal = Calendar.current

    var body: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous day")
            Spacer()
            Text(dayLabel(day)).font(.headline)
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .opacity(cal.isDateInToday(day) ? 0 : 1)
                .allowsHitTesting(!cal.isDateInToday(day))
                .accessibilityLabel("Next day")
        }
        .buttonStyle(.borderless)
    }

    private func move(_ value: Int) {
        if let next = cal.date(byAdding: .day, value: value, to: day) { day = next }
    }
}

/// Big number summary card used at the top of Health and Finance sections.
struct SummaryCard<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Journal › Notes

@Model
final class Note {
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool = false

    init(title: String = "", body: String = "", createdAt: Date = .now) {
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        let firstLine = body.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? "New note" : firstLine
    }
}

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var newNote: Note?

    private var visible: [Note] {
        notes
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
            .sorted { $0.isPinned && !$1.isPinned }
    }

    var body: some View {
        List {
            ForEach(visible) { note in
                NavigationLink(value: note) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if note.isPinned { Image(systemName: "pin.fill").font(.caption) }
                            Text(note.displayTitle).font(.headline).lineLimit(1)
                        }
                        if !note.body.isEmpty {
                            Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(note.updatedAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions(edge: .leading) {
                    Button { note.isPinned.toggle() } label: {
                        Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.primary)
                }
            }
            .onDelete { offsets in
                let items = visible
                for index in offsets { context.delete(items[index]) }
            }
        }
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView("No notes yet", systemImage: "note.text",
                                       description: Text("Tap + to jot something down."))
            }
        }
        .searchable(text: $search, prompt: "Search notes")
        .navigationDestination(for: Note.self) { note in NoteEditorView(note: note) }
        .navigationDestination(item: $newNote) { note in NoteEditorView(note: note) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let note = Note()
                    context.insert(note)
                    newNote = note
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("New note")
            }
        }
    }
}

struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $note.title, axis: .vertical)
                .font(.title2.bold())
            TextEditor(text: $note.body)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if note.body.isEmpty {
                        Text("Start writing…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: note.title) { note.updatedAt = .now }
        .onChange(of: note.body) { note.updatedAt = .now }
        .onDisappear {
            // Don't keep blank notes
            if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                context.delete(note)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { note.isPinned.toggle() } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(note.isPinned ? "Unpin" : "Pin")
            }
        }
    }
}

// MARK: - Journal › Reminders

@Model
final class Reminder {
    var title: String
    var dueDate: Date?
    var notify: Bool
    var isDone: Bool
    var notificationID: String
    var createdAt: Date

    init(title: String, dueDate: Date?, notify: Bool, createdAt: Date = .now) {
        self.title = title
        self.dueDate = dueDate
        self.notify = notify
        self.isDone = false
        self.notificationID = UUID().uuidString
        self.createdAt = createdAt
    }
}

/// Schedules a phone notification at a reminder's due time (asks permission the first time).
@MainActor
enum ReminderNotifications {
    static func update(_ reminder: Reminder) async {
        let center = UNUserNotificationCenter.current()
        let id = reminder.notificationID
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard reminder.notify, !reminder.isDone, let due = reminder.dueDate, due > .now else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "Reminder · \(due.formatted(date: .omitted, time: .shortened))"
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await center.add(request)
    }

    static func cancel(_ reminder: Reminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])
    }
}

struct ReminderRow: View {
    @Bindable var reminder: Reminder

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation {
                    reminder.isDone.toggle()
                    if reminder.isDone { ReminderNotifications.cancel(reminder) }
                    else { Task { await ReminderNotifications.update(reminder) } }
                }
            } label: {
                Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(reminder.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .strikethrough(reminder.isDone)
                    .foregroundStyle(reminder.isDone ? Color.secondary : Color.primary)
                if let due = reminder.dueDate {
                    HStack(spacing: 4) {
                        if reminder.notify && !reminder.isDone { Image(systemName: "bell.fill") }
                        Text("\(dayLabel(due)), \(due.formatted(date: .omitted, time: .shortened))")
                    }
                    .font(.caption)
                    .foregroundStyle(!reminder.isDone && due < .now ? Color.primary : Color.secondary)
                    .fontWeight(!reminder.isDone && due < .now ? .semibold : .regular)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @State private var showingAdd = false
    @State private var editing: Reminder?

    private var open: [Reminder] {
        reminders.filter { !$0.isDone }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var overdue: [Reminder] { open.filter { ($0.dueDate ?? .distantFuture) < .now } }
    private var upcoming: [Reminder] { open.filter { ($0.dueDate ?? .distantFuture) >= .now } }
    private var done: [Reminder] {
        reminders.filter(\.isDone).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            section("Overdue", overdue)
            section("Upcoming", upcoming)
            section("Completed", done)
        }
        .overlay {
            if reminders.isEmpty {
                ContentUnavailableView("No reminders", systemImage: "checklist",
                                       description: Text("Tap + to add one, with an optional alert on your phone."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New reminder")
            }
        }
        .sheet(isPresented: $showingAdd) { ReminderEditor(reminder: nil).tint(.primary) }
        .sheet(item: $editing) { reminder in ReminderEditor(reminder: reminder).tint(.primary) }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Reminder]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { reminder in
                    ReminderRow(reminder: reminder)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = reminder }
                }
                .onDelete { offsets in
                    for index in offsets {
                        ReminderNotifications.cancel(items[index])
                        context.delete(items[index])
                    }
                }
            }
        }
    }
}

struct ReminderEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let reminder: Reminder?

    @State private var title = ""
    @State private var hasDate = true
    @State private var due = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
    @State private var notify = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you need to remember?", text: $title, axis: .vertical)
                        .onChange(of: title) { error = nil }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    Toggle("Due date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("When", selection: $due)
                        Toggle("Alert me on my phone", isOn: $notify)
                    }
                }
            }
            .navigationTitle(reminder == nil ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .outlined)) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(CapsuleButtonStyle()) }
            }
            .onAppear {
                guard let reminder else { return }
                title = reminder.title
                hasDate = reminder.dueDate != nil
                if let date = reminder.dueDate { due = date }
                notify = reminder.notify
            }
        }
    }

    private func save() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            error = "Give the reminder a name."
            return
        }
        let target: Reminder
        if let reminder {
            reminder.title = text
            reminder.dueDate = hasDate ? due : nil
            reminder.notify = hasDate && notify
            target = reminder
        } else {
            target = Reminder(title: text, dueDate: hasDate ? due : nil, notify: hasDate && notify)
            context.insert(target)
        }
        Task { await ReminderNotifications.update(target) }
        dismiss()
    }
}

// MARK: - Health › Diet

@Model
final class Meal {
    var name: String
    var mealType: String
    var calories: Int
    var protein: Double?
    var date: Date

    init(name: String, mealType: String, calories: Int, protein: Double?, date: Date) {
        self.name = name
        self.mealType = mealType
        self.calories = calories
        self.protein = protein
        self.date = date
    }
}

enum MealType: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snack = "Snack"
    var id: Self { self }

    static func suggested(for date: Date) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

struct DietView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \Meal.date) private var meals: [Meal]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var showingAdd = false
    @State private var showingTarget = false

    private var dayMeals: [Meal] { meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) } }
    private var total: Int { dayMeals.reduce(0) { $0 + $1.calories } }
    private var protein: Double { dayMeals.compactMap(\.protein).reduce(0, +) }
    private var target: Int { profiles.first?.calorieTarget ?? 2000 }

    var body: some View {
        List {
            Section { DayStepper(day: $day) }

            Section {
                SummaryCard("Energy") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(total.formatted()).font(.system(size: 40, weight: .thin))
                        Text("/ \(target.formatted()) kcal").foregroundStyle(.secondary)
                        Spacer()
                        Button("Target") { showingTarget = true }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.borderless)
                    }
                    ProgressView(value: min(Double(total) / Double(max(target, 1)), 1))
                        .tint(.primary)
                    HStack {
                        Text(total <= target ? "\((target - total).formatted()) kcal left" : "\((total - target).formatted()) kcal over")
                        Spacer()
                        if protein > 0 { Text("Protein \(Int(protein.rounded())) g") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if dayMeals.isEmpty {
                Section {
                    Text("No meals logged \(Calendar.current.isDateInToday(day) ? "today" : "this day"). Tap + to add one.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(MealType.allCases) { type in
                let items = dayMeals.filter { $0.mealType == type.rawValue }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { meal in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meal.name)
                                    Text(meal.date, format: .dateTime.hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(meal.calories) kcal").monospacedDigit()
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(items[index]) }
                        }
                    } header: {
                        HStack {
                            Text(type.rawValue)
                            Spacer()
                            Text("\(items.reduce(0) { $0 + $1.calories }) kcal")
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log a meal")
            }
        }
        .sheet(isPresented: $showingAdd) { AddMealSheet(day: day).tint(.primary) }
        .sheet(isPresented: $showingTarget) { CalorieTargetSheet().tint(.primary).presentationDetents([.height(260)]) }
    }
}

struct AddMealSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let day: Date

    @State private var name = ""
    @State private var type = MealType.suggested(for: .now)
    @State private var calories: Int?
    @State private var protein: Double?
    @State private var time = Date.now
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you have?", text: $name)
                    Picker("Meal", selection: $type) {
                        ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section {
                    HStack {
                        Text("Energy")
                        Spacer()
                        TextField("0", value: $calories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Protein (optional)")
                        Spacer()
                        TextField("0", value: $protein, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .onChange(of: name) { error = nil }
            .onChange(of: calories) { error = nil }
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .outlined)) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(CapsuleButtonStyle()) }
            }
        }
    }

    private func save() {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { error = "Add what you had."; return }
        guard let calories, calories > 0 else { error = "Enter the energy in kcal."; return }
        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute], from: time)
        let date = cal.date(bySettingHour: parts.hour ?? 12, minute: parts.minute ?? 0, second: 0, of: day) ?? day
        context.insert(Meal(name: text, mealType: type.rawValue, calories: calories, protein: protein, date: date))
        dismiss()
    }
}

struct CalorieTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var value = 2000

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(value.formatted()) kcal a day", value: $value, in: 1000...5000, step: 50)
                Text("Set this to suit you, or ask a GP or dietitian for a personal guide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Daily target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .outlined)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profiles.first?.calorieTarget = value
                        dismiss()
                    }
                    .buttonStyle(CapsuleButtonStyle())
                }
            }
            .onAppear { value = profiles.first?.calorieTarget ?? 2000 }
        }
    }
}

// MARK: - Health › Sleep

@Model
final class SleepLog {
    var bedtime: Date
    var wakeTime: Date
    var quality: Int          // 1–5
    var note: String
    var day: Date             // the morning you woke up

    init(bedtime: Date, wakeTime: Date, quality: Int, note: String) {
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.quality = quality
        self.note = note
        self.day = Calendar.current.startOfDay(for: wakeTime)
    }

    var duration: TimeInterval { wakeTime.timeIntervalSince(bedtime) }
}

struct QualityStars: View {
    let value: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
            }
        }
        .font(.caption2)
        .accessibilityLabel("Quality \(value) of 5")
    }
}

struct SleepView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SleepLog.wakeTime, order: .reverse) private var logs: [SleepLog]
    @State private var showingAdd = false

    private let cal = Calendar.current

    // Last 7 mornings, oldest first
    private var week: [(day: Date, hours: Double)] {
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset -> (day: Date, hours: Double)? in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let total = logs.filter { $0.day == d }.reduce(0) { $0 + $1.duration }
            return (day: d, hours: total / 3600)
        }
    }

    private var average: Double? {
        let nights = week.filter { $0.hours > 0 }
        guard !nights.isEmpty else { return nil }
        return nights.reduce(0) { $0 + $1.hours } / Double(nights.count)
    }

    var body: some View {
        List {
            Section {
                SummaryCard("Last 7 nights") {
                    if let average {
                        Text("\(hoursMinutes(average * 3600)) average")
                            .font(.system(size: 32, weight: .thin))
                    } else {
                        Text("No sleep logged this week").foregroundStyle(.secondary)
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(week, id: \.day) { item in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.hours > 0 ? Color.primary : Color.primary.opacity(0.1))
                                    .frame(height: max(CGFloat(min(item.hours, 12) / 12) * 90, 4))
                                Text(item.day.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 110, alignment: .bottom)
                }
            }

            Section("History") {
                if logs.isEmpty {
                    Text("Tap + after you wake up to log last night's sleep.")
                        .foregroundStyle(.secondary)
                }
                ForEach(logs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dayLabel(log.day)).font(.headline)
                            Text("\(log.bedtime.formatted(date: .omitted, time: .shortened)) – \(log.wakeTime.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !log.note.isEmpty {
                                Text(log.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(hoursMinutes(log.duration)).monospacedDigit()
                            QualityStars(value: log.quality)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(logs[index]) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log sleep")
            }
        }
        .sheet(isPresented: $showingAdd) { AddSleepSheet().tint(.primary) }
    }
}

struct AddSleepSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var bedtime: Date = {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now) ?? .now
        return cal.date(bySettingHour: 22, minute: 30, second: 0, of: yesterday) ?? .now
    }()
    @State private var wake: Date = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: .now) ?? .now
    @State private var quality = 3
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Went to bed", selection: $bedtime)
                    DatePicker("Woke up", selection: $wake)
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(hoursMinutes(wake.timeIntervalSince(bedtime))).foregroundStyle(.secondary)
                    }
                }
                Section("How did you sleep?") {
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Button { quality = i } label: {
                                Image(systemName: i <= quality ? "star.fill" : "star").font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(i) stars")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    TextField("Note (optional)", text: $note)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .onChange(of: bedtime) { error = nil }
            .onChange(of: wake) { error = nil }
            .navigationTitle("Log sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .outlined)) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(CapsuleButtonStyle()) }
            }
        }
    }

    private func save() {
        let length = wake.timeIntervalSince(bedtime)
        guard length > 0 else { error = "Wake-up time needs to be after bedtime."; return }
        guard length < 20 * 3600 else { error = "That's over 20 hours. Check the dates."; return }
        context.insert(SleepLog(bedtime: bedtime, wakeTime: wake, quality: quality, note: note))
        dismiss()
    }
}

// MARK: - Finance › Savings (bank balances, typed in by you — no bank connection)

@Model
final class BankAccount {
    var name: String
    var balance: Double
    var updatedAt: Date
    var createdAt: Date

    init(name: String, balance: Double, createdAt: Date = .now) {
        self.name = name
        self.balance = balance
        self.updatedAt = createdAt
        self.createdAt = createdAt
    }
}

struct SavingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BankAccount.createdAt) private var accounts: [BankAccount]
    @State private var showingAdd = false
    @State private var editing: BankAccount?

    private var total: Double { accounts.reduce(0) { $0 + $1.balance } }

    var body: some View {
        List {
            Section {
                SummaryCard("Total balance") {
                    Text(total.aud).font(.system(size: 36, weight: .thin)).monospacedDigit()
                    if let latest = accounts.map(\.updatedAt).max() {
                        Text("Last updated \(latest.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if accounts.isEmpty {
                    Text("Tap + to add an account and its current balance.")
                        .foregroundStyle(.secondary)
                }
                ForEach(accounts) { account in
                    Button { editing = account } label: {
                        HStack {
                            Image(systemName: "building.columns")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                Text("Updated \(account.updatedAt.formatted(.dateTime.day().month(.abbreviated)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(account.balance.aud).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(accounts[index]) }
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Balances are typed in by you and stay on this phone. Tap an account to update it.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add account")
            }
        }
        .sheet(isPresented: $showingAdd) { AccountSheet(account: nil).tint(.primary) }
        .sheet(item: $editing) { account in AccountSheet(account: account).tint(.primary) }
    }
}

struct AccountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let account: BankAccount?

    @State private var name = ""
    @State private var balance: Double?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Account name, e.g. Everyday", text: $name)
                    .onChange(of: name) { error = nil }
                HStack {
                    Text("Balance")
                    Spacer()
                    TextField("$0.00", value: $balance, format: .currency(code: "AUD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(account == nil ? "New account" : "Update balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .outlined)) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(CapsuleButtonStyle()) }
            }
            .onAppear {
                if let account { name = account.name; balance = account.balance }
            }
        }
    }

    private func save() {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { error = "Give the account a name."; return }
        guard let balance else { error = "Enter the current balance."; return }
        if let account {
            account.name = text
            account.balance = balance
            account.updatedAt = .now
        } else {
            context.insert(BankAccount(name: text, balance: balance))
        }
        dismiss()
    }
}

// MARK: - Finance › Goals

@Model
final class SavingsGoal {
    var name: String
    var target: Double
    var saved: Double
    var deadline: Date?
    var createdAt: Date

    init(name: String, target: Double, saved: Double, deadline: Date?, createdAt: Date = .now) {
        self.name = name
        self.target = target
        self.saved = saved
        self.deadline = deadline
        self.createdAt = createdAt
    }

    var progress: Double { target > 0 ? min(saved / target, 1) : 0 }
}

/// Money put towards a goal on a given day (shown in the calendar snapshot).
@Model
final class GoalDeposit {
    var goalName: String
    var amount: Double
    var date: Date

    init(goalName: String, amount: Double, date: Date = .now) {
        self.goalName = goalName
        self.amount = amount
        self.date = date
    }
}

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @State private var showingAdd = false
    @State private var editing: SavingsGoal?

    var body: some View {
        List {
            if goals.isEmpty {
                Text("Tap + to set a savings goal, like a holiday or a new car.")
                    .foregroundStyle(.secondary)
            }
            ForEach(goals) { goal in
                Button { editing = goal } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(goal.name).font(.headline)
                            Spacer()
                            Text("\(Int((goal.progress * 100).rounded()))%").monospacedDigit()
                        }
                        ProgressView(value: goal.progress).tint(.primary)
                        HStack {
                            Text("\(goal.saved.aud) of \(goal.target.aud)")
                            Spacer()
                            if goal.saved >= goal.target {
                                Text("Reached").fontWeight(.semibold)
                            } else if let deadline = goal.deadline {
                                Text("by \(deadline.formatted(.dateTime.month(.abbreviated).year()))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets { context.delete(goals[index]) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New goal")
            }
        }
        .sheet(isPresented: $showingAdd) { GoalSheet(goal: nil).tint(.primary) }
        .sheet(item: $editing) { goal in GoalSheet(goal: goal).tint(.primary) }
    }
}

struct GoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal?

    @State private var name = ""
    @State private var target: Double?
    @State private var saved: Double?
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var deposit: Double?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let goal {
                    Section {
                        HStack {
                            TextField("Amount", value: $deposit, format: .currency(code: "AUD"))
                                .keyboardType(.decimalPad)
                            Button("Add money") { addDeposit(to: goal) }
                                .buttonStyle(.borderless)
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Text("Add to \(goal.name)")
                    } footer: {
                        Text("Saved so far: \(goal.saved.aud) of \(goal.target.aud)")
                    }
                }
                Section {
                    TextField("Goal name, e.g. Holiday fund", text: $name)
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("$0.00", value: $target, format: .currency(code: "AUD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if goal == nil {
                        HStack {
                            Text("Already saved")
                            Spacer()
                            TextField("$0.00", value: $saved, format: .currency(code: "AUD"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Toggle("Target date", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("By", selection: $deadline, in: Date.now..., displayedComponents: .date)
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .onChange(of: name) { error = nil }
            .onChange(of: deposit) { error = nil }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .outlined)) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(CapsuleButtonStyle()) }
            }
            .onAppear {
                guard let goal else { return }
                name = goal.name
                target = goal.target
                hasDeadline = goal.deadline != nil
                if let d = goal.deadline { deadline = d }
            }
        }
    }

    private func addDeposit(to goal: SavingsGoal) {
        guard let amount = deposit, amount > 0 else { error = "Enter an amount to add."; return }
        goal.saved += amount
        context.insert(GoalDeposit(goalName: goal.name, amount: amount))
        deposit = nil
    }

    private func save() {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { error = "Give the goal a name."; return }
        guard let target, target > 0 else { error = "Enter a target amount."; return }
        if let goal {
            goal.name = text
            goal.target = target
            goal.deadline = hasDeadline ? deadline : nil
        } else {
            context.insert(SavingsGoal(name: text, target: target, saved: max(saved ?? 0, 0),
                                       deadline: hasDeadline ? deadline : nil))
        }
        dismiss()
    }
}

// MARK: - Finance › Expenses

@Model
final class Expense {
    var title: String
    var amount: Double
    var category: String
    var date: Date

    init(title: String, amount: Double, category: String, date: Date) {
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
    }
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case food = "Food", groceries = "Groceries", transport = "Transport", bills = "Bills"
    case shopping = "Shopping", fun = "Fun", health = "Health", other = "Other"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .groceries: return "cart"
        case .transport: return "car"
        case .bills: return "doc.text"
        case .shopping: return "bag"
        case .fun: return "gamecontroller"
        case .health: return "cross.case"
        case .other: return "ellipsis.circle"
        }
    }

    static func symbol(for name: String) -> String { ExpenseCategory(rawValue: name)?.symbol ?? "ellipsis.circle" }
}

struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showingAdd = false

    private let cal = Calendar.current

    private func total(since start: Date) -> Double {
        expenses.filter { $0.date >= start }.reduce(0) { $0 + $1.amount }
    }
    private var startOfWeek: Date { cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now }
    private var startOfMonth: Date { cal.startOfMonth(for: .now) }

    private var byDay: [(day: Date, items: [Expense])] {
        let groups = Dictionary(grouping: expenses) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { (day: $0, items: groups[$0] ?? []) }
    }

    private var topCategories: [(name: String, amount: Double)] {
        let month = expenses.filter { $0.date >= startOfMonth }
        let sums = Dictionary(grouping: month, by: \.category).mapValues { $0.reduce(0) { $0 + $1.amount } }
        return sums.sorted { $0.value > $1.value }.prefix(4).map { (name: $0.key, amount: $0.value) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    stat("Today", total(since: cal.startOfDay(for: .now)))
                    Spacer()
                    stat("This week", total(since: startOfWeek))
                    Spacer()
                    stat("This month", total(since: startOfMonth))
                }
                .padding(.vertical, 4)

                if let biggest = topCategories.first?.amount, biggest > 0 {
                    ForEach(topCategories, id: \.name) { item in
                        HStack(spacing: 10) {
                            Image(systemName: ExpenseCategory.symbol(for: item.name)).frame(width: 20)
                            Text(item.name).frame(width: 80, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(Color.primary)
                                    .frame(width: max(geo.size.width * item.amount / biggest, 4), height: 6)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 12)
                            Text(item.amount.aud).font(.caption).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            } footer: {
                if !topCategories.isEmpty { Text("Top categories this month") }
            }

            if expenses.isEmpty {
                Text("Tap + to log something you spent.").foregroundStyle(.secondary)
            }

            ForEach(byDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { expense in
                        HStack(spacing: 12) {
                            Image(systemName: ExpenseCategory.symbol(for: expense.category)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expense.title)
                                Text(expense.category).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(expense.amount.aud).monospacedDigit()
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(group.items[index]) }
                    }
                } header: {
                    HStack {
                        Text(dayLabel(group.day))
                        Spacer()
                        Text(group.items.reduce(0) { $0 + $1.amount }.aud)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log an expense")
            }
        }
        .sheet(isPresented: $showingAdd) { ExpenseSheet().tint(.primary) }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.aud).font(.headline).monospacedDigit()
        }
    }
}

struct ExpenseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double?
    @State private var title = ""
    @State private var category = ExpenseCategory.food
    @State private var date = Date.now
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("$0.00", value: $amount, format: .currency(code: "AUD"))
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .thin))
                }
                Section {
                    TextField("What was it for?", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { item in
                            Label(item.rawValue, systemImage: item.symbol).tag(item)
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .onChange(of: amount) { error = nil }
            .onChange(of: title) { error = nil }
            .navigationTitle("Log an expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .outlined)) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(CapsuleButtonStyle()) }
            }
        }
    }

    private func save() {
        guard let amount, amount > 0 else { error = "Enter how much you spent."; return }
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(Expense(title: text.isEmpty ? category.rawValue : text,
                               amount: amount, category: category.rawValue, date: date))
        dismiss()
    }
}

// MARK: - Calendar › day snapshot (brief summary of every category, tap to expand)

struct SnapshotCard<Summary: View, Detail: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let summary: Summary
    let detail: Detail

    init(_ title: String, systemImage: String, isExpanded: Binding<Bool>,
         @ViewBuilder summary: () -> Summary, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.summary = summary()
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(title.uppercased(), systemImage: systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    summary
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")

            if isExpanded {
                Divider()
                detail.transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
    }
}

/// Two-sided summary line used in every snapshot card.
struct SummaryLine: View {
    let left: String
    var right: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(left)
            Spacer()
            if let right { Text(right) }
        }
        .font(.subheadline.weight(.medium))
    }
}

struct DayDetailView: View {
    let day: Date
    let openEntry: (JournalEntry) -> Void

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var dayEntries: [JournalEntry]
    @Query private var dayNews: [SavedHeadline]
    @Query(sort: \WatchItem.addedAt) private var watchItems: [WatchItem]
    @Query private var allNotes: [Note]
    @Query private var allReminders: [Reminder]
    @Query private var dayMeals: [Meal]
    @Query private var daySleep: [SleepLog]
    @Query private var dayExpenses: [Expense]
    @Query private var dayDeposits: [GoalDeposit]
    @Query(sort: \SurfBreak.addedAt) private var breaks: [SurfBreak]

    @State private var surf: [String: SurfDay] = [:]
    @State private var surfLoading = true
    @State private var surfNote: String?
    @State private var weather: DayWeather?
    @State private var weatherNote: String?
    @State private var weatherLoading = true
    @State private var markets: [DayMarket] = []
    @State private var marketsLoading = true
    @State private var expanded: Set<String> = []

    private let cal = Calendar.current

    init(day: Date, openEntry: @escaping (JournalEntry) -> Void) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        self.day = start
        self.openEntry = openEntry
        _dayEntries = Query(filter: #Predicate<JournalEntry> { $0.createdAt >= start && $0.createdAt < end },
                            sort: \JournalEntry.createdAt)
        _dayNews = Query(filter: #Predicate<SavedHeadline> { $0.day == start && $0.isHighlighted == true })
        _dayMeals = Query(filter: #Predicate<Meal> { $0.date >= start && $0.date < end }, sort: \Meal.date)
        _daySleep = Query(filter: #Predicate<SleepLog> { $0.day == start })
        _dayExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end }, sort: \Expense.date)
        _dayDeposits = Query(filter: #Predicate<GoalDeposit> { $0.date >= start && $0.date < end }, sort: \GoalDeposit.date)
    }

    // Day data

    private var isFuture: Bool { day > cal.startOfDay(for: .now) }
    private var dayNotes: [Note] { allNotes.filter { cal.isDate($0.createdAt, inSameDayAs: day) } }
    private var dayReminders: [Reminder] {
        allReminders
            .filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.dueDate ?? .now) < ($1.dueDate ?? .now) }
    }
    private var calories: Int { dayMeals.reduce(0) { $0 + $1.calories } }
    private var sleep: TimeInterval { daySleep.reduce(0) { $0 + $1.duration } }
    private var spent: Double { dayExpenses.reduce(0) { $0 + $1.amount } }
    private var saved: Double { dayDeposits.reduce(0) { $0 + $1.amount } }
    private var sortedNews: [SavedHeadline] {
        dayNews.sorted { ($0.publishedAt ?? $0.savedAt) > ($1.publishedAt ?? $1.savedAt) }
    }

    private func isOpen(_ key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) },
                set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                healthSnapshot
                journalSnapshot
                reportsSnapshot
                financeSnapshot
                Text("Tap a card to see more.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadWeather() }
        .task(id: watchItems.map(\.symbol)) { await loadMarkets() }
        .task(id: breaks.map(\.name)) { await loadSurf() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cal.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide)))
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(day.formatted(.dateTime.day().month(.wide).year()))
                .font(.largeTitle.bold())
        }
        .padding(.horizontal, 4)
    }

    // MARK: Journal

    private var journalSnapshot: some View {
        SnapshotCard("Journal", systemImage: "book", isExpanded: isOpen("journal")) {
            SummaryLine(left: "\(countText(dayEntries.count, "entry", "entries")) · \(countText(dayNotes.count, "note", "notes"))",
                        right: countText(dayReminders.count, "reminder", "reminders"))
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(dayEntries) { entry in
                    NavigationLink(value: entry) {
                        HStack(spacing: 10) {
                            Text(entry.mood)
                            Text(entry.title.isEmpty ? "Untitled" : entry.title).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(entry.createdAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(dayNotes) { note in
                    NavigationLink(value: note) {
                        HStack(spacing: 10) {
                            Image(systemName: "note.text")
                            Text(note.displayTitle).font(.subheadline).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(dayReminders) { reminder in
                    ReminderRow(reminder: reminder).padding(.vertical, 3)
                }
                Button {
                    let time = cal.dateComponents([.hour, .minute], from: .now)
                    let date = cal.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
                    let entry = JournalEntry(createdAt: date)
                    context.insert(entry)
                    openEntry(entry)
                } label: {
                    Label("New entry for this day", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .padding(.top, 8)
            }
        }
    }

    // MARK: Reports

    private var weatherSummary: String {
        if let weather {
            let rain = weather.rain < 0.1 ? "0 mm" : String(format: "%.1f mm", weather.rain)
            return "\(Int(weather.high.rounded()))° / \(Int(weather.low.rounded()))° · \(rain)"
        }
        return weatherLoading ? "Loading weather…" : "No weather"
    }

    private var marketSummary: String? {
        guard let first = markets.first else { return nil }
        let arrow = first.changePercent >= 0 ? "▲" : "▼"
        return "\(first.name) \(arrow) \(abs(first.changePercent).formatted(.number.precision(.fractionLength(2))))%"
    }

    private var reportsSnapshot: some View {
        SnapshotCard("Reports", systemImage: "chart.bar.doc.horizontal", isExpanded: isOpen("reports")) {
            VStack(alignment: .leading, spacing: 4) {
                SummaryLine(left: weatherSummary, right: marketSummary)
                if let best = bestSurf {
                    Label("Surf \(surfHeight(best.day)) at \(best.spot.name) · \(ratingLabel(best.day.rating(for: best.spot)))",
                          systemImage: "water.waves")
                        .font(.caption.weight(.semibold))
                }
                Label(countText(dayNews.count, "highlighted headline", "highlighted headlines"),
                      systemImage: dayNews.isEmpty ? "square" : "checkmark.square.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                // Weather
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let weather {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(weather.high.rounded()))°").font(.system(size: 36, weight: .thin))
                            Text("/ \(Int(weather.low.rounded()))°").foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Label(weather.rain < 0.1 ? "0 mm" : String(format: "%.1f mm", weather.rain), systemImage: "drop.fill")
                                    .font(.subheadline.weight(.medium))
                                if let chance = weather.rainChance {
                                    Text("\(chance)% chance of rain").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else if weatherLoading {
                        ProgressView()
                    } else {
                        Text(weatherNote ?? "Weather isn't available for this day.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // Highlighted news
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Highlighted news").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !isFuture {
                            NavigationLink("All saved", value: NewsDay(date: day)).font(.caption.weight(.medium))
                        }
                    }
                    if dayNews.isEmpty {
                        Text("Nothing highlighted for this day.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    ForEach(sortedNews) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.square.fill").padding(.top, 9)
                            headlineRow(item)
                        }
                    }
                }

                // Surf at your breaks
                if !breaks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Surf").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if surfLoading && surf.isEmpty {
                            ProgressView().padding(.top, 4)
                        } else if surf.isEmpty {
                            Text(surfNote ?? "Surf data isn't available for this day.")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
                        } else {
                            ForEach(breaks) { spot in
                                if let d = surf[spot.name] { surfRow(spot, d) }
                            }
                        }
                    }
                }

                // Watchlist report
                VStack(alignment: .leading, spacing: 0) {
                    Text("Watchlist").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if watchItems.isEmpty {
                        Text("Your watchlist is empty. Tap the star in Reports › Markets.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
                    } else if isFuture {
                        Text("Appears once the day has traded.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
                    } else if marketsLoading {
                        ProgressView().padding(.top, 4)
                    } else if markets.isEmpty {
                        Text("Couldn't load prices for this day.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
                    } else {
                        ForEach(markets) { item in marketRow(item) }
                        Text("Closing prices · Data from Yahoo Finance")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func headlineRow(_ item: SavedHeadline) -> some View {
        let row = VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Text(item.source)
                if let time = item.publishedAt {
                    Text("·")
                    Text(time, format: .dateTime.hour().minute())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)

        if let url = item.linkString.flatMap(URL.init(string:)) {
            Link(destination: url) { row }.foregroundStyle(.primary)
        } else {
            row
        }
    }

    @ViewBuilder
    private func marketRow(_ item: DayMarket) -> some View {
        let row = HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                if !item.isSameDay {
                    Text("Closed · last close \(item.tradingDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(formatPrice(item.close, kind: item.kind, currency: item.currency))
                .font(.subheadline.monospacedDigit())
            ChangeBadge(percent: item.changePercent)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 7)

        if let link = item.link {
            Link(destination: link) { row }.foregroundStyle(.primary)
        } else {
            row
        }
    }

    // MARK: Health

    private var healthSnapshot: some View {
        SnapshotCard("Health", systemImage: "heart", isExpanded: isOpen("health")) {
            SummaryLine(left: dayMeals.isEmpty ? "No meals logged" : "\(calories.formatted()) kcal",
                        right: daySleep.isEmpty ? "No sleep logged" : "Slept \(hoursMinutes(sleep))")
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                if dayMeals.isEmpty && daySleep.isEmpty {
                    Text("Log meals and sleep in the Health tab.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(dayMeals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(meal.name).font(.subheadline)
                            Text("\(meal.mealType) · \(meal.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(meal.calories) kcal").font(.subheadline).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                }
                ForEach(daySleep) { log in
                    HStack {
                        Image(systemName: "bed.double")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Slept \(hoursMinutes(log.duration))").font(.subheadline)
                            Text("\(log.bedtime.formatted(date: .omitted, time: .shortened)) – \(log.wakeTime.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        QualityStars(value: log.quality)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Finance

    private var financeSnapshot: some View {
        SnapshotCard("Finance", systemImage: "creditcard", isExpanded: isOpen("finance")) {
            SummaryLine(left: dayExpenses.isEmpty ? "No spending" : "Spent \(spent.aud)",
                        right: dayDeposits.isEmpty ? nil : "Saved \(saved.aud)")
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                if dayExpenses.isEmpty && dayDeposits.isEmpty {
                    Text("Log spending and add to goals in the Finance tab.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(dayExpenses) { expense in
                    HStack(spacing: 10) {
                        Image(systemName: ExpenseCategory.symbol(for: expense.category)).frame(width: 20)
                        Text(expense.title).font(.subheadline)
                        Spacer()
                        Text(expense.amount.aud).font(.subheadline).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                }
                ForEach(dayDeposits) { deposit in
                    HStack(spacing: 10) {
                        Image(systemName: "target").frame(width: 20)
                        Text(deposit.goalName).font(.subheadline)
                        Spacer()
                        Text("+\(deposit.amount.aud)").font(.subheadline.weight(.medium)).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Loading

    private func loadWeather() async {
        defer { weatherLoading = false }
        guard let profile = profiles.first, let lat = profile.latitude, let lon = profile.longitude else {
            weatherNote = "Set your location in your profile to see the weather."
            return
        }
        guard AustraliaRegion.contains(latitude: lat, longitude: lon) else {
            weatherNote = "Weather is available for Australian locations only."
            return
        }
        do {
            weather = try await DayWeatherService.fetch(latitude: lat, longitude: lon, day: day)
            if weather == nil { weatherNote = "The forecast only reaches about two weeks ahead." }
        } catch {
            weatherNote = "Couldn't load the weather. Check your connection and try again."
        }
    }

    private var bestSurf: (spot: SurfBreak, day: SurfDay)? {
        breaks.compactMap { b in surf[b.name].map { (spot: b, day: $0) } }
            .max { $0.day.rating(for: $0.spot) < $1.day.rating(for: $1.spot) }
    }

    private func surfHeight(_ d: SurfDay) -> String {
        guard let m = d.swellHeight ?? d.waveHeight else { return "–" }
        return "\(m.formatted(.number.precision(.fractionLength(1)))) m"
    }

    private func surfRow(_ spot: SurfBreak, _ d: SurfDay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(spot.name).font(.subheadline.weight(.medium)).lineLimit(1)
                RatingBars(value: d.rating(for: spot), small: true)
                Spacer()
                Text(surfHeight(d)).font(.subheadline.weight(.semibold).monospacedDigit())
                if let p = d.swellPeriod {
                    Text("\(Int(p.rounded()))s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let from = d.swellFrom {
                    HStack(spacing: 2) { WindArrow(degrees: from); Text(Compass.label(from)) }.font(.caption)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "wind")
                if let speed = d.morningWind, let from = d.morningWindFrom {
                    Text("Dawn \(Compass.label(from)) \(Int(speed.rounded())) km/h")
                    if let kind = d.windKind(for: spot) { Text("· \(kind.rawValue)") }
                } else {
                    Text("Dawn wind –")
                }
                if let t = d.waterTemp { Text("· Water \(Int(t.rounded()))°C") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private func loadSurf() async {
        surfLoading = true
        defer { surfLoading = false }
        surfNote = nil
        guard !breaks.isEmpty else { surf = [:]; return }
        let ahead = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: day).day ?? 0
        guard ahead <= 6 else {
            surf = [:]
            surfNote = "The surf forecast reaches about a week ahead."
            return
        }
        let spots = breaks.map { (name: $0.name, lat: $0.latitude, lon: $0.longitude) }
        let target = day
        let found = await withTaskGroup(of: (String, SurfDay?).self) { group -> [String: SurfDay] in
            for s in spots {
                group.addTask {
                    let days = try? await SurfService.fetch(latitude: s.lat, longitude: s.lon, day: target)
                    return (s.name, days?.first)
                }
            }
            var result: [String: SurfDay] = [:]
            for await (name, d) in group { if let d { result[name] = d } }
            return result
        }
        surf = found
        if found.isEmpty { surfNote = "Surf data isn't available for this day." }
    }

    private func loadMarkets() async {
        marketsLoading = true
        defer { marketsLoading = false }
        guard !isFuture, !watchItems.isEmpty else { markets = []; return }
        markets = await DayMarketService.fetchAll(day: day,
                                                  symbols: watchItems.map { ($0.symbol, $0.name, $0.quoteKind) })
    }
}


// MARK: - Style B (Solid Mono): shared controls

/// Capsule buttons: solid (main action), outlined (secondary) or destructive.
struct CapsuleButtonStyle: ButtonStyle {
    enum Kind { case solid, outlined, destructive }
    var kind: Kind = .solid
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        let tint: Color = kind == .destructive ? .red : .primary
        return configuration.label
            .font(large ? .headline : .subheadline.weight(.bold))
            .foregroundStyle(kind == .solid ? Color(.systemBackground) : tint)
            .padding(.horizontal, large ? 20 : 14)
            .padding(.vertical, large ? 14 : 6)
            .frame(maxWidth: large ? .infinity : nil)
            .background { if kind == .solid { Capsule().fill(Color.primary) } }
            .overlay { if kind != .solid { Capsule().stroke(tint, lineWidth: 1.5) } }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Segmented control with a solid capsule thumb (replaces the system segmented picker).
struct MonoSegment<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let isOn = selection == value
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = value }
                } label: {
                    Text(options[i].1)
                        .font(.subheadline.weight(isOn ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isOn { Capsule().fill(Color.primary).matchedGeometryEffect(id: "thumb", in: thumb) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// Solid floating tab bar (black in light mode, white in dark mode).
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { item in
                let isOn = selection == item
                Button {
                    selection = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 18, weight: isOn ? .semibold : .regular))
                        Text(item.title).font(.system(size: 10, weight: isOn ? .bold : .medium))
                    }
                    .foregroundStyle(Color(.systemBackground).opacity(isOn ? 1 : 0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.primary))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}

extension View {
    /// Hides the system tab bar and leaves room for the floating one.
    func floatingTabContent() -> some View {
        self
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 68) }
    }
}

// MARK: - Sunrise and sunset (for Auto appearance; calculated on the phone, no internet needed)

enum SunTimes {
    /// Sunrise and sunset for a date at a location. Falls back to 6 am / 6 pm with no location.
    static func times(on date: Date, latitude: Double?, longitude: Double?) -> (sunrise: Date, sunset: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let fallback = (cal.date(bySettingHour: 6, minute: 0, second: 0, of: start) ?? start,
                        cal.date(bySettingHour: 18, minute: 0, second: 0, of: start) ?? start)
        guard let lat = latitude, let lon = longitude else { return fallback }

        let rad = Double.pi / 180
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: start) ?? start
        let julianDay = noon.timeIntervalSince1970 / 86400 + 2440587.5
        let n = (julianDay - 2451545.0 + 0.0008).rounded()
        let jStar = n - lon / 360
        let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
        let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2451545.0 + jStar + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
        let declination = asin(sin(lambda * rad) * sin(23.4397 * rad))
        let cosOmega = (sin(-0.833 * rad) - sin(lat * rad) * sin(declination)) / (cos(lat * rad) * cos(declination))
        guard (-1...1).contains(cosOmega) else { return fallback }   // polar day or night
        let omega = acos(cosOmega) / rad
        func toDate(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2440587.5) * 86400) }
        return (toDate(transit - omega / 360), toDate(transit + omega / 360))
    }

    static func today(latitude: Double?, longitude: Double?) -> (sunrise: Date, sunset: Date) {
        times(on: .now, latitude: latitude, longitude: longitude)
    }

    static func isNight(at date: Date, latitude: Double?, longitude: Double?) -> Bool {
        let t = times(on: date, latitude: latitude, longitude: longitude)
        return date < t.sunrise || date >= t.sunset
    }
}

// MARK: - Weather › Surf (South East Queensland swell forecast)

/// A surf break you follow. Offshore wind and best swell are compass bearings the wind/swell come FROM.
@Model
final class SurfBreak {
    var name: String
    var area: String
    var latitude: Double
    var longitude: Double
    var offshoreFrom: Double
    var bestSwellFrom: Double
    var isCustom: Bool
    var addedAt: Date

    init(name: String, area: String, latitude: Double, longitude: Double,
         offshoreFrom: Double, bestSwellFrom: Double, isCustom: Bool = false, addedAt: Date = .now) {
        self.name = name
        self.area = area
        self.latitude = latitude
        self.longitude = longitude
        self.offshoreFrom = offshoreFrom
        self.bestSwellFrom = bestSwellFrom
        self.isCustom = isCustom
        self.addedAt = addedAt
    }
}

struct BreakPreset: Identifiable {
    let name: String
    let area: String
    let latitude: Double
    let longitude: Double
    let offshoreFrom: Double
    let bestSwellFrom: Double
    var id: String { name }
}

struct BreakGroup: Identifiable {
    let title: String
    let breaks: [BreakPreset]
    var id: String { title }
}

enum SEQLD {
    /// Rough box around South East Queensland's coast, from the NSW border to Noosa.
    static func contains(latitude: Double, longitude: Double) -> Bool {
        (-28.3 ... -25.8).contains(latitude) && (152.6 ... 153.7).contains(longitude)
    }

    static let searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -27.1, longitude: 153.2),
        span: MKCoordinateSpan(latitudeDelta: 2.6, longitudeDelta: 1.2))

    /// Approximate positions and orientations. Ratings are a rough guide, not local knowledge.
    static let groups: [BreakGroup] = [
        BreakGroup(title: "Gold Coast", breaks: [
            BreakPreset(name: "Snapper Rocks", area: "Coolangatta", latitude: -28.1625, longitude: 153.5500, offshoreFrom: 200, bestSwellFrom: 120),
            BreakPreset(name: "Greenmount", area: "Coolangatta", latitude: -28.1650, longitude: 153.5430, offshoreFrom: 200, bestSwellFrom: 120),
            BreakPreset(name: "Kirra", area: "Coolangatta", latitude: -28.1670, longitude: 153.5250, offshoreFrom: 210, bestSwellFrom: 120),
            BreakPreset(name: "Currumbin Alley", area: "Currumbin", latitude: -28.1300, longitude: 153.4870, offshoreFrom: 200, bestSwellFrom: 120),
            BreakPreset(name: "Palm Beach", area: "Palm Beach", latitude: -28.1150, longitude: 153.4700, offshoreFrom: 270, bestSwellFrom: 100),
            BreakPreset(name: "Burleigh Heads", area: "Burleigh Heads", latitude: -28.0890, longitude: 153.4550, offshoreFrom: 200, bestSwellFrom: 120),
            BreakPreset(name: "Miami", area: "Miami", latitude: -28.0720, longitude: 153.4430, offshoreFrom: 260, bestSwellFrom: 100),
            BreakPreset(name: "Nobby Beach", area: "Mermaid Beach", latitude: -28.0640, longitude: 153.4410, offshoreFrom: 260, bestSwellFrom: 100),
            BreakPreset(name: "Mermaid Beach", area: "Mermaid Beach", latitude: -28.0460, longitude: 153.4380, offshoreFrom: 260, bestSwellFrom: 100),
            BreakPreset(name: "Surfers Paradise", area: "Surfers Paradise", latitude: -28.0000, longitude: 153.4310, offshoreFrom: 260, bestSwellFrom: 100),
            BreakPreset(name: "Main Beach", area: "Main Beach", latitude: -27.9750, longitude: 153.4300, offshoreFrom: 260, bestSwellFrom: 100),
            BreakPreset(name: "The Spit", area: "Main Beach", latitude: -27.9580, longitude: 153.4280, offshoreFrom: 250, bestSwellFrom: 110)
        ]),
        BreakGroup(title: "Brisbane bay islands", breaks: [
            BreakPreset(name: "Cylinder Beach", area: "North Stradbroke Island", latitude: -27.4250, longitude: 153.5270, offshoreFrom: 180, bestSwellFrom: 130),
            BreakPreset(name: "Point Lookout Main Beach", area: "North Stradbroke Island", latitude: -27.4400, longitude: 153.5450, offshoreFrom: 290, bestSwellFrom: 110),
            BreakPreset(name: "Woorim", area: "Bribie Island", latitude: -27.0710, longitude: 153.2050, offshoreFrom: 270, bestSwellFrom: 80)
        ]),
        BreakGroup(title: "Sunshine Coast", breaks: [
            BreakPreset(name: "Kings Beach", area: "Caloundra", latitude: -26.8020, longitude: 153.1420, offshoreFrom: 290, bestSwellFrom: 130),
            BreakPreset(name: "Moffat Beach", area: "Caloundra", latitude: -26.7900, longitude: 153.1440, offshoreFrom: 260, bestSwellFrom: 120),
            BreakPreset(name: "Dicky Beach", area: "Caloundra", latitude: -26.7840, longitude: 153.1380, offshoreFrom: 270, bestSwellFrom: 100),
            BreakPreset(name: "Point Cartwright", area: "Buddina", latitude: -26.6800, longitude: 153.1390, offshoreFrom: 270, bestSwellFrom: 110),
            BreakPreset(name: "Mooloolaba", area: "Mooloolaba", latitude: -26.6820, longitude: 153.1200, offshoreFrom: 190, bestSwellFrom: 120),
            BreakPreset(name: "Alexandra Headland", area: "Alexandra Headland", latitude: -26.6720, longitude: 153.1100, offshoreFrom: 210, bestSwellFrom: 120),
            BreakPreset(name: "Coolum", area: "Coolum Beach", latitude: -26.5280, longitude: 153.0910, offshoreFrom: 270, bestSwellFrom: 90),
            BreakPreset(name: "Sunshine Beach", area: "Noosa", latitude: -26.4050, longitude: 153.1120, offshoreFrom: 270, bestSwellFrom: 90),
            BreakPreset(name: "Granite Bay", area: "Noosa National Park", latitude: -26.3770, longitude: 153.1040, offshoreFrom: 150, bestSwellFrom: 110),
            BreakPreset(name: "Tea Tree Bay", area: "Noosa National Park", latitude: -26.3800, longitude: 153.0970, offshoreFrom: 150, bestSwellFrom: 110),
            BreakPreset(name: "First Point", area: "Noosa Heads", latitude: -26.3840, longitude: 153.0880, offshoreFrom: 150, bestSwellFrom: 110)
        ])
    ]

    static var allPresets: [BreakPreset] { groups.flatMap(\.breaks) }

    static func nearest(to latitude: Double, _ longitude: Double, count: Int) -> [BreakPreset] {
        allPresets.sorted {
            hypot($0.latitude - latitude, $0.longitude - longitude) < hypot($1.latitude - latitude, $1.longitude - longitude)
        }.prefix(count).map { $0 }
    }
}

/// Smallest angle between two compass bearings (0–180).
func angleBetween(_ a: Double, _ b: Double) -> Double {
    let d = abs((a - b).truncatingRemainder(dividingBy: 360))
    return d > 180 ? 360 - d : d
}

enum WindKind: String { case glassy = "Glassy", offshore = "Offshore", cross = "Cross-shore", onshore = "Onshore" }

struct SurfDay: Identifiable {
    let id: String              // yyyy-MM-dd
    let date: Date
    let swellHeight: Double?    // metres (largest swell of the day)
    let swellPeriod: Double?    // seconds
    let swellFrom: Double?      // degrees
    let waveHeight: Double?     // total sea including wind chop
    let windWave: Double?
    let morningWind: Double?    // km/h, 5–9 am average
    let morningWindFrom: Double?
    let afternoonWind: Double?  // km/h, 1–5 pm average
    let afternoonWindFrom: Double?
    let waterTemp: Double?

    func windKind(for spot: SurfBreak) -> WindKind? {
        guard let speed = morningWind, let from = morningWindFrom else { return nil }
        if speed < 8 { return .glassy }
        let off = angleBetween(from, spot.offshoreFrom)
        if off <= 67.5 { return .offshore }
        if off >= 112.5 { return .onshore }
        return .cross
    }

    /// 0 (flat or blown out) to 5 (great). A rough guide built from size, period, morning wind and swell angle.
    func rating(for spot: SurfBreak) -> Int {
        guard let h = swellHeight ?? waveHeight else { return 0 }
        if h < 0.3 { return 0 }
        var score: Double
        switch h {
        case ..<0.5: score = 1
        case ..<0.9: score = 2
        case ..<1.5: score = 3
        case ..<2.5: score = 3.5
        default: score = 3
        }
        if let p = swellPeriod { score += p >= 11 ? 1 : p >= 9 ? 0.5 : p < 7 ? -1 : 0 }
        if let from = swellFrom {
            let d = angleBetween(from, spot.bestSwellFrom)
            score += d <= 45 ? 0.5 : d > 100 ? -1 : 0
        }
        if let kind = windKind(for: spot) {
            let speed = morningWind ?? 0
            switch kind {
            case .glassy: score += 1
            case .offshore: score += speed > 30 ? 0 : 1
            case .cross: score -= speed > 20 ? 1 : 0
            case .onshore: score -= speed > 15 ? 2 : 1
            }
        }
        return max(0, min(5, Int(score.rounded())))
    }
}

func ratingLabel(_ r: Int) -> String {
    ["Flat", "Poor", "Poor to fair", "Fair", "Good", "Great"][max(0, min(5, r))]
}

enum SurfService {
    private struct Marine: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let wave_height_max: [Double?]?
            let swell_wave_height_max: [Double?]?
            let swell_wave_period_max: [Double?]?
            let swell_wave_direction_dominant: [Double?]?
            let wind_wave_height_max: [Double?]?
        }
        struct Hourly: Decodable {
            let time: [String]
            let sea_surface_temperature: [Double?]?
        }
        let daily: Daily
        let hourly: Hourly?
    }

    private struct Wind: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let wind_speed_10m: [Double?]
            let wind_direction_10m: [Double?]
        }
        let hourly: Hourly
    }

    private static func get<T: Decodable>(_ type: T.Type, _ base: String, _ items: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: base)!
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Date range items: one day (yyyy-MM-dd) or the next 7 days.
    private static func range(_ dayKey: String?) -> [URLQueryItem] {
        if let dayKey { return [.init(name: "start_date", value: dayKey), .init(name: "end_date", value: dayKey)] }
        return [.init(name: "forecast_days", value: "7")]
    }

    private static func marine(lat: Double, lon: Double, day dayKey: String?) async throws -> Marine {
        try await get(Marine.self, "https://marine-api.open-meteo.com/v1/marine", [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "daily", value: "wave_height_max,swell_wave_height_max,swell_wave_period_max,swell_wave_direction_dominant,wind_wave_height_max"),
            .init(name: "hourly", value: "sea_surface_temperature"),
            .init(name: "cell_selection", value: "sea"),
            .init(name: "timezone", value: "Australia/Brisbane")
        ] + range(dayKey))
    }

    /// Average speed and vector-averaged direction for the given hours of each day.
    private static func windWindow(_ w: Wind.Hourly, hours: Range<Int>) -> [String: (speed: Double, from: Double)] {
        var acc: [String: (s: Double, x: Double, y: Double, n: Double)] = [:]
        for i in w.time.indices {
            let t = w.time[i]
            guard t.count >= 13, let hour = Int(t.dropFirst(11).prefix(2)), hours.contains(hour),
                  let speed = w.wind_speed_10m[safe: i] ?? nil, let dir = w.wind_direction_10m[safe: i] ?? nil else { continue }
            let key = String(t.prefix(10))
            var a = acc[key] ?? (0, 0, 0, 0)
            a.s += speed
            a.x += sin(dir * .pi / 180)
            a.y += cos(dir * .pi / 180)
            a.n += 1
            acc[key] = a
        }
        return acc.mapValues { a in
            var deg = atan2(a.x, a.y) * 180 / .pi
            if deg < 0 { deg += 360 }
            return (a.s / a.n, deg)
        }
    }

    static func fetch(for spot: SurfBreak) async throws -> [SurfDay] {
        try await fetch(latitude: spot.latitude, longitude: spot.longitude)
    }

    /// The next 7 days, or just `day` (any date up to a week ahead) for the calendar's daily report.
    static func fetch(latitude: Double, longitude: Double, day: Date? = nil) async throws -> [SurfDay] {
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM-dd"
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.timeZone = TimeZone(identifier: "Australia/Brisbane")
        let dayKey = day.map { keyFormatter.string(from: $0) }

        // Coastal points can land on a land grid cell; nudge out to sea (east, in SE QLD) if the forecast comes back empty.
        var sea = try await marine(lat: latitude, lon: longitude, day: dayKey)
        for nudge in [0.06, 0.15] {
            let empty = (sea.daily.swell_wave_height_max ?? []).allSatisfy { $0 == nil }
                && (sea.daily.wave_height_max ?? []).allSatisfy { $0 == nil }
            guard empty else { break }
            sea = try await marine(lat: latitude, lon: longitude + nudge, day: dayKey)
        }

        // Older dates come from the weather archive
        let isOld = day.map { $0 < Date.now.addingTimeInterval(-60 * 86400) } ?? false
        let wind = try? await get(Wind.self, isOld ? "https://archive-api.open-meteo.com/v1/archive" : "https://api.open-meteo.com/v1/forecast", [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "wind_speed_10m,wind_direction_10m"),
            .init(name: "timezone", value: "Australia/Brisbane"),
            .init(name: "wind_speed_unit", value: "kmh")
        ] + range(dayKey))
        let morning = wind.map { windWindow($0.hourly, hours: 5..<9) } ?? [:]
        let afternoon = wind.map { windWindow($0.hourly, hours: 13..<17) } ?? [:]

        // Daily water temperature: mean of the hourly values
        var water: [String: (sum: Double, n: Double)] = [:]
        if let h = sea.hourly, let temps = h.sea_surface_temperature {
            for i in h.time.indices {
                guard let v = temps[safe: i] ?? nil else { continue }
                let key = String(h.time[i].prefix(10))
                let w = water[key] ?? (0, 0)
                water[key] = (w.sum + v, w.n + 1)
            }
        }

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "Australia/Brisbane")

        let d = sea.daily
        return d.time.indices.compactMap { i in
            let key = d.time[i]
            guard let date = parser.date(from: key) else { return nil }
            return SurfDay(id: key, date: date,
                           swellHeight: d.swell_wave_height_max?[safe: i] ?? nil,
                           swellPeriod: d.swell_wave_period_max?[safe: i] ?? nil,
                           swellFrom: d.swell_wave_direction_dominant?[safe: i] ?? nil,
                           waveHeight: d.wave_height_max?[safe: i] ?? nil,
                           windWave: d.wind_wave_height_max?[safe: i] ?? nil,
                           morningWind: morning[key]?.speed,
                           morningWindFrom: morning[key]?.from,
                           afternoonWind: afternoon[key]?.speed,
                           afternoonWindFrom: afternoon[key]?.from,
                           waterTemp: water[key].map { $0.sum / $0.n })
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: Surf screen

struct SurfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SurfBreak.addedAt) private var breaks: [SurfBreak]
    @Query private var profiles: [UserProfile]

    @State private var selectedName: String?
    @State private var days: [String: [SurfDay]] = [:]
    @State private var loadedAt: [String: Date] = [:]
    @State private var errors: [String: String] = [:]
    @State private var expanded: String?
    @State private var showingBreaks = false

    private var selected: SurfBreak? {
        breaks.first { $0.name == selectedName } ?? breaks.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                breakChips
                if let spot = selected {
                    if let list = days[spot.name], !list.isEmpty {
                        todayCard(list[0], spot: spot)
                        weekCard(list, spot: spot)
                    } else if let error = errors[spot.name] {
                        ContentUnavailableView("Surf forecast unavailable", systemImage: "water.waves.slash",
                                               description: Text(error))
                    } else {
                        ProgressView("Loading swell…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                    Text("Swell data by Open-Meteo.com marine forecast. Ratings are a rough guide from size, period, morning wind and swell angle. Check the beach before you paddle out.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .refreshable { if let spot = selected { await load(spot, force: true) } }
        .task(id: selected?.name) { if let spot = selected { await load(spot) } }
        .sheet(isPresented: $showingBreaks) { ManageBreaksView().tint(.primary) }
    }

    // Break picker: one capsule per saved break, plus Add/Edit

    private var breakChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(breaks) { spot in
                    let isOn = spot.name == selected?.name
                    Button { selectedName = spot.name } label: { Text(spot.name).lineLimit(1) }
                        .buttonStyle(CapsuleButtonStyle(kind: isOn ? .solid : .outlined))
                }
                Button { showingBreaks = true } label: {
                    Label(breaks.isEmpty ? "Add a break" : "Breaks", systemImage: breaks.isEmpty ? "plus" : "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(CapsuleButtonStyle(kind: .outlined))
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Follow your local breaks")
                .font(.title3.bold())
            Text("Get a 7-day swell forecast for South East Queensland breaks, from Coolangatta to Noosa.")
                .foregroundStyle(.secondary)
            if let p = profiles.first, let lat = p.latitude, let lon = p.longitude, SEQLD.contains(latitude: lat, longitude: lon) {
                Text("Closest to \(p.placeName)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(SEQLD.nearest(to: lat, lon, count: 3)) { preset in
                    Button { add(preset) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.headline)
                                Text(preset.area).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Choose breaks") { showingBreaks = true }
                .buttonStyle(CapsuleButtonStyle(large: true))
                .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private func add(_ preset: BreakPreset) {
        guard !breaks.contains(where: { $0.name == preset.name }) else { return }
        context.insert(SurfBreak(name: preset.name, area: preset.area, latitude: preset.latitude, longitude: preset.longitude,
                                 offshoreFrom: preset.offshoreFrom, bestSwellFrom: preset.bestSwellFrom))
        selectedName = preset.name
    }

    // Today

    private func todayCard(_ day: SurfDay, spot: SurfBreak) -> some View {
        let rating = day.rating(for: spot)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.name).font(.headline)
                    Text(spot.area).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                RatingBars(value: rating)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(heightText(day.swellHeight ?? day.waveHeight))
                    .font(.system(size: 52, weight: .thin))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(ratingLabel(rating)).font(.title3.weight(.semibold))
                    if let p = day.swellPeriod { Text("\(Int(p.rounded())) s period").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            Divider()
            HStack(alignment: .top) {
                metric("Swell", day.swellFrom.map { "\(Compass.label($0)) \(Int($0.rounded()))°" } ?? "–", arrow: day.swellFrom)
                Spacer()
                metric("Morning wind", windText(day.morningWind, day.morningWindFrom), arrow: day.morningWindFrom)
                Spacer()
                metric("Water", day.waterTemp.map { "\(Int($0.rounded()))°C" } ?? "–")
            }
            if let kind = day.windKind(for: spot) {
                Text("\(kind.rawValue) at dawn (5–9 am)\(day.afternoonWind.map { " · \(Int($0.rounded())) km/h \(Compass.label(day.afternoonWindFrom ?? 0)) by afternoon" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
    }

    // 7 days

    private func weekCard(_ list: [SurfDay], spot: SurfBreak) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("7-day swell", systemImage: "water.waves")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            ForEach(Array(list.enumerated()), id: \.element.id) { index, day in
                if index > 0 { Divider() }
                dayRow(day, spot: spot, isToday: index == 0)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.05)))
    }

    private func dayRow(_ day: SurfDay, spot: SurfBreak, isToday: Bool) -> some View {
        let open = expanded == day.id
        let rating = day.rating(for: spot)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.body.weight(.medium))
                    .frame(width: 52, alignment: .leading)
                RatingBars(value: rating, small: true)
                Spacer()
                Text(heightText(day.swellHeight ?? day.waveHeight))
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(day.swellPeriod.map { "\(Int($0.rounded()))s" } ?? "")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                HStack(spacing: 2) {
                    if let from = day.swellFrom { WindArrow(degrees: from) }
                    Text(day.swellFrom.map { Compass.label($0) } ?? "")
                }
                .font(.caption)
                .frame(width: 38, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Image(systemName: "wind")
                if let from = day.morningWindFrom { WindArrow(degrees: from) }
                Text(windText(day.morningWind, day.morningWindFrom))
                if let kind = day.windKind(for: spot) { Text("· \(kind.rawValue)") }
                Spacer()
                Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 62)

            if open {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { detail("Rating", ratingLabel(rating)); detail("Total sea", heightText(day.waveHeight)) }
                    GridRow { detail("Wind chop", heightText(day.windWave)); detail("Afternoon wind", windText(day.afternoonWind, day.afternoonWindFrom)) }
                    GridRow { detail("Water", day.waterTemp.map { "\(Int($0.rounded()))°C" } ?? "–"); detail("Best swell here", Compass.label(spot.bestSwellFrom)) }
                }
                .padding(.leading, 62)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded = open ? nil : day.id } }
    }

    private func metric(_ label: String, _ value: String, arrow: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                if let arrow { WindArrow(degrees: arrow) }
                Text(value).font(.subheadline.weight(.semibold))
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold))
        }
    }

    private func heightText(_ metres: Double?) -> String {
        guard let m = metres else { return "–" }
        return "\(m.formatted(.number.precision(.fractionLength(1)))) m"
    }

    private func windText(_ speed: Double?, _ from: Double?) -> String {
        guard let speed, let from else { return "–" }
        return "\(Compass.label(from)) \(Int(speed.rounded())) km/h"
    }

    private func load(_ spot: SurfBreak, force: Bool = false) async {
        if !force, let at = loadedAt[spot.name], Date.now.timeIntervalSince(at) < 1800 { return }
        errors[spot.name] = nil
        do {
            let result = try await SurfService.fetch(for: spot)
            if result.allSatisfy({ $0.swellHeight == nil && $0.waveHeight == nil }) {
                errors[spot.name] = "No swell data for this spot. Try a break a little further along the coast."
            } else {
                days[spot.name] = result
                loadedAt[spot.name] = .now
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if days[spot.name] == nil {
                errors[spot.name] = "Couldn't load the swell forecast. Check your connection and pull down to try again."
            }
        }
    }
}

/// Five bars, filled to the rating.
struct RatingBars: View {
    let value: Int
    var small = false

    var body: some View {
        HStack(spacing: small ? 2 : 3) {
            ForEach(1...5, id: \.self) { i in
                Capsule()
                    .fill(i <= value ? Color.primary : Color.primary.opacity(0.12))
                    .frame(width: small ? 5 : 7, height: small ? 12 : 18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ratingLabel(value)), \(value) out of 5")
    }
}

// MARK: Manage breaks

struct ManageBreaksView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SurfBreak.addedAt) private var breaks: [SurfBreak]

    @State private var customName = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var picked: MKMapItem?
    @State private var faces: Double = 90
    @State private var searching = false
    @State private var error: String?

    private let faceOptions: [(String, Double)] = [("N", 0), ("NE", 45), ("E", 90), ("SE", 135), ("S", 180)]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if breaks.isEmpty {
                        Text("No breaks yet. Add some below.").foregroundStyle(.secondary)
                    }
                    ForEach(breaks) { spot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spot.name)
                            Text(spot.isCustom ? "\(spot.area) · your break" : spot.area)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(breaks[i]) }
                    }
                } header: {
                    Text("Your breaks")
                } footer: {
                    if !breaks.isEmpty { Text("Swipe left to remove.") }
                }

                ForEach(SEQLD.groups) { group in
                    Section(group.title) {
                        ForEach(group.breaks) { preset in
                            let has = breaks.contains { $0.name == preset.name }
                            Button {
                                if let existing = breaks.first(where: { $0.name == preset.name }) {
                                    context.delete(existing)
                                } else {
                                    context.insert(SurfBreak(name: preset.name, area: preset.area, latitude: preset.latitude,
                                                             longitude: preset.longitude, offshoreFrom: preset.offshoreFrom,
                                                             bestSwellFrom: preset.bestSwellFrom))
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name).fontWeight(has ? .bold : .regular)
                                        Text(preset.area).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: has ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.title3)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    TextField("Break name, e.g. Tallebudgera Creek", text: $customName)
                        .onChange(of: customName) { error = nil }
                    if let picked {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                            Text(picked.name ?? "Selected place")
                            Spacer()
                            Button("Change") { self.picked = nil }.buttonStyle(.borderless)
                        }
                    } else {
                        HStack {
                            TextField("Search a beach or suburb", text: $query)
                                .submitLabel(.search)
                                .onSubmit { Task { await search() } }
                                .onChange(of: query) { error = nil }
                            Button { Task { await search() } } label: {
                                if searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                            }
                            .buttonStyle(.borderless)
                        }
                        ForEach(results, id: \.self) { item in
                            Button {
                                picked = item
                                results = []
                                if customName.trimmingCharacters(in: .whitespaces).isEmpty { customName = item.name ?? "" }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown place")
                                    if let title = item.placemark.title {
                                        Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Which way does the beach face?").font(.subheadline)
                        MonoSegment(options: faceOptions.map { ($0.1, $0.0) }, selection: $faces)
                    }
                    .padding(.vertical, 4)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Add break") { addCustom() }
                        .buttonStyle(CapsuleButtonStyle(large: true))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Add your own break")
                } footer: {
                    Text("South East Queensland only, from the NSW border to Noosa. Facing direction sets which wind counts as offshore.")
                }
            }
            .navigationTitle("Surf breaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle()) }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { error = "Type a beach or suburb to search."; return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = SEQLD.searchRegion
        let response = try? await MKLocalSearch(request: request).start()
        results = Array((response?.mapItems ?? []).filter {
            let c = $0.placemark.coordinate
            return SEQLD.contains(latitude: c.latitude, longitude: c.longitude)
        }.prefix(5))
        if results.isEmpty { error = "No places found in South East Queensland. Try a nearby suburb, e.g. Tugun." }
    }

    private func addCustom() {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Give the break a name."; return }
        guard let picked else { error = "Search for where the break is, then pick it from the list."; return }
        guard !breaks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            error = "You already have a break called \(name)."
            return
        }
        let c = picked.placemark.coordinate
        let offshore = (faces + 180).truncatingRemainder(dividingBy: 360)
        context.insert(SurfBreak(name: name, area: picked.placemark.locality ?? picked.name ?? "Custom",
                                 latitude: c.latitude, longitude: c.longitude,
                                 offshoreFrom: offshore, bestSwellFrom: faces, isCustom: true))
        customName = ""
        query = ""
        self.picked = nil
    }
}
