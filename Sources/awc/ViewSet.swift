import Libawc
import Wlroots

public class Output<L: Layout> {
    public let workspace: Workspace<L>
    public let data: L.OutputData
    // XXX should this moved to data?
    // The current surface arrangement
    public var arrangement: [(L.View, Set<ViewAttribute>, wlr_box)] = []

    init(data: L.OutputData,
         workspace: Workspace<L>
    ) {
        self.data = data
        self.workspace = workspace
    }

    /**
     * Returns a new `Output` instance, with the `workspace` property set to the given value.
     */
    public func copy(workspace: Workspace<L>) -> Output<L> {
        Output(data: self.data, workspace: workspace)
    }
}

extension Output: CustomStringConvertible {
    public var description: String {
        "Output { details = \(self.data), workspace = \(self.workspace) }"
    }
}


public class Workspace<L: Layout> {
    public let tag: String
    public let layout: L
    public let stack: Stack<L.View>?

    init(tag: String, layout: L, stack: Stack<L.View>? = nil) {
        self.tag = tag
        self.layout = layout
        self.stack = stack
    }

    public func replace(layout: L) -> Workspace<L> {
        Workspace(tag: self.tag, layout: layout, stack: self.stack)
    }

    public func replace(stack: Stack<L.View>?) -> Workspace<L> {
        Workspace(tag: self.tag, layout: self.layout, stack: stack)
    }
}

extension Workspace: CustomStringConvertible {
    public var description: String {
        """
        Workspace {
            tag = \(self.tag),
            layout = \(String(describing: self.layout)),
            stack = \(String(describing: self.stack))
        }
        """
    }
}


// Note that the `View` parameter is superfluous, it could also be expressed with a constraint such as
// "where L.View: Hashable", but unfortunately, that makes swift crash with an assertion error:
// swift::CanType (anonymous namespace)::SubstFunctionTypeCollector::getSubstitutedInterfaceType(
// swift::Lowering::AbstractionPattern, swift::CanType): Assertion `result && "substType was not
// bindable to abstraction pattern type?"' failed.
/// See https://bugs.swift.org/browse/SR-13849
public class ViewSet<L: Layout, View: Hashable> where L.View == View {
    // The output with the currently focused workspace
    public let current: Output<L>
    // Non-focused workspaces visible on outputs
    public let visible: [Output<L>]
    // The workspaces that are not visible anywhere
    public let hidden: [Workspace<L>]
    // Mapping of untiled views to their boxes (location + size)
    public let floating: Map<L.View, wlr_box>

    convenience init(current: Output<L>, hidden: [Workspace<L>] = []) {
        self.init(current: current, visible: [], hidden: hidden, floating: [:])
    }

    private init(current: Output<L>,
                 visible: [Output<L>],
                 hidden: [Workspace<L>],
                 floating: Map<L.View, wlr_box>) {
        self.current = current
        self.visible = visible
        self.hidden = hidden
        self.floating = floating
    }

    // MARK: Convenience methods for updating state

    func replace(current: Output<L>) -> ViewSet<L, View> {
        ViewSet(current: current, visible: self.visible, hidden: self.hidden, floating: self.floating)
    }

    func replace(floating: Map<L.View, wlr_box>) -> ViewSet<L, View> {
        ViewSet(current: self.current, visible: self.visible, hidden: self.hidden, floating: floating)
    }

    func replace(
        current: Output<L>,
        visible: [Output<L>],
        hidden: [Workspace<L>]
    ) -> ViewSet<L, View> {
        ViewSet(current: current, visible: visible, hidden: hidden, floating: self.floating)
    }

    /// Replaces the layout on the current workspace with the given layout.
    func replace(layout: L) -> ViewSet<L, View> {
        self.replace(current: self.current.copy(workspace: self.current.workspace.replace(layout: layout)))
    }

    func modify(_ f: (Stack<L.View>) -> Stack<L.View>?) -> ViewSet<L, View> {
        if let stack = self.current.workspace.stack {
            return self.replace(
                current: self.current.copy(workspace: self.current.workspace.replace(stack: f(stack))))
        }
        return self
    }

    func modifyOr(default: @autoclosure () -> Stack<L.View>?, _ f: (Stack<L.View>) -> Stack<L.View>?) -> ViewSet<L, View> {
        let withNewStack = { newStack in
            self.replace(current: self.current.copy(workspace: self.current.workspace.replace(stack: newStack)))
        }
        if let stack = self.current.workspace.stack {
            return withNewStack(f(stack))
        } else {
            return withNewStack(`default`())
        }
    }

    /// Finds the output that displays the given view.
    func findOutput(view: L.View) -> Output<L>? {
        for output in self.outputs() {
            if let stack = output.workspace.stack {
                if stack.contains(view) {
                    return output
                }
            }
        }
        return nil
    }

    /// Finds the workspace that displays the given view.
    func findWorkspace(view: L.View) -> Workspace<L>? {
        self.workspaces().first(where: { $0.stack?.contains(view) == true })
    }

    /// Removes the given view, if it exists.
    func remove(view: L.View) -> ViewSet<L, View> {
        let removeFromWorkspace: (Workspace<L>) -> Workspace<L> = {
            $0.replace(stack: $0.stack?.remove(view))
        }
        let removeFromOutput: (Output<L>) -> Output<L> = {
            $0.copy(workspace: removeFromWorkspace($0.workspace))
        }
        return self.sink(view: view)
            .replace(
                current: removeFromOutput(self.current),
                visible: self.visible.map(removeFromOutput),
                hidden: self.hidden.map(removeFromWorkspace)
        )
    }

    // MARK: Floating views

    func float(view: L.View, box: wlr_box) -> ViewSet<L, View> {
        self.replace(floating: self.floating.updateValue(box, forKey: view))
    }

    /// Clears the view's floating status.
    func sink(view: L.View) -> ViewSet<L, View> {
        self.replace(floating: self.floating.removeValue(forKey: view))
    }

    // MARK:

    /// Performs the given action on the workspace with the given tag.
    func onWorkspace(tag: String, _ f: (ViewSet<L, View>) -> ViewSet<L, View>) -> ViewSet<L, View> {
        f(self.view(tag: tag)).view(tag: self.current.workspace.tag)
    }

    func focus(view: L.View) -> ViewSet<L, View> {
        guard self.peek() != view else {
            return self
        }

        if let workspace = self.findWorkspace(view: view) {
            return self.view(tag: workspace.tag).modify { until({ $0.focus == view }, { $0.focusUp() }, $0) }
        } else {
            return self
        }
    }

    func focusMain() -> ViewSet<L, View> {
        self.modify {
            switch $0.up.reverse() {
            case .empty: return $0
            case .cons(let x, let xs): return Stack(up: .empty, focus: x, down: xs +++ $0.focus ++ $0.down)
            }
        }
    }

    /// Returns the focused element of the current stack (if there is one).
    func peek() -> L.View? {
        self.current.workspace.stack?.focus
    }

    /// Moves the current stack's focused element to the workspace with the given tag. Doesn't
    /// change the current workspace.
    func shift(tag: String) -> ViewSet<L, View> {
        guard let focus = self.peek() else {
            return self
        }

        if self.workspaces().contains(where: { $0.tag == tag}) {
            return self
                    .modify { $0.remove(focus) }
                    .onWorkspace(tag: tag, { $0.modifyOr(default: Stack.singleton(focus), { $0.insert(focus) }) })
        } else {
            return self
        }
    }

    /// Sets the focus to the workspace with the given tag. Returns self if the tag doesn't exist.
    public func view(tag: String) -> ViewSet<L, View> {
        if tag == self.current.workspace.tag {
            return self
        } else if let output = self.visible.first(where: { $0.workspace.tag == tag }) {
            return self.replace(
                current: output,
                visible: self.visible.filter { $0 !== output } + [self.current],
                hidden: self.hidden)
        } else if let workspace = self.hidden.first(where: { $0.tag == tag }) {
            return self.replace(
                current: self.current.copy(workspace: workspace),
                visible: self.visible,
                hidden: self.hidden.filter { $0 !== workspace } + [self.current.workspace])
        } else {
            // Not contained in the StackSet at all
            return self
        }
    }

    /// Returns an array of all workspaces contained in this view set.
    func workspaces() -> [Workspace<L>] {
        [self.current.workspace] + self.visible.map { $0.workspace } + self.hidden
    }

    func outputs() -> ViewSetOutputIterator<L> {
        ViewSetOutputIterator(self)
    }

    public struct ViewSetOutputIterator<L: Layout>: Sequence, IteratorProtocol where L.View: Hashable {
        private let viewSet: ViewSet<L, L.View>
        private var visible: IndexingIterator<Array<Output<L>>>? = nil

        internal init(_ viewSet: ViewSet<L, L.View>) {
            self.viewSet = viewSet
        }

        public mutating func next() -> Output<L>? {
            if self.visible != nil {
                return self.visible?.next()
            } else {
                self.visible = self.viewSet.visible.makeIterator()
                return self.viewSet.current
            }
        }

        public func makeIterator() -> ViewSetOutputIterator<L> {
            self
        }
    }
}

extension ViewSet: CustomStringConvertible {
    public var description: String {
        "ViewSet { current = \(self.current), visible = \(self.visible), hidden = \(self.hidden)"
    }
}


/// A convenience wrapper around Dictionaries to support copy-on-write semantics.
/// There exist better underlying structures for that (e.g. HAMTs), but for the number
/// of elements we (likely) manage, it probably doesn't make a lot of difference.
public class Map<K: Hashable, V>: ExpressibleByDictionaryLiteral {
    private var dict: [K: V]

    public required init(dictionaryLiteral elements: (K, V)...) {
        self.dict = Dictionary(uniqueKeysWithValues: elements)
    }

    init(from: Map<K, V>) {
        self.dict = from.dict
    }

    public func contains(key: K) -> Bool {
        dict[key] != nil
    }

    public func removeValue(forKey: K) -> Map<K, V> {
        let newMap = Map(from: self)
        newMap.dict.removeValue(forKey: forKey)
        return newMap
    }

    public func updateValue(_ value: V, forKey: K) -> Map<K, V> {
        let newMap = Map(from: self)
        newMap.dict.updateValue(value, forKey: forKey)
        return newMap
    }

    subscript(key: K) -> V? {
        get {
            self.dict[key]
        }
    }
}

/// Applies the given function until the given predicate holds and returns its value.
private func until<T>(_ pred: (T) -> Bool, _ f: (T) -> T, _ x: T) -> T {
    var value = x
    while !pred(value) {
        value = f(value)
    }
    return value
}
