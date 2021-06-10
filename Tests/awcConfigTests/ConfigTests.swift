import Foundation
import XCTest

import awc_config

public final class ConfigTests: XCTestCase {
    func testEmptyConfig() {
        withConfig("empty") {
            XCTAssertEqual($0.border_width, 2)
            XCTAssertEqual($0.number_of_key_bindings, 0)
        }
    }

    func testButtonBinding() {
        withConfig("button_binding") {
            XCTAssertEqual($0.number_of_button_bindings, 1)
            XCTAssertEqual($0.button_bindings[0].number_of_mods, 3)
        }
    }

    private func withConfig(_ fixtureName: String, _ block: (AwcConfig) -> ()) {
        let configPath = Bundle.module.path(forResource: fixtureName, ofType: "dhall", inDirectory: "Fixtures")!

        var awcConfig = AwcConfig()
        if let error = awc_config_load(configPath, &awcConfig) {
            defer {
                awc_config_str_free(error)
            }
            XCTFail(String(cString: error))
        } else {
            defer {
                awc_config_free(&awcConfig)
            }
            block(awcConfig)
        }
    }

    public static var allTests = [
        ("testEmptyConfig", testEmptyConfig),
        ("testButtonBinding", testButtonBinding),
    ]
}
