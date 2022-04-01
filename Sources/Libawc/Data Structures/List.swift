// MARK: List

// Immutable single-linked list
public enum List<T> {
    indirect case cons(head: T, tail: List<T>)
    case empty
}


extension List: Sequence {
    public typealias Element = T

    public typealias Iterator = ListIterator<T>

    public func makeIterator() -> Iterator {
        ListIterator(self)
    }

    public struct ListIterator<T>: IteratorProtocol {

        public typealias Element = T

        private var list: List<T>

        init(_ list: List<T>) {
            self.list = list
        }

        public mutating func next() -> Element? {
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
    public var description: String {
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
    public static func ++(left: T, right: List<T>) -> List<T> {
        .cons(head: left, tail: right)
    }

    public var isEmpty: Bool {
        get {
            switch self {
            case .empty: return true
            default: return false
            }
        }
    }

    public static func +++(left: List<T>, right: List<T>) -> List<T> {
        switch left {
        case .empty: return right
        case let .cons(x, xs): return x ++ xs +++ right
        }
    }

    public func reverse() -> Self {
        func rev(_ l: Self, _ reversed: Self) -> Self {
            switch l {
            case .empty: return reversed
            case let .cons(x, xs): return rev(xs, x ++ reversed)
            }
        }
        return rev(self, .empty)
    }

    public func filter(_ pred: (T) -> Bool) -> Self {
        switch self {
        case .empty: return self
        case let .cons(x, xs) where pred(x): return .cons(head: x, tail: xs.filter(pred))
        case .cons(_, let xs): return xs.filter(pred)
        }
    }
}

extension List {
    public init<C: Collection>(collection: C) where C.Element == T {
        self = collection.reversed().reduce(List.empty, { result, next in
            next ++ result
        })
    }
}

extension List: Equatable where T: Equatable {
}

extension List where T: Equatable {
    func remove(_ element: T) -> Self {
        self.filter { $0 != element }
    }
}
