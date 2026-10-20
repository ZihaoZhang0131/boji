import XCTest
import UIKit
@testable import Boji

final class ProjectConfigurationTests: XCTestCase {
    @MainActor
    func testBundledPixelFontIsRegistered() {
        XCTAssertNotNil(UIFont(name: PixelTheme.fontName, size: 16))
    }
    func testMinimumSupportedSystemIsIOS17() throws {
        let appBundle = Bundle(for: ProjectConfigurationTests.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent()
        let bundle = try XCTUnwrap(Bundle(url: appBundle))
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "MinimumOSVersion") as? String, "17.0")
    }
}
