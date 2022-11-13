/// Phantom type to add some type safety to `OpaquePointer`
public struct TypedOpaque<T> {
    private let ptr: OpaquePointer

    public init(_ ptr: OpaquePointer) {
        self.ptr = ptr
    }

    public init(_ ptr: UnsafeMutableRawPointer) {
        self.init(OpaquePointer(ptr))
    }

    public init?(_ ptr: OpaquePointer?) {
        guard let unpacked = ptr else {
            return nil
        }
        self.init(unpacked)
    }

    public func get(as: T.Type) -> OpaquePointer {
        ptr
    }
}
