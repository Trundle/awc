import Wlroots


public protocol AnyLayoutMapper {
    associatedtype View
    associatedtype OutputData

    func flatMap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData>
    where L.View == View, L.OutputData == OutputData
}


/// A wrapper for some `Layout` that is only parametrized over `View` and `OutputData`.
public class AnyLayout<View, OutputData>: Layout {
    public var description: String {
        get {
            fatalError()
        }
    }

    public func flatMap<M: AnyLayoutMapper>(_ mapper: M) -> AnyLayout<View, OutputData>
    where M.View == View, M.OutputData == OutputData
    {
        fatalError()
    }

    public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        fatalError()
    }

    public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        fatalError()
    }

    public func nextLayout() -> Self? {
        fatalError()
    }

    public func firstLayout() -> Self {
        fatalError()
    }

    public func expand() -> Self {
        fatalError()
    }

    public func shrink() -> Self {
        fatalError()
    }
}

public extension AnyLayout {
    static func wrap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData> 
    where L.View == View, L.OutputData == OutputData 
    {
        AnyLayoutImpl(layout)
    }
}

private final class AnyLayoutImpl<L: Layout>: AnyLayout<L.View, L.OutputData> {
    override public var description: String {
        get {
            wrapped.description
        }
    }

    private let wrapped: L

    init(_ wrapped: L) {
        self.wrapped = wrapped
    }

    override public func flatMap<M: AnyLayoutMapper>(_ mapper: M) -> AnyLayout<View, OutputData>
    where M.View == View, M.OutputData == OutputData
    {
        mapper.flatMap(self.wrapped)
    }

    override public func emptyLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        self.wrapped.emptyLayout(dataProvider: dataProvider, output: output, box:box)
    }

    override public func doLayout<L: Layout>(
        dataProvider: ExtensionDataProvider,
        output: Output<L>,
        stack: Stack<L.View>,
        box: wlr_box
    ) -> [(L.View, Set<ViewAttribute>, wlr_box)] where L.View == View, L.OutputData == OutputData {
        self.wrapped.doLayout(dataProvider: dataProvider, output: output, stack: stack, box: box)
    }

    override public func nextLayout() -> AnyLayoutImpl<L>? {
        guard let nextLayout = self.wrapped.nextLayout() else { return nil }
        return AnyLayoutImpl(nextLayout)
    }

    override public func firstLayout() -> AnyLayoutImpl<L> {
        AnyLayoutImpl(self.wrapped.firstLayout())
    }

    override public func expand() -> AnyLayoutImpl<L> {
        AnyLayoutImpl(self.wrapped.expand())
    }

    override public func shrink() -> AnyLayoutImpl<L> {
        AnyLayoutImpl(self.wrapped.shrink())
    }
}
