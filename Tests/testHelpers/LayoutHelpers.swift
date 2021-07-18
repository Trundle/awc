import Libawc
import Wlroots

public class TestView {
    public init() {
    }
}

extension TestView: Equatable {
    public static func ==(lhs: TestView, rhs: TestView) -> Bool {
        lhs === rhs
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
