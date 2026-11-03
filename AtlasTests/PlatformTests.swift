import XCTest
import SwiftUI
@testable import Atlas

private final class PlatformProtocol: URLProtocol {
    static var handler: ((URLRequest, [String: Any]) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
                }
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let response = try Self.handler!(request, body)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class PlatformTests: XCTestCase {
    private let task = #"{"id":"t1","title":"Book the dentist","type":"todo","status":"active","area":"health","plan_day":"2026-10-17","due_date":"2026-10-17","must":true}"#
    private func api() -> AtlasAPI {
        let api = AtlasAPI(credentials: Credentials(token: "test"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlatformProtocol.self]
        api.session = URLSession(configuration: configuration)
        return api
    }
    private func fixture(_ body: [String: Any]) throws -> Data {
        let source = body["source"] as? String
        let query = body["query"] as? [String: Any]
        let data: String
        if source == "dashboard" {
            data = "{\"today\":\"2026-10-17\",\"day_ends\":null,\"focus\":[\(task)],\"people\":[],\"projects\":[],\"waiting\":[{\"id\":\"q1\",\"kind\":\"question\",\"handler\":\"shopping\",\"question\":\"Which protein bread?\",\"options\":[\"Warburtons\",\"Fitbakes\"],\"summary\":null,\"expires_at\":null,\"run_at\":null}]}"
        } else if source == "calendar" {
            data = #"[{"id":"e1","summary":"Coffee with Sam","start":{"dateTime":"2026-10-17T14:00:00+01:00"}}]"#
        } else if query?["scope"] as? String == "today" {
            data = "{\"date\":\"2026-10-17\",\"today\":\"2026-10-17\",\"day_ends\":null,\"tasks\":[\(task)],\"overdue\":[],\"leftovers\":[],\"timed\":[]}"
        } else {
            data = "[\(task),{\"id\":\"t2\",\"title\":\"A calmer place to think\",\"type\":\"project\",\"status\":\"active\"}]"
        }
        return Data("{\"read_id\":\"read\",\"source\":\"\(source ?? "items")\",\"data\":\(data),\"freshness\":\"fresh\",\"refreshing\":false,\"verified_at\":\"2026-10-17T12:00:00Z\"}".utf8)
    }
    func testReadContractsAndOfflineRetention() async throws {
        let api = api(); let store = PlatformStore()
        PlatformProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.path, "/api/mobile/reads")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
            return try self.fixture(body)
        }
        await store.refresh(api: api)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.day?.tasks.first?.planDay, "2026-10-17")
        XCTAssertEqual(store.calendar.first?.start.dateTime, "2026-10-17T14:00:00+01:00")
        XCTAssertEqual(store.dashboard?.waiting.first?.options, ["Warburtons", "Fitbakes"])
        XCTAssertTrue(store.errors.isEmpty)
        PlatformProtocol.handler = { _, _ in throw URLError(.notConnectedToInternet) }
        await store.refresh(api: api)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.errors.count, 4)
        XCTAssertEqual(store.dashboard?.focus.count, 1, "the last good dashboard is kept offline")
        store.reset()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.day)
        XCTAssertNil(store.dashboard)
        XCTAssertTrue(store.calendar.isEmpty)
    }
    func testUncertainMutationReusesIDAndWaitsForCompletion() async throws {
        let api = api(); let store = PlatformStore()
        let item = try mobileDecoder().decode(PlatformItem.self, from: Data(task.utf8))
        var submitted: String?
        PlatformProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.path, "/api/mobile/operations")
            XCTAssertEqual(body["handler"] as? String, "items.update")
            XCTAssertEqual((body["input"] as? [String: Any])?["item_id"] as? String, "t1")
            submitted = body["request_id"] as? String
            throw URLError(.networkConnectionLost)
        }
        let first = await store.update(item, fields: ["status": "done"], api: api)
        XCTAssertNil(first)
        XCTAssertNil(store.pending[item.id])
        PlatformProtocol.handler = { _, body in
            XCTAssertEqual(body["request_id"] as? String, submitted)
            return Data("{\"id\":\"\(submitted!)\",\"kind\":\"operation\",\"status\":\"queued\",\"title\":\"Complete task\",\"text\":\"\",\"summary\":\"\",\"created_at\":\"now\",\"updated_at\":\"now\"}".utf8)
        }
        let accepted = await store.update(item, fields: ["status": "done"], api: api)
        XCTAssertNotNil(accepted)
        XCTAssertNotNil(store.pending[item.id])
        XCTAssertFalse(store.reconcile([accepted!]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(accepted!)) as? [String: Any])
        object["status"] = "completed"
        let completed = try JSONDecoder().decode(TrackedRequest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(store.reconcile([completed]))
        XCTAssertNil(store.pending[item.id])
    }
    func testRenderPlatformScreens() async throws {
        let api = api(); let store = PlatformStore()
        PlatformProtocol.handler = { _, body in try self.fixture(body) }
        await store.refresh(api: api)
        let model = AppModel(); model.credentials = Credentials(token: "preview")
        for today in [true, false] {
            for dark in [false, true] {
                let controller = UIHostingController(rootView: NavigationStack {
                    PlatformView(store: store, today: today)
                }.environmentObject(model).tint(Theme.accent).preferredColorScheme(dark ? .dark : .light))
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = controller; window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(today ? "Today" : "Everything")-\(dark ? "dark" : "light")"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true
            }
        }
    }
}
