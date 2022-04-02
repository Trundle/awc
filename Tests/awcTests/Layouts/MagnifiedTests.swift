import XCTest

import Libawc
import Wlroots
import testHelpers

fileprivate typealias Arrangement = [(TestView, Set<ViewAttribute>, wlr_box)]

public final class MagnifiedTests: XCTestCase {
    private let output = Output(data: (), workspace: Workspace(tag: "test", layout: TestLayout()))
    private let mainView = TestView(id: 0)
    private let secondView = TestView(id: 1)

    func testDoesNotMagnifyMainView() {
        let stack = Stack(up: List.empty, focus: mainView, down: List(collection: [secondView]))
        let arrangement: Arrangement = [
            (mainView, [.focused], wlr_box(x: 0, y: 0, width: 100, height: 50)),
            (secondView, [], wlr_box(x: 100, y: 0, width: 100, height: 50))
        ]
        let layout = createLayout(arrangement)

        let result = layout.doLayout(
            dataProvider: NoDataProvider(),
            output: output,
            stack: stack,
            box: wlr_box(x: 0, y: 0, width: 200, height: 50))

        XCTAssertEqual(
            arrangement.map(ArrangementEqWrapper.init),
            result.map(ArrangementEqWrapper.init))
    }

    func testMagnifiedViewDoesntOvershootRightBoundary() {
        let arrangement: Arrangement = [
            (mainView, [], wlr_box(x: 0, y: 0, width: 100, height: 50)),
            (secondView, [.focused], wlr_box(x: 100, y: 0, width: 100, height: 50))
        ]
        let expected: Arrangement = [
            (mainView, [], wlr_box(x: 0, y: 0, width: 100, height: 50)),
            (secondView, [.focused], wlr_box(x: 50, y: 0, width: 150, height: 50))
        ]
        let box = wlr_box(x: 0, y: 0, width: 200, height: 50)
        self.validateSecondaryViewMagnification(arrangement: arrangement, expected: expected, box: box)
    }

    func testMagnifiedViewDoesntOvershootLeftBoundary() {
        let arrangement: Arrangement = [
            (secondView, [.focused], wlr_box(x: 0, y: 0, width: 100, height: 50)),
            (mainView, [], wlr_box(x: 0, y: 100, width: 100, height: 50))
        ]
        let expected: Arrangement = [
            (mainView, [], wlr_box(x: 0, y: 100, width: 100, height: 50)),
            (secondView, [.focused], wlr_box(x: 0, y: 0, width: 150, height: 50))
        ]
        let box = wlr_box(x: 0, y: 0, width: 200, height: 50)
        self.validateSecondaryViewMagnification(arrangement: arrangement, expected: expected, box: box)
    }

    func testMagnifiedViewDoesntOvershootBottomBoundary() {
        let arrangement: Arrangement = [
            (mainView, [], wlr_box(x: 0, y: 00, width: 100, height: 100)),
            (secondView, [.focused], wlr_box(x: 100, y: 50, width: 100, height: 100))
        ]
        let expected: Arrangement = [
            (mainView, [], wlr_box(x: 0, y: 0, width: 100, height: 100)),
            (secondView, [.focused], wlr_box(x: 50, y: 25, width: 150, height: 150))
        ]
        let box = wlr_box(x: 0, y: 0, width: 200, height: 200)
        self.validateSecondaryViewMagnification(arrangement: arrangement, expected: expected, box: box)
    }

    func testCentersMagnifiedView() {
        let arrangement: Arrangement = [
            (mainView, [], wlr_box(x: 0, y: 0, width: 100, height: 50)),
            (secondView, [.focused], wlr_box(x: 100, y: 25, width: 100, height: 50))
        ]
        let expected: Arrangement = [
            (mainView, [], wlr_box(x: 0, y: 0, width: 100, height: 50)),
            (secondView, [.focused], wlr_box(x: 75, y: 13, width: 150, height: 75))
        ]
        let box = wlr_box(x: 0, y: 0, width: 400, height: 100)
        self.validateSecondaryViewMagnification(arrangement: arrangement, expected: expected, box: box)
    }

    private func validateSecondaryViewMagnification(
        arrangement: Arrangement, 
        expected: Arrangement,
        box: wlr_box
    ) {
        let stack = Stack(up: List(collection: [mainView]), focus: secondView, down: List.empty)
        let layout = createLayout(arrangement)

        let result = layout.doLayout(
            dataProvider: NoDataProvider(),
            output: output,
            stack: stack,
            box: box)

        XCTAssertEqual(
            expected.map(ArrangementEqWrapper.init),
            result.map(ArrangementEqWrapper.init))
    }

    private func createLayout(_ arrangement: Arrangement) -> Magnified<TestLayout> {
        Magnified(
            layout: TestLayout(arrangementToReturn: arrangement),
            magnification: 1.5)
    }
}
