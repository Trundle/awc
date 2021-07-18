import XCTest

import Libawc
import Wlroots
import testHelpers


final class TestLayout: Layout {
    typealias View = TestView
    typealias OutputData = ()

    var emptyLayoutCalled: Bool = false
    var doLayoutCalled: Bool = false
    var firstLayoutCalled: Bool = false
    var nextLayoutCalled: Bool = false
    var expandCalled: Bool = false
    var shrinkCalled: Bool = false

    func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        self.emptyLayoutCalled = true
        return []
    }

    func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        self.doLayoutCalled = true
        return []
    }

    func firstLayout() -> TestLayout {
        self.firstLayoutCalled = true
        return self
    }
    
    func nextLayout() -> TestLayout? {
        self.nextLayoutCalled = true
        return nil
    }
    
    func expand() -> TestLayout {
        self.expandCalled = true
        return self
    }

    func shrink() -> TestLayout {
        self.shrinkCalled = true
        return self
    } 
}


public class AnyLayoutTests: XCTestCase {
    func testForwardsEmptyLayout() {
        let (layout, wrappedLayout) = self.createLayout()

        let box = wlr_box(x: 0, y: 0, width: 1024, height: 768)
        let workspace = Workspace(tag: "test", layout: layout)
        let output = Output(data: (), workspace: workspace)

        let _ = layout.emptyLayout(dataProvider: NoDataProvider(), output: output, box: box)

        XCTAssertTrue(wrappedLayout.emptyLayoutCalled)
    }

    func testForwardsDoLayout() {
        let (layout, wrappedLayout) = self.createLayout()

        let view = TestView()
        let stack = Stack.singleton(view)
        let box = wlr_box(x: 0, y: 0, width: 1024, height: 768)
        let workspace = Workspace(tag: "test", layout: layout)
        let output = Output(data: (), workspace: workspace)

        let _ = layout.doLayout(dataProvider: NoDataProvider(), output: output, stack: stack, box: box)

        XCTAssertTrue(wrappedLayout.doLayoutCalled)
    }

    func testForwardsFirstLayout() {
        let (layout, wrappedLayout) = self.createLayout()

        let _ = layout.firstLayout()

        XCTAssertTrue(wrappedLayout.firstLayoutCalled)
    }

    func testForwardsNextLayout() {
        let (layout, wrappedLayout) = self.createLayout()

        let _ = layout.nextLayout()

        XCTAssertTrue(wrappedLayout.nextLayoutCalled)
    }

    func testForwardsExpand() {
        let (layout, wrappedLayout) = self.createLayout()

        let _ = layout.expand()

        XCTAssertTrue(wrappedLayout.expandCalled)        
    }

    func testForwardsShrink() {
        let (layout, wrappedLayout) = self.createLayout()

        let _ = layout.shrink()

        XCTAssertTrue(wrappedLayout.shrinkCalled)
    }

    func createLayout() -> (AnyLayout<TestView, ()>, TestLayout) {
        let wrappedLayout = TestLayout()
        let layout: AnyLayout<TestView, ()> = AnyLayout.wrap(wrappedLayout)

        return (layout, wrappedLayout)
    }

    public static var allTests = [
        ("testForwardsEmptyLayout", testForwardsEmptyLayout),
        ("testForwardsDoLayout", testForwardsDoLayout),
        ("testForwardsFirstLayout", testForwardsFirstLayout),
        ("testForwardsNextLayout", testForwardsNextLayout),
        ("testForwardsExpand", testForwardsExpand),
        ("testForwardsShrink", testForwardsShrink),
    ]
}
