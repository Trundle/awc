// MARK: List

// Immutable single-linked list
enum List<T> {
    indirect case cons(head: T, tail: List<T>)
    case empty
}


extension List: Sequence {
    typealias Element = T

    typealias Iterator = ListIterator<T>

    public func makeIterator() -> Iterator {
        ListIterator(self)
    }

    struct ListIterator<T>: IteratorProtocol {

        typealias Element = T

        private var list: List<T>

        init(_ list: List<T>) {
            self.list = list
        }

        mutating func next() -> Element? {
            switch list {
            case .empty:
                return nil
            case .cons(let head, let tail):
                self.list = tail
                return Optional.some(head)
            }
        }
    }
}


extension List: CustomStringConvertible {
    var description: String {
        switch self {
        case .empty: return "[]"
        case let .cons(x, xs): return "\(x) ++ \(xs)"
        }
    }
}

// Used to add another element to the front of a list.
infix operator ++: AssignmentPrecedence
// Used to append a list to another
infix operator +++: AssignmentPrecedence

extension List {
    static func ++(left: T, right: List<T>) -> List<T> {
        return .cons(head: left, tail: right)
    }

    static func +++(left: List<T>, right: List<T>) -> List<T> {
        switch left {
        case .empty: return right
        case let .cons(x, xs): return x ++ xs +++ right
        }
    }

    func isEmpty() -> Bool {
        switch self {
        case .empty: return true
        default: return false
        }
    }

    func reverse() -> Self {
        func rev(_ l: Self, _ reversed: Self) -> Self {
            switch l {
            case .empty: return reversed
            case let .cons(x, xs): return rev(xs, x ++ reversed)
            }
        }
        return rev(self, .empty)
    }
}

extension List {
    init<C: Collection>(collection: C) where C.Element == T {
        self = collection.reversed().reduce(List.empty, { result, next in
            next ++ result
        })
    }
}


extension List where T: Equatable {
    func remove(_ element: T) -> Self {
        switch self {
        case .empty:
            return self
        case .cons(let head, let tail):
            if head == element {
                return tail
            } else {
                return List.cons(head: head, tail: tail.remove(element))
            }
        }
    }
}
