import Foundation
import XCTest

import awc_config

public func withConfig(_ bundle: Bundle, _ fixtureName: String, _ block: (AwcConfig) -> ()) {
    let configPath = bundle.path(forResource: fixtureName, ofType: "dhall", inDirectory: "Fixtures")!

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
