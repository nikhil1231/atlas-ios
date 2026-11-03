import XCTest
@testable import Atlas

/// The app against what Atlas really returns (AtlasFixtures.swift), plus the pure pieces of the
/// Reminders sync, widgets, routing and Siri summaries.
@MainActor
final class IntegrationTests: XCTestCase {
    private func fixture(_ key: String) throws -> ReadSnapshot {
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(atlasFixtures.utf8)) as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(all[key]))
        return try mobileDecoder().decode(ReadSnapshot.self, from: data)
    }

    func testDecodesTheRealDashboard() throws {
        let read = try fixture("dashboard")
        XCTAssertEqual(read.freshness, "fresh")
        let dashboard = try XCTUnwrap(read.data).decode(Dashboard.self)
        XCTAssertEqual(dashboard.focus.map(\.title), ["Book the dentist"])
        XCTAssertEqual(dashboard.focus.first?.must, true)
        XCTAssertEqual(dashboard.people.first?.title, "Priya")
        XCTAssertNotNil(dashboard.people.first?.daysSinceContact)
        XCTAssertEqual(dashboard.people.first?.cadenceDays, 30)
        let project = try XCTUnwrap(dashboard.projects.first)
        XCTAssertEqual(project.title, "Garden app")
        XCTAssertEqual(project.counts?.doing, 1)
        XCTAssertEqual(project.counts?.ideas, 1)
        XCTAssertEqual(dashboard.projectWork.map(\.title), ["Sketch the beds"])
        XCTAssertEqual(dashboard.inbox.first?.suggestedTitle, "Sort out the ISA")
        let question = try XCTUnwrap(dashboard.waiting.first)
        XCTAssertTrue(question.isQuestion)
        XCTAssertEqual(question.options, ["Warburtons Protein Power", "Fitbakes bagels"])
        XCTAssertEqual(dashboard.captures.first?.rawText, "remember milk")
        XCTAssertEqual(dashboard.goals.first?.title, "Run a half marathon")
        XCTAssertEqual(dashboard.habits.first?.title, "Read more")
    }

    func testDecodesTodayEverythingProjectAndItem() throws {
        let day = try XCTUnwrap(try fixture("today").data).decode(PlatformDay.self)
        XCTAssertEqual(day.tasks.map(\.title), ["Book the dentist"])
        XCTAssertNotNil(day.tomorrow)
        let everything = try XCTUnwrap(try fixture("all").data).decode([PlatformItem].self)
        XCTAssertEqual(Set(everything.map(\.type)), ["todo", "person", "project", "idea", "goal", "habit", "inbox"])
        let dentist = try XCTUnwrap(everything.first { $0.title == "Book the dentist" })
        XCTAssertEqual(dentist.noteCount, 1)
        XCTAssertNotNil(dentist.remindAt.flatMap(parseISODate))
        let project = try XCTUnwrap(try fixture("project").data).decode(ProjectView.self)
        XCTAssertEqual(project.cards.first { $0.boardColumn == "doing" }?.title, "Sketch the beds")
        XCTAssertEqual(project.ideas.map(\.title), ["Watering reminders"])
        let item = try XCTUnwrap(try fixture("item").data).decode(PlatformItem.self)
        XCTAssertEqual(item.notes?.map(\.text), ["Ask about the filling"])
    }

    func testOperationResultIsATrackedAction() throws {
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(atlasFixtures.utf8)) as? [String: Any])
        let request = try mobileDecoder().decode(TrackedRequest.self, from: JSONSerialization.data(withJSONObject: all["operation"]!))
        XCTAssertTrue(request.isAction)
        XCTAssertEqual(request.status, "completed")
        XCTAssertEqual(request.summary, "Pinned “Book the dentist”")
        XCTAssertEqual(request.revision, 2)
        let model = AppModel()
        model.requests = [request]
        XCTAssertTrue(model.visibleRequests.isEmpty, "finished edits stay out of Activity")
    }

    func testReminderLinesMatchTheShortcutFormat() throws {
        var components = DateComponents(); components.year = 2026; components.month = 11; components.day = 4
        components.hour = 9; components.minute = 30; components.timeZone = TimeZone(identifier: "Europe/London")
        let due = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        let open = ReminderLine(done: false, due: due, url: "https://atlas.nikhil.ing/i/abc123", title: "Call the bank")
        let parts = open.line.components(separatedBy: " | ")
        XCTAssertEqual(parts[0], "open")
        XCTAssertEqual(parseISODate(parts[1]), due)
        XCTAssertEqual(parts[2], "https://atlas.nikhil.ing/i/abc123")
        XCTAssertEqual(parts[3], "Call the bank")
        XCTAssertEqual(open.editKey, "https://atlasnikhiling/i/abc123")
        let done = ReminderLine(done: true, due: due, url: nil, title: "Old v1.2 thing\nsecond line")
        XCTAssertEqual(done.line, "done |  |  | Old v1.2 thing second line")
        XCTAssertEqual(done.editKey, "Old v12 thing\nsecond line")
    }

    func testReminderResponseKeepsEditKeysVerbatim() throws {
        let json = #"{"device_actions":[{"type":"reminder","title":"Pay rent","notes":"","link":"https://atlas.nikhil.ing/i/x1","due_at":"2026-11-04T09:00+00:00","due_text":"4 November 2026 at 09:00","due_in_minutes":75}],"edits":{"https://atlasnikhiling/i/a_b":{"op":"move","due_in_minutes":5},"Some_title":{"op":"delete"}},"changes":["✅ Gym"],"nudge":null}"#
        let response = try JSONDecoder().decode(ReminderSyncResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.deviceActions.first?.dueInMinutes, 75)
        XCTAssertEqual(response.edits["https://atlasnikhiling/i/a_b"]?.op, "move")
        XCTAssertEqual(response.edits["https://atlasnikhiling/i/a_b"]?.dueInMinutes, 5)
        XCTAssertEqual(response.edits["Some_title"]?.op, "delete")
        XCTAssertEqual(response.changes, ["✅ Gym"])
        XCTAssertNil(response.nudge)
    }

    func testWidgetSnapshotFromTheRealDay() throws {
        let day = try XCTUnwrap(try fixture("today").data).decode(PlatformDay.self)
        let dashboard = try XCTUnwrap(try fixture("dashboard").data).decode(Dashboard.self)
        let snapshot = WidgetSnapshot.build(day: day, dashboard: dashboard)
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Book the dentist"])
        XCTAssertEqual(snapshot.tasks.first?.must, true)
        XCTAssertEqual(snapshot.focus.map(\.title), ["Book the dentist"])
        XCTAssertEqual(snapshot.waitingCount, 1)
        XCTAssertEqual(snapshot.openTasks.count, 1)

        // The store writes to the App Group container (Application Support in an unsigned build).
        SnapshotStore.save(snapshot)
        XCTAssertEqual(SnapshotStore.load()?.tasks, snapshot.tasks)
        SnapshotStore.markDone(try XCTUnwrap(snapshot.tasks.first).id)
        XCTAssertEqual(SnapshotStore.load()?.openTasks.count, 0)
        XCTAssertEqual(SnapshotStore.load()?.focus.count, 0)
        SnapshotStore.clear()
        XCTAssertNil(SnapshotStore.load())
    }

    func testRoutesFromWidgetsLinksAndOldScheme() {
        XCTAssertEqual(AppRouter.route(URL(string: "atlas://today")!), .today)
        XCTAssertEqual(AppRouter.route(URL(string: "atlas://talk")!), .talk)
        XCTAssertEqual(AppRouter.route(URL(string: "atlas://item/abc")!), .item("abc"))
        XCTAssertEqual(AppRouter.route(URL(string: "atlas://project/p1")!), .project("p1"))
        XCTAssertEqual(AppRouter.route(URL(string: "noodle://request/r1")!), .request("r1"))
        XCTAssertNil(AppRouter.route(URL(string: "https://example.com/today")!))
        XCTAssertNil(AppRouter.route(URL(string: "atlas://item")!))
    }

    func testSpokenDaySummary() throws {
        let day = try XCTUnwrap(try fixture("today").data).decode(PlatformDay.self)
        XCTAssertTrue(WhatsOnTodayIntent.summary(day).contains("On your list: Book the dentist."))
        let empty = PlatformDay(date: "2026-11-03", today: "2026-11-03", dayEnds: nil, tasks: [], overdue: [], leftovers: [], timed: [])
        XCTAssertEqual(WhatsOnTodayIntent.summary(empty), "Nothing planned today. A clear day.")
        XCTAssertEqual(AddToAtlasIntent.spoken("✅ Book the dentist\n⏰ Fri 9:00"), "Book the dentist.  Fri 9:00")
    }

    func testInvalidationEventRefreshesScreens() async throws {
        final class Transport: MobileTransport {
            func state() async throws -> MobileState { MobileState(requests: [], notifications: [], cursor: 1) }
            func events(after cursor: Int, connected: @escaping () -> Void, receive: @escaping (EventFrame) async throws -> Void) async throws {}
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sync = MobileSync(transport: Transport(), cache: StateCache(directory: directory), scope: "test")
        var invalidated = 0
        sync.onInvalidated = { invalidated += 1 }
        try await sync.accept(EventFrame(id: "5", type: "source.invalidated",
            data: #"{"id":"00000000000000000005","sequence":5,"type":"source.invalidated","payload":{"sources":["all"]}}"#))
        XCTAssertEqual(invalidated, 1)
        XCTAssertEqual(sync.projection.state.cursor, 5)
    }
}
