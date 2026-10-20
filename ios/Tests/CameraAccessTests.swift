import XCTest
import AVFoundation
@testable import Boji

@MainActor final class CameraAccessTests: XCTestCase {
    private final class Device: CameraDevice {
        var available = true
        var authorization: AVAuthorizationStatus = .notDetermined
        var allow = false
        var requests = 0
        func requestAccess() async -> Bool { requests += 1; return allow }
    }
    func testUnavailableDeniedRestrictedAndFirstPermission() async {
        let device = Device(); device.available = false
        let unavailable = await CameraAccess.authorize(using: device)
        XCTAssertEqual(unavailable, .unavailable); XCTAssertEqual(device.requests, 0)
        device.available = true
        for status in [AVAuthorizationStatus.denied, .restricted] {
            device.authorization = status
            let result = await CameraAccess.authorize(using: device)
            XCTAssertEqual(result, .denied); XCTAssertEqual(device.requests, 0)
        }
        device.authorization = .notDetermined
        let refused = await CameraAccess.authorize(using: device)
        XCTAssertEqual(refused, .denied); XCTAssertEqual(device.requests, 1)
        device.allow = true
        let accepted = await CameraAccess.authorize(using: device)
        XCTAssertEqual(accepted, .authorized); XCTAssertEqual(device.requests, 2)
        device.authorization = .authorized
        let existing = await CameraAccess.authorize(using: device)
        XCTAssertEqual(existing, .authorized); XCTAssertEqual(device.requests, 2)
    }
}
