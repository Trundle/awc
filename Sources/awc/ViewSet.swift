import Libawc
import Wlroots

public class Output<View> {
    public let output: UnsafeMutablePointer<wlr_output>
    public let workspace: Workspace<View>
    // The current surface arrangement
    public var arrangement: [(View, wlr_box)] = []

    init(wlrOutput: UnsafeMutablePointer<wlr_output>, workspace: Workspace<View>) {
        self.output = wlrOutput
        self.workspace = workspace
    }

    public func replace(workspace: Workspace<View>) -> Output<View> {
        Output(wlrOutput: self.output, workspace: workspace)
    }
}

extension Output: CustomStringConvertible {
    public var description: String {
        "Output { output = \(self.output), workspace = \(self.workspace) }"
    }
}


public class Workspace<View> {
    public let tag: String
    public let layout: Layout
    public let stack: Stack<View>?

    init(tag: String, layout: Layout, stack: Stack<View>? = nil) {
        self.tag = tag
        self.layout = layout
        self.stack = stack
    }

    public func replace(layout: Layout) -> Workspace<View> {
        Workspace(tag: self.tag, layout: layout, stack: self.stack)
    }

    public func replace(stack: Stack<View>?) -> Workspace<View> {
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


public class ViewSet<View: Hashable> {
    // The output with the currently focused workspace
    public let current: Output<View>
    // Non-focused workspaces visible on outputs
    public let visible: [Output<View>]
    // The workspaces that are not visible anywhere
    public let hidden: [Workspace<View>]
    // Mapping of untiled views to their boxes (location + size)
    public let floating: Map<View, wlr_box>

    convenience init(current: Output<View>, hidden: [Workspace<View>] = []) {
        self.init(current: current, visible: [], hidden: hidden, floating: [:])
    }

    private init(current: Output<View>, visible: [Output<View>], hidden: [Workspace<View>],
                 floating: Map<View, wlr_box>) {
        self.current = current
        self.visible = visible
        self.hidden = hidden
        self.floating = floating
    }

    // MARK: Convenience methods for updating state

    func replace(current: Output<View>) -> ViewSet<View> {
        ViewSet(current: current, visible: self.visible, hidden: self.hidden, floating: self.floating)
    }

    func replace(floating: Map<View, wlr_box>) -> ViewSet<View> {
        ViewSet(current: self.current, visible: self.visible, hidden: self.hidden, floating: floating)
    }

    func replace(current: Output<View>, visible: [Output<View>], hidden: [Workspace<View>]) -> ViewSet<View> {
        ViewSet(current: current, visible: visible, hidden: hidden, floating: self.floating)
    }

    func modify(_ f: (Stack<View>) -> Stack<View>?) -> ViewSet<View> {
        if let stack = self.current.workspace.stack {
            return self.replace(
                current: self.current.replace(workspace: self.current.workspace.replace(stack: f(stack))))
        }
        return self
    }

    func modifyOr(default: @autoclosure () -> Stack<View>?, _ f: (Stack<View>) -> Stack<View>?) -> ViewSet<View> {
        let withNewStack = { newStack in
            self.replace(current: self.current.replace(workspace: self.current.workspace.replace(stack: newStack)))
        }
        if let stack = self.current.workspace.stack {
            return withNewStack(f(stack))
        } else {
            return withNewStack(`default`())
        }
    }

    /// Finds the output that displays the given view.
    func findOutput(view: View) -> Output<View>? {
        for output in self.outputs() {
            if let stack = output.workspace.stack {
                if stack.contains(view) {
                    return output
                }
            }
        }
        return nil
    }

    /// Removes the given view, if it exists.
    func remove(view: View) -> ViewSet<View> {
        let removeFromWorkspace: (Workspace<View>) -> Workspace<View> = {
            $0.replace(stack: $0.stack?.remove(view))
        }
        let removeFromOutput: (Output<View>) -> Output<View> = {
            $0.replace(workspace: removeFromWorkspace($0.workspace))
        }
        return self.sink(view: view)
            .replace(
                current: removeFromOutput(self.current),
                visible: self.visible.map(removeFromOutput),
                hidden: self.hidden.map(removeFromWorkspace)
        )
    }

    // MARK: Floating views

    func float(view: View, box: wlr_box) -> ViewSet<View> {
        self.replace(floating: self.floating.updateValue(box, forKey: view))
    }

    /// Clears the view's floating status.
    func sink(view: View) -> ViewSet<View> {
        self.replace(floating: self.floating.removeValue(forKey: view))
    }

    // MARK:

    /// Performs the given action on the workspace with the given tag.
    func onWorkspace(tag: String, _ f: (ViewSet<View>) -> ViewSet<View>) -> ViewSet<View> {
        f(self.view(tag: tag)).view(tag: self.current.workspace.tag)
    }

    /// Returns the focused element of the current stack (if there is one).
    func peek() -> View? {
        self.current.workspace.stack?.focus
    }

    /// Moves the current stack's focused element to the workspace with the given tag. Doesn't
    /// change the current workspace.
    func shift(tag: String) -> ViewSet<View> {
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
    public func view(tag: String) -> ViewSet<View> {
        if tag == self.current.workspace.tag {
            return self
        } else if let output = self.visible.first(where: { $0.workspace.tag == tag }) {
            return self.replace(
                current: output,
                visible: self.visible.filter { $0 !== output } + [self.current],
                hidden: self.hidden)
        } else if let workspace = self.hidden.first(where: { $0.tag == tag }) {
            return self.replace(
                current: self.current.replace(workspace: workspace),
                visible: self.visible,
                hidden: self.hidden.filter { $0 !== workspace } + [self.current.workspace])
        } else {
            // Not contained in the StackSet at all
            return self
        }
    }

    /// Returns an array of all workspaces contained in this view set.
    func workspaces() -> [Workspace<View>] {
        [self.current.workspace] + self.visible.map { $0.workspace } + self.hidden
    }

    func outputs() -> ViewSetOutputIterator<View> {
        ViewSetOutputIterator(self)
    }

    public struct ViewSetOutputIterator<View: Hashable>: Sequence, IteratorProtocol {
        private let viewSet: ViewSet<View>
        private var visible: IndexingIterator<Array<Output<View>>>? = nil

        internal init(_ viewSet: ViewSet<View>) {
            self.viewSet = viewSet
        }

        public mutating func next() -> Output<View>? {
            if self.visible != nil {
                return self.visible?.next()
            } else {
                self.visible = self.viewSet.visible.makeIterator()
                return self.viewSet.current
            }
        }

        public func makeIterator() -> ViewSetOutputIterator<View> {
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
