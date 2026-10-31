import FluidKit
import Foundation

/// Your next meeting in the menu bar, with a one-click join.
///
/// It reads the calendars you have in Calendar.app (through the host, which
/// asks for access once), finds the video link in the location, URL or notes
/// (Zoom, Meet, Teams, Webex and a dozen more), counts down to it, reminds
/// you a few minutes before, and can open the call for you when it starts.
@main
final class UpNext: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.up-next",
        name: "Up Next",
        version: "1.0.0",
        summary: "Your next meeting in the menu bar, with a countdown and one-click join.",
        surfaces: [.menuBar, .panel, .window, .widget],
        triggers: [.launch, .every(.seconds(30)), .wake],
        capabilities: [.calendar],
        hotkey: "ctrl+option+j"
    )

    // MARK: Meeting links

    struct Service {
        let name: String
        /// Lowercased fragments a link to this service contains.
        let patterns: [String]
    }

    /// Known video services, most specific first.
    static let services: [Service] = [
        Service(name: "Zoom", patterns: ["zoom.us/j/", "zoom.us/my/", "zoom.us/w/", "zoomgov.com/j/", "zoom.us/s/"]),
        Service(name: "Google Meet", patterns: ["meet.google.com/"]),
        Service(name: "Teams", patterns: ["teams.microsoft.com/l/meetup-join", "teams.live.com/meet", "teams.microsoft.com/meet"]),
        Service(name: "Webex", patterns: [".webex.com/meet", ".webex.com/join", ".webex.com/wbxmjs", ".webex.com/"]),
        Service(name: "Slack huddle", patterns: ["app.slack.com/huddle"]),
        Service(name: "FaceTime", patterns: ["facetime.apple.com/join"]),
        Service(name: "Chime", patterns: ["chime.aws/"]),
        Service(name: "GoTo Meeting", patterns: ["gotomeeting.com/join", "gotomeet.me/", "meet.goto.com/"]),
        Service(name: "Whereby", patterns: ["whereby.com/"]),
        Service(name: "Jitsi", patterns: ["meet.jit.si/"]),
        Service(name: "BlueJeans", patterns: ["bluejeans.com/"]),
        Service(name: "Around", patterns: ["around.co/"]),
        Service(name: "Tuple", patterns: ["tuple.app/c/"]),
        Service(name: "Gather", patterns: ["app.gather.town/"]),
        Service(name: "Skype", patterns: ["join.skype.com/"]),
        Service(name: "Discord", patterns: ["discord.gg/", "discord.com/channels/"]),
        Service(name: "Zoho Meeting", patterns: ["meeting.zoho.com/", "meeting.zoho.eu/"]),
        Service(name: "Livestorm", patterns: ["app.livestorm.co/"]),
    ]

    struct MeetingLink: Equatable {
        let url: String
        let service: String
    }

    /// The first video-call link in the event's location, URL or notes.
    static func meetingLink(for event: CalendarEvent) -> MeetingLink? {
        for text in [event.location, event.url, event.notes].compactMap({ $0 }) {
            for url in links(in: text) {
                let lower = url.lowercased()
                if let service = services.first(where: { service in service.patterns.contains { lower.contains($0) } }) {
                    return MeetingLink(url: url, service: service.name)
                }
            }
        }
        return nil
    }

    /// Every http(s) URL in a piece of text, without trailing punctuation.
    static func links(in text: String) -> [String] {
        var result: [String] = []
        var rest = Substring(text)
        while let start = rest.range(of: "https://", options: .caseInsensitive) ?? rest.range(of: "http://", options: .caseInsensitive) {
            let tail = rest[start.lowerBound...]
            let end = tail.firstIndex(where: { $0.isWhitespace || "<>\"'()[]{}".contains($0) }) ?? tail.endIndex
            var url = String(tail[..<end])
            while let last = url.last, ".,;:!?".contains(last) { url.removeLast() }
            if url.count > 10 { result.append(url) }
            rest = tail[end...]
        }
        return result
    }

    // MARK: State

    @Stored("hiddenCalendars") var hiddenCalendars: [String] = []
    @Stored("showAllDay") var showAllDay = true
    @Stored("showDeclined") var showDeclined = false
    @Stored("onlyWithLinks") var onlyWithLinks = false
    @Stored("remindMinutes") var remindMinutes = 2.0
    @Stored("autoJoin") var autoJoin = false
    @Stored("titleLength") var titleLength = 24.0
    @Stored("showTitle") var showTitle = true
    @Stored("openInApps") var openInApps = true
    @Stored("onlyWithPeople") var onlyWithPeople = false
    @Stored("showFinished") var showFinished = false
    /// Show the next meeting in the menu bar only this many hours ahead (0: any time today).
    @Stored("menuBarHours") var menuBarHours = 0.0

    var events: [CalendarEvent] = []
    var calendars: [String] = []
    var lastError: String?
    var loaded = false
    private var reminded: Set<String> = []
    private var joined: Set<String> = []

    func refresh() async throws {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        guard let end = Calendar.current.date(byAdding: .day, value: 2, to: start) else { return }
        do {
            let all = try await Fluid.calendarEvents(from: start, to: end)
            calendars = Array(Set(all.map(\.calendar))).sorted()
            events = all
            lastError = nil
            loaded = true
        } catch {
            lastError = "\(error)"
            return
        }
        remindAndJoin(now: now)
    }

    /// The events the settings let through.
    var visible: [CalendarEvent] {
        events.filter { event in
            !hiddenCalendars.contains(event.calendar)
                && (showAllDay || !event.isAllDay)
                && (showDeclined || event.participation != .declined)
                && (!onlyWithLinks || event.isAllDay || Self.meetingLink(for: event) != nil)
                && (!onlyWithPeople || event.isAllDay || event.attendees > 1)
        }
    }

    /// Timed events that haven't ended, soonest first.
    func upcoming(now: Date = Date()) -> [CalendarEvent] {
        visible.filter { !$0.isAllDay && $0.end > now && $0.participation != .declined }.sorted { $0.start < $1.start }
    }

    /// What's on now (the latest-started one), else what's next today.
    func focus(now: Date = Date()) -> CalendarEvent? {
        let soon = upcoming(now: now)
        if let current = soon.filter({ $0.start <= now }).max(by: { $0.start < $1.start }) {
            // A meeting about to start beats one that is ending.
            if let next = soon.first(where: { $0.start > now }), next.start.timeIntervalSince(now) <= 5 * 60, current.end.timeIntervalSince(now) <= 5 * 60 { return next }
            return current
        }
        // Today's next one, or one soon after midnight (a late-night call
        // shouldn't vanish because the date changes first).
        return soon.first { Calendar.current.isDate($0.start, inSameDayAs: now) || $0.start.timeIntervalSince(now) <= 3 * 3600 }
    }

    func remindAndJoin(now: Date) {
        for event in upcoming(now: now) {
            let until = event.start.timeIntervalSince(now)
            if remindMinutes > 0, until > 0, until <= remindMinutes * 60 + 15, !reminded.contains(event.id) {
                reminded.insert(event.id)
                let link = Self.meetingLink(for: event)
                Fluid.notify("\(event.title) in \(max(1, Int((until / 60).rounded()))) min", body: link.map { "Join on \($0.service) from the menu bar (⌃⌥J)" } ?? event.location)
            }
            if autoJoin, until <= 30, now < event.start.addingTimeInterval(120), !joined.contains(event.id), let link = Self.meetingLink(for: event) {
                joined.insert(event.id)
                Fluid.open(link.url)
            }
        }
        if reminded.count > 200 { reminded = Set(reminded.suffix(50)) }
        if joined.count > 200 { joined = Set(joined.suffix(50)) }
    }

    func join(_ event: CalendarEvent) {
        if let link = Self.meetingLink(for: event) {
            joined.insert(event.id)
            Fluid.open(openInApps ? Self.appURL(for: link) : link.url)
        } else if let url = event.url {
            Fluid.open(url)
        }
    }

    /// The meeting app's own URL for Zoom and Teams links, so joining opens
    /// the app without leaving a browser tab behind. Other links stay https.
    static func appURL(for link: MeetingLink) -> String {
        guard let url = URLComponents(string: link.url), let host = url.host?.lowercased() else { return link.url }
        if link.service == "Zoom", url.path.hasPrefix("/j/") {
            let number = url.path.dropFirst(3).prefix { $0.isNumber }
            guard !number.isEmpty else { return link.url }
            var app = URLComponents()
            app.scheme = "zoommtg"
            app.host = host
            app.path = "/join"
            app.queryItems = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(number))]
                + (url.queryItems ?? []).filter { $0.name == "pwd" }
            return app.string ?? link.url
        }
        if link.service == "Teams", link.url.lowercased().hasPrefix("https://teams.microsoft.com/") {
            return "msteams:" + link.url.dropFirst("https://teams.microsoft.com".count)
        }
        return link.url
    }

    static let instantMeetings: [(name: String, url: String)] = [
        ("Google Meet", "https://meet.google.com/new"),
        ("Zoom", "https://zoom.us/start/videomeeting"),
        ("Teams", "https://teams.microsoft.com/l/meeting/new"),
    ]

    // MARK: Words

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func span(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(max(1, minutes))m" }
        let hours = minutes / 60
        return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
    }

    func countdown(_ event: CalendarEvent, now: Date = Date()) -> String {
        if event.start <= now { return "\(Self.span(event.end.timeIntervalSince(now))) left" }
        return "in \(Self.span(event.start.timeIntervalSince(now)))"
    }

    func shortTitle(_ title: String) -> String {
        let limit = max(4, Int(titleLength))
        return title.count > limit ? String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : title
    }

    func subtitle(_ event: CalendarEvent) -> String {
        var parts: [String] = []
        parts.append(event.isAllDay ? "All day" : "\(Self.time(event.start))–\(Self.time(event.end))")
        if let link = Self.meetingLink(for: event) {
            parts.append(link.service)
        } else if let location = event.location, !location.isEmpty {
            parts.append(location.count > 40 ? String(location.prefix(39)) + "…" : location)
        }
        if event.attendees > 1 { parts.append("\(event.attendees) people") }
        parts.append(event.calendar)
        return parts.joined(separator: " · ")
    }

    // MARK: Surfaces

    var menuBar: ViewContent {
        if lastError != nil && !loaded {
            Label("", symbol: "calendar.badge.exclamationmark").role(.warning)
        } else if let event = focus(), menuBarHours == 0 || event.start.timeIntervalSinceNow <= menuBarHours * 3600 {
            let soon = event.start.timeIntervalSinceNow < 5 * 60
            let title = showTitle ? "\(shortTitle(event.title)) · \(countdown(event))" : countdown(event)
            Label(title, symbol: Self.meetingLink(for: event) != nil ? "video" : "calendar").role(event.start <= Date() ? .accent : soon ? .warning : .primary)
        } else {
            Label("", symbol: "calendar").role(.secondary)
        }
    }

    var panel: ViewContent {
        let now = Date()
        if let lastError {
            Text(lastError).role(.warning)
        }
        if let event = focus(now: now) {
            Text(event.start <= now ? "Now" : "Next").style(.caption).role(.secondary)
            Text(event.title).style(.headline)
            Text("\(subtitle(event)) · \(countdown(event, now: now))").style(.caption).role(.secondary)
            if let link = Self.meetingLink(for: event) {
                Button("Join on \(link.service)", symbol: "video.fill", role: .accent, key: "join-focus") { self.join(event) }
            }
        } else if loaded {
            ContentUnavailableView("No more meetings today", symbol: "calendar", message: "Enjoy the focus time.")
        }
        List(searchable: true) {
            day("Today", now, now: now)
            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) {
                day("Tomorrow", tomorrow, now: now)
            }
        }
        Picker("Start a meeting now", options: Self.instantMeetings.map(\.name), selection: nil) { name in
            if let meeting = Self.instantMeetings.first(where: { $0.name == name }) { Fluid.open(meeting.url) }
        }
        settings
    }

    @ViewBuilder func day(_ title: String, _ date: Date, now: Date) -> ViewContent {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        // Timed events first (soonest on top, so Return joins it), all-day ones after.
        let items = visible.filter { $0.start < dayEnd && $0.end > dayStart && (showFinished || $0.isAllDay || $0.end > now) }
            .sorted { ($0.isAllDay ? 1 : 0, $0.start) < ($1.isAllDay ? 1 : 0, $1.start) }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { event in row(event, now: now) }
            }
        }
    }

    func row(_ event: CalendarEvent, now: Date) -> Row {
        let link = Self.meetingLink(for: event)
        let past = !event.isAllDay && event.end <= now
        var row = Row(event.title, subtitle: subtitle(event), symbol: event.isAllDay ? "sun.max" : link != nil ? "video" : "calendar", key: event.id)
        switch event.participation {
        case .declined: row = row.badge("Declined", role: .critical)
        case .tentative: row = row.badge("Maybe", role: .warning)
        case .pending: row = row.badge("Invited", role: .warning)
        default:
            if past {
                row = row.badge("Done", role: .secondary)
            } else if !event.isAllDay, event.start <= now {
                row = row.badge("Now", role: .accent)
            } else if !event.isAllDay, event.start.timeIntervalSince(now) < 3600 {
                row = row.badge(countdown(event, now: now), role: .primary)
            }
        }
        if let link {
            row = row.action("Join on \(link.service)", shortcut: "cmd+return") { self.join(event) }
                .action("Copy meeting link") { Fluid.copy(link.url) }
        }
        if let url = event.url, url != link?.url {
            row = row.action("Open event link") { Fluid.open(url) }
        }
        return row.action("Copy details") {
            Fluid.copy([event.title, self.subtitle(event), link?.url].compactMap { $0 }.joined(separator: "\n"))
        }
    }

    @ViewBuilder var settings: ViewContent {
        Section("Settings") {
            Slider(remindMinutes > 0 ? "Remind \(Int(remindMinutes)) min before" : "No reminders", value: remindMinutes, in: 0...15, step: 1, key: "remind") { self.remindMinutes = $0 }
            Toggle("Open the call when it starts", isOn: autoJoin) { self.autoJoin = $0 }
            Toggle("Open Zoom and Teams in their apps", isOn: openInApps) { self.openInApps = $0 }
            Toggle("Show the title in the menu bar", isOn: showTitle) { self.showTitle = $0 }
            Slider(menuBarHours == 0 ? "Menu bar: any meeting today" : "Menu bar: meetings within \(Int(menuBarHours))h", value: menuBarHours, in: 0...8, step: 1, key: "menu-hours") { self.menuBarHours = $0 }
            if showTitle {
                Slider("Menu bar title: \(Int(titleLength)) characters", value: titleLength, in: 8...60, step: 4, key: "title-length") { self.titleLength = $0 }
            }
            Toggle("Show all-day events", isOn: showAllDay) { self.showAllDay = $0 }
            Toggle("Show declined events", isOn: showDeclined) { self.showDeclined = $0 }
            Toggle("Only meetings with a call link", isOn: onlyWithLinks) { self.onlyWithLinks = $0 }
            Toggle("Only events with other people", isOn: onlyWithPeople) { self.onlyWithPeople = $0 }
            Toggle("Show finished events", isOn: showFinished) { self.showFinished = $0 }
            ForEach(calendars) { name in
                Toggle(name, isOn: !hiddenCalendars.contains(name), key: "calendar-\(name)") { on in
                    if on { self.hiddenCalendars.removeAll { $0 == name } } else if !self.hiddenCalendars.contains(name) { self.hiddenCalendars.append(name) }
                }
            }
        }
    }

    var widget: ViewContent {
        if let event = focus() {
            Text(event.title).style(.headline)
            Text("\(Self.time(event.start)) · \(countdown(event))").style(.caption)
            if let link = Self.meetingLink(for: event) { Label(link.service, symbol: "video") }
        } else {
            Label("No more meetings today", symbol: "calendar")
        }
        ForEach(upcoming().dropFirst().prefix(3)) { event in
            LabeledContent(Self.time(event.start), value: event.title)
        }
    }

    // MARK: Agents

    var tools: [AgentTool] {
        AgentTool("next_meeting", description: "The meeting on now or next, with its time and call link") { _ in
            guard let event = self.focus() else { return "No more meetings today." }
            return "\(event.title), \(self.subtitle(event)), \(self.countdown(event))" + (Self.meetingLink(for: event).map { "\nJoin: \($0.url)" } ?? "")
        }
        AgentTool("agenda", description: "Meetings for today or tomorrow, one per line", parameters: [ToolParameter("day", description: "today or tomorrow (default today)", required: false)]) { arguments in
            let tomorrow = arguments.string("day")?.lowercased() == "tomorrow"
            let date = tomorrow ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() : Date()
            let items = self.visible.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
            return items.isEmpty ? "Nothing on the calendar \(tomorrow ? "tomorrow" : "today")." : items.map { "\($0.isAllDay ? "All day" : Self.time($0.start)) \($0.title)" }.joined(separator: "\n")
        }
        AgentTool("join_next", description: "Open the call link of the meeting on now or next") { _ in
            guard let event = self.focus(), let link = Self.meetingLink(for: event) else { return "The next meeting has no call link." }
            self.join(event)
            return "Opening \(event.title) on \(link.service)."
        }
    }
}
