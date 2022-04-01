import XCTest

import Libawc

public final class ListTests: XCTestCase {
    func testEmptyIsEmpty() {
        XCTAssertTrue(List<Int>.empty.isEmpty)
    }

    func testFilterAllFiltered() {
        let list = List(collection: 1...10)

        let filtered = list.filter { _ in false }

        XCTAssertTrue(filtered.isEmpty)
    }

    func testFilterNonFiltered() {
        let list = List(collection: 1...10)

        let filtered = list.filter { _ in true }

        XCTAssertEqual(list, filtered)
    }

    func testReverse() {
        let list = List(collection: 1...10)
        XCTAssertEqual(list.reverse(), List(collection: (1...10).reversed()))
        XCTAssertEqual(list.reverse().reverse(), list)
    }

    func testContainsReturnsFalseForEmptyList() {
        XCTAssertFalse(List<Int>.empty.contains(42))
    }

    func testContainsSingleton() {
        let list = List(collection: [42])

        XCTAssertFalse(list.contains(23))
        XCTAssertTrue(list.contains(42))
    }
}
