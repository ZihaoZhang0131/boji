import XCTest
import BojiEstimation

final class KeychainTests: XCTestCase {
    func testDeviceOnlyCredentialRoundTripAndEndpointIsolation() async throws {
        let store = KeychainCredentials(), url = URL(string: "https://" + UUID().uuidString + ".invalid")!
        let other = URL(string: "https://" + UUID().uuidString + ".invalid")!
        let token = UUID().uuidString + UUID().uuidString
        try await store.setToken(token, for: url)
        let actual = try await store.token(for: url), absent = try await store.token(for: other)
        XCTAssertEqual(actual, token); XCTAssertNil(absent)
        try await store.setToken(nil, for: url)
        let removed = try await store.token(for: url); XCTAssertNil(removed)
    }
}
