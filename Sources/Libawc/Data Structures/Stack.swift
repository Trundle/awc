// MARK: Window Stack

// A cursor onto a window list. The primary window is by convention the top-most item.
public struct Stack<T> {
    // Implementation detail: implements a so-called zipper. Note that up is
    // in reverse order.
    public let up: List<T>
    public let focus: T
    public let down: List<T>
}

extension Stack {
    public static func singleton(_ focus: T) -> Self {
        Stack(up: .empty, focus: focus, down: .empty)
    }
}


// MARK: Stack operations
extension Stack {
    /// Moves the focus to the next element in the stack. Wraps around if
    /// the focus is already on the down-most element.
    public func focusDown() -> Self {
        self.reverse().focusUp().reverse()
    }

    /// Moves the focus to the element one up. Wraps around if the focus is
    /// already on top-most element.
    public func focusUp() -> Self {
        switch self.up {
        case let .cons(u, us): return Stack(up: us, focus: u, down: self.focus ++ self.down)
        case .empty:
            guard case .cons(let x, let xs) = (self.focus ++ self.down).reverse() else {
                fatalError("impossible to reach")
            }
            return Stack(up: xs, focus: x, down: .empty)
        }
    }

    /// Swaps the focussed element with the primary element.
    public func swapPrimary() -> Self {
        guard !self.up.isEmpty() else {
            // Nothing to do, focussed element is already the primary element
            return self
        }

        guard case .cons(let u, let us) = self.up.reverse() else {
            fatalError("impossible to reach")
        }
        return Stack(up: .empty, focus: self.focus, down: us +++ (u ++ self.down))
    }

    /// Swaps the focused element with the element one up. Focus stays the same. Wraps around.
    public func swapUp() -> Self {
        switch self.up {
        case let .cons(u, us): return Stack(up: us, focus: self.focus, down: u ++ self.down)
        case .empty: return Stack(up: self.down.reverse(), focus: self.focus, down: .empty)
        }
    }

    /// Swaps the focused element with the element one down. Focus stays the same. Wraps around.
    public func swapDown() -> Self {
        self.reverse().swapUp().reverse()
    }

    /// Reverses the stack: up becomes down and down becomes up.
    public func reverse() -> Self {
        Stack(up: self.down, focus: self.focus, down: self.up)
    }

    public func toList() -> List<T> {
        self.up.reverse() +++ (self.focus ++ self.down)
    }

    public func toArray() -> [T] {
        Array(self.up.reverse()) + [self.focus] + Array(self.down)
    }

    public func insert(_ element: T) -> Self {
        Stack(up: up, focus: element, down: focus ++ down)
    }

    public func filter(_ pred: (T) -> Bool) -> Self? {
        if case let .cons(f, ds) = (self.focus ++ self.down).filter(pred) {
            return Stack(up: self.up.filter(pred), focus: f, down: ds)
        } else if case let .cons(f, us) = self.up.filter(pred) {
            return Stack(up: us, focus: f, down: .empty)
        } else {
            return nil
        }
    }
}

extension Stack where T: Equatable {
    public func remove(_ element: T) -> Self? {
        self.filter { $0 != element }
    }
}
