import Libawc
import Wlroots

public class TestView {
    public let id: Int

    convenience public init() {
        self.init(id: 0)
    }

    public init(id: Int) {
        self.id = id
    }
}

extension TestView: Equatable {
    public static func ==(lhs: TestView, rhs: TestView) -> Bool {
        lhs === rhs
    }
}

extension TestView: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

extension TestView: CustomStringConvertible {
    public var description: String {
        String(id)
    }
}

extension wlr_box: Equatable {
    public static func ==(lhs: wlr_box, rhs: wlr_box) -> Bool {
        (lhs.x, lhs.y, lhs.width, lhs.height) == (rhs.x, rhs.y, rhs.width, rhs.height)
    }
}

public class NoDataProvider: ExtensionDataProvider {
    public init() {
    }

    public func getExtensionData<D>() -> D? {
        nil
    }
}


public final class TestLayout: Layout {
    public typealias View = TestView
    public typealias OutputData = ()

    public var description: String {
        get {
            "TestLayout"
        }
    }

    public var emptyLayoutCalled: Bool = false
    public var doLayoutCalled: Bool = false
    public var firstLayoutCalled: Bool = false
    public var nextLayoutCalled: Bool = false
    public var expandCalled: Bool = false
    public var shrinkCalled: Bool = false

    private let arrangementToReturn: [(TestView, Set<ViewAttribute>, wlr_box)]

    public init(arrangementToReturn: [(TestView, Set<ViewAttribute>, wlr_box)] = []) {
        self.arrangementToReturn = arrangementToReturn
    }

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        self.emptyLayoutCalled = true
        return []
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        self.doLayoutCalled = true
        return arrangementToReturn
    }

    public func firstLayout() -> TestLayout {
        self.firstLayoutCalled = true
        return self
    }

    public func nextLayout() -> TestLayout? {
        self.nextLayoutCalled = true
        return nil
    }

    public func expand() -> TestLayout {
        self.expandCalled = true
        return self
    }

    public func shrink() -> TestLayout {
        self.shrinkCalled = true
        return self
    }
}

// As tuples cannot conform to protocols, this is a convenience struct to compare arrangements
public struct ArrangementEqWrapper: Equatable {
    let view: TestView
    let attributes: Set<ViewAttribute>
    let box: wlr_box

    public init(_ tuple: (TestView, Set<ViewAttribute>, wlr_box)) {
        self.view = tuple.0
        self.attributes = tuple.1
        self.box = tuple.2
    }
}
