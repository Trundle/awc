import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    [
        testCase(AnyLayoutTests.allTests),
        testCase(ConfigTests.allTests),
        testCase(ListTests.allTests),
    ]
}
#endif
