import awc_config
import Libawc
import testHelpers
import Wlroots

import XCTest

private struct EqWrapper: Equatable {
    let view: TestView
    let attributes: Set<ViewAttribute>
    let box: wlr_box

    public init(_ tuple: (TestView, Set<ViewAttribute>, wlr_box)) {
        self.view = tuple.0
        self.attributes = tuple.1
        self.box = tuple.2
    }
}

public class ReflectedTests: XCTestCase {
    func testReflectsHorizontally() {
        let view = TestView()
        let arrangement: [(TestView, Set<ViewAttribute>, wlr_box)] = [
            (view, Set(), wlr_box(x: 0, y: 0, width: 100, height: 100))
        ]
        let expected = [
            (view, Set(), wlr_box(x: 100, y: 0, width: 100, height: 100))
        ].map { EqWrapper($0) }
        self.testLayoutWithSingleView(
            layout: Reflected(layout: TestLayout(arrangementToReturn: arrangement), direction: Horizontal),
            expectedResult: expected)
    }

    func testReflectsVertically() {
        let view = TestView()
        let arrangement: [(TestView, Set<ViewAttribute>, wlr_box)] = [
            (view, Set(), wlr_box(x: 0, y: 0, width: 200, height: 50))
        ]
        let expected = [
            (view, Set(), wlr_box(x: 0, y: 50, width: 200, height: 50))
        ].map { EqWrapper($0) }
        self.testLayoutWithSingleView(
            layout: Reflected(layout: TestLayout(arrangementToReturn: arrangement), direction: Vertical),
            expectedResult: expected)
    }

    private func testLayoutWithSingleView(
        layout: Reflected<TestLayout>, 
        expectedResult: [EqWrapper]
    ) {
        let view = TestView()
        let stack = Stack.singleton(view)
        let workspace = Workspace(tag: "test", layout: layout)
        let output = Output(data: (), workspace: workspace)
        let box = wlr_box(x: 0, y: 0, width: 200, height: 100)

        let result = layout.doLayout(dataProvider: NoDataProvider(), output: output, stack: stack, box: box)

        XCTAssertEqual(expectedResult, result.map { EqWrapper($0) })
    }
}
