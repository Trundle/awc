import Foundation
import XCTest

import awc_config

public final class ConfigTests: XCTestCase {
    func testEmptyConfig() {
        withConfig("empty") {
            XCTAssertEqual($0.borderWidth, 2)
            XCTAssertEqual($0.numberOfKeyBindings, 0)
        }
    }

    func testButtonBinding() {
        withConfig("button_binding") {
            XCTAssertEqual($0.numberOfButtonBindings, 1)
            XCTAssertEqual($0.buttonBindings[0].mods, 8)
        }
    }

    func testDuplicatedModifiers() {
        withConfig("duplicated_mods") {
            XCTAssertEqual($0.numberOfKeyBindings, 1)
            XCTAssertEqual($0.keyBindings[0].mods, 8)
        }
    }

    private func withConfig(_ fixtureName: String, _ block: (AwcConfig) -> ()) {
        let configPath = Bundle.module.path(forResource: fixtureName, ofType: "dhall", inDirectory: "Fixtures")!

        var awcConfig = AwcConfig()
        if let error = awcLoadConfig(configPath, &awcConfig) {
            defer {
                free(error)
            }
            XCTFail(String(cString: error))
        } else {
            defer {
                awcConfigFree(&awcConfig)
            }
            block(awcConfig)
        }
    }

    public static var allTests = [
        ("testEmptyConfig", testEmptyConfig),
        ("testButtonBinding", testButtonBinding),
        ("testDuplicatedModifiers", testDuplicatedModifiers),
    ]
}