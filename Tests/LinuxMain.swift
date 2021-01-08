import XCTest

import awcTests
import awcConfigTests

var tests = [XCTestCaseEntry]()
tests += awcTests.allTests()
tests += awcConfigTests.allTests()
XCTMain(tests)
