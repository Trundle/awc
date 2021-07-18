import XCTest

import awc_config
import testHelpers

public final class ConfigTests: XCTestCase {
    func testEmptyConfig() {
        withConfig(Bundle.module, "empty") {
            XCTAssertEqual($0.border_width, 2)
            XCTAssertEqual($0.number_of_key_bindings, 0)
        }
    }

    func testButtonBinding() {
        withConfig(Bundle.module, "button_binding") {
            XCTAssertEqual($0.number_of_button_bindings, 1)
            XCTAssertEqual($0.button_bindings[0].number_of_mods, 3)
        }
    }

    public static var allTests = [
        ("testEmptyConfig", testEmptyConfig),
        ("testButtonBinding", testButtonBinding),
    ]
}
