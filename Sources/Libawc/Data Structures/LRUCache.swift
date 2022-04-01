// MARK: LinkedList implementation

// A classic doubly linked list with a sentinel node
private final class LinkedList<T> {
    class Node {
        var next: Node!
        var prev: Node!
        var value: T?

        // Creates a sentinel node
        init() {
            next = self
            prev = self
        }

        init(prev: Node, next: Node, value: T) {
            self.prev = prev
            self.next = next
            self.value = value
        }
    }

    private var sentinel: Node = Node()

    var isEmpty: Bool {
        get {
            sentinel.next === sentinel
        }
    }

    init() {
    }

    func add(_ value: T) -> Node {
        let node = Node(prev: sentinel, next: sentinel.next, value: value)
        sentinel.next.prev = node
        sentinel.next = node
        return node
    }

    func dropLast() -> T {
        assert(!isEmpty)
        let node = sentinel.prev!
        node.prev.next = node.next
        node.next.prev = node.prev
        node.prev = .none
        node.next = .none
        return node.value!
    }

    func moveToHead(node: Node) {
        node.next.prev = node.prev
        node.prev.next = node.next
        node.prev = sentinel
        node.next = sentinel.next
        sentinel.next.prev = node
        sentinel.next = node
    }
}


/// A simple LRU cache. Allows caching values by a certain key. Requires the key to be hashable.
public final class LRUCache<Key, Value> where Key: Hashable {
    private var lastAccessOrder: LinkedList<(Key, Value)> = LinkedList()
    private var elements: [Key: LinkedList<(Key, Value)>.Node] = [:]
    private var maxSize: Int

    public init(maxSize: Int) {
        self.maxSize = maxSize
    }

    public func add(key: Key, value: Value) {
        if let node = elements[key] {
            lastAccessOrder.moveToHead(node: node)
            node.value = (key, value)
        } else {
            let node = lastAccessOrder.add((key, value))
            elements[key] = node
            node.value = (key, value)
        }

        if elements.count > maxSize {
            let (lastKey, _) = lastAccessOrder.dropLast()
            elements.removeValue(forKey: lastKey)
        }
    }

    public func get(forKey: Key) -> Value? {
        guard let node = elements[forKey] else {
            return .none
        }
        lastAccessOrder.moveToHead(node: node)
        return node.value!.1
    }

    public subscript(key: Key) -> Value {
        get {
            return self.get(forKey: key)!
        }
        set(newValue) {
            self.add(key: key, value: newValue)
        }
  }
}
