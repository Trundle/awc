import XCTest

import Libawc
import Wlroots
import testHelpers


public final class ConfigTests: XCTestCase {
    func testBuildFullLayout() {
        withConfig(Bundle.module, "full") {
            let view = TestView()
            let stack = Stack.singleton(view)
            let box = wlr_box(x: 0, y: 0, width: 1024, height: 768)

            let layout: AnyLayout<TestView, ()> = try! buildLayout($0.layout, $0.number_of_layout_ops)

            XCTAssertNil(layout.nextLayout())

            let workspace = Workspace(tag: "test", layout: layout)
            let output = Output(data: (), workspace: workspace)
            let arrangement = layout.doLayout(dataProvider: NoDataProvider(), output: output, stack: stack, box: box)
            XCTAssertEqual(arrangement.count, 1)
            XCTAssertEqual(arrangement[0].0, view)
            XCTAssertEqual(arrangement[0].2, box)
        }
    }

    func testBuildMagnifiedLayout() {
        withConfig(Bundle.module, "magnify") {
            let layout: AnyLayout<TestView, ()> = try! buildLayout($0.layout, $0.number_of_layout_ops)

            let wrapped = Mirror(reflecting: layout).descendant("wrapped")
            XCTAssertTrue(wrapped! is Magnified<TwoPane<TestView, ()>>)
        }
    }
}
