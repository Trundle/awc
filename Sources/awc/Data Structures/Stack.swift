// MARK: Window Stack

// A cursor onto a window list. The primary window is by convention the top-most item.
struct Stack<T> {
    // Implementation detail: implements a so-called zipper. Note that up is
    // in reverse order.
    let up: List<T>
    let focus: T
    let down: List<T>
}


// MARK: Stack operations
extension Stack {
    /// Moves the focus to the next window in the stack. Wraps around if
    /// the focus is already on the down-most window.
    func focusDown() -> Self {
        return self.reverse().focusUp().reverse()
    }

    /// Moves the focus to the window one up. Wraps around if the focus is
    /// already on top-most window.
    func focusUp() -> Self {
        switch self.up {
        case let .cons(u, us): return Stack(up: us, focus: u, down: self.focus ++ self.down)
        case .empty:
            guard case .cons(let x, let xs) = (self.focus ++ self.down).reverse() else {
                fatalError("impossible to reach")
            }
            return Stack(up: xs, focus: x, down: .empty)
        }
    }

    /// Swaps the focussed window with the primary window.
    // XXX maybe only needs to exist in StackSet
    func swapPrimary() -> Self {
        guard !self.up.isEmpty() else {
            // Nothing to do, focussed window is already the primary window
            return self
        }

        guard case .cons(let u, let us) = self.up.reverse() else {
            fatalError("impossible to reach")
        }
        return Stack(up: .empty, focus: self.focus, down: us +++ (u ++ self.down))
    }

    /// Reverses the stack: up becomes down and down becomes up.
    func reverse() -> Self {
        return Stack(up: self.down, focus: self.focus, down: self.up)
    }

    func toList() -> List<T> {
        return self.up.reverse() +++ (self.focus ++ self.down)
    }

    func toArray() -> [T] {
        return Array(self.up.reverse()) + [self.focus] + Array(self.down)
    }

    func insert(_ element: T) -> Self {
        Stack(up: up, focus: element, down: focus ++ down)
    }
}

extension Stack where T: Equatable {
    func remove(_ element: T) -> Self? {
        if element == focus {
            if case .cons(let head, let tail) = up {
                return Stack(up: tail, focus: head, down: down)
            } else if case .cons(let head, let tail) = down {
                return Stack(up: up, focus: head, down: tail)
            } else {
                return nil
            }
        } else if up.contains(element) {
            // TODO: double work. We fist check with contains, then we remove.
            return Stack(up: up.remove(element), focus: focus, down: down)
        } else if down.contains(element) {
            // TODO: double work. We fist check with contains, then we remove.
            return Stack(up: up, focus: focus, down: down.remove(element))
        } else {
            assertionFailure()
            return self
        }
    }
}
