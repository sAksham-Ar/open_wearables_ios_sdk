import XCTest
@testable import OpenWearablesHealthSDK

final class SummaryReadTests: XCTestCase {
    func testReadsOnlyPairedUserAndWhitelistedQuery() {
        withIsolatedSDK { sdk, _ in
            StubURLProtocol.install { _ in .status(200, #"{"data":[]}"#) }
            var outcome: Result<Data, Error>?
            sdk.fetchSummary(section: "activity", query: ["start_date": "2026-10-01", "user_id": "someone-else"]) {
                outcome = $0
            }
            XCTAssertTrue(waitUntil { outcome != nil })
            let request = StubURLProtocol.requests.first
            XCTAssertEqual(request?.httpMethod, "GET")
            XCTAssertEqual(request?.url?.path, "/api/v1/sdk/users/test-user/summaries/activity")
            XCTAssertFalse(request?.url?.query?.contains("someone-else") ?? true)
            XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        }
    }

    func testRefreshesOnceThenReturnsSummary() {
        withIsolatedSDK { sdk, _ in
            StubURLProtocol.install { request in
                if request.url?.path.hasSuffix("/token/refresh") == true {
                    return .status(200, #"{"access_token":"access-2","refresh_token":"refresh-2"}"#)
                }
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
                    ? .status(200, "null") : .status(401)
            }
            var outcome: Result<Data, Error>?
            sdk.fetchSummary(section: "vitals", query: [:]) { outcome = $0 }
            XCTAssertTrue(waitUntil { outcome != nil })
            guard case .success(let data)? = outcome else { return XCTFail("Summary should succeed") }
            XCTAssertEqual(String(data: data, encoding: .utf8), "null")
            XCTAssertEqual(StubURLProtocol.requests(matching: "/token/refresh").count, 1)
            XCTAssertEqual(StubURLProtocol.requests(matching: "/summaries/vitals").count, 2)
        }
    }

    func testSecondUnauthorizedDoesNotLoop() {
        withIsolatedSDK { sdk, _ in
            StubURLProtocol.install { request in
                request.url?.path.hasSuffix("/token/refresh") == true
                    ? .status(200, #"{"access_token":"access-2","refresh_token":"refresh-2"}"#)
                    : .status(401)
            }
            var outcome: Result<Data, Error>?
            sdk.fetchSummary(section: "sleep", query: [:]) { outcome = $0 }
            XCTAssertTrue(waitUntil { outcome != nil })
            guard case .failure(let error)? = outcome else { return XCTFail("Must return unauthorized") }
            XCTAssertEqual((error as NSError).code, 401)
            XCTAssertEqual(StubURLProtocol.requests(matching: "/token/refresh").count, 1)
        }
    }
}
