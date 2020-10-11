import Wlroots

class Output<View> {
    let output: UnsafeMutablePointer<wlr_output>
    var workspace: Workspace<View>
    // The current surface arrangement
    var arrangement: [(View, wlr_box)] = []

    init(wlrOutput: UnsafeMutablePointer<wlr_output>, workspace: Workspace<View>) {
        self.output = wlrOutput
        self.workspace = workspace
    }
}

class Workspace<View> {
    let tag: String
    let layout: Layout
    var stack: Stack<View>? = nil

    init(tag: String, layout: Layout) {
        self.tag = tag
        self.layout = layout
    }
}

class ViewSet<View: Hashable> {
    // The output with the currently focused workspace
    var current: Output<View>
    // Non-focused workspaces visible on outputs
    var visible: [Output<View>] = []
    // The workspaces that are not visible anywhere
    var hidden: [Workspace<View>] = []
    // The views that exist, should be managed, but are not mapped yet
    var unmapped: Set<View> = Set()

    init(current: Output<View>) {
        self.current = current
    }

    func remove(view: View) {
        // XXX make it immutable, i.e. return a new viewset?
        let removeFromWorkspace: (Workspace<View>) -> () = {
            $0.stack = $0.stack?.remove(view)
        }
        let removeFromOutput: (Output) -> () = {
            removeFromWorkspace($0.workspace)
        }
        removeFromOutput(self.current)
        self.visible.forEach(removeFromOutput)
        self.hidden.forEach(removeFromWorkspace)
    }

    func outputs() -> ViewSetIterator<View> {
        return ViewSetIterator(self)
    }
}

struct ViewSetIterator<View: Hashable>: Sequence, IteratorProtocol {
    private let viewSet: ViewSet<View>
    private var visible: IndexingIterator<Array<Output<View>>>? = nil

    internal init(_ viewSet: ViewSet<View>) {
        self.viewSet = viewSet
    }

    mutating func next() -> Output<View>? {
        if var delegate = self.visible {
            return delegate.next()
        } else {
            self.visible = self.viewSet.visible.makeIterator()
            return self.viewSet.current
        }
    }

    func makeIterator() -> ViewSetIterator<View> {
        return self
    }
}
