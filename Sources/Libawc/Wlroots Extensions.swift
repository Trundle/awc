///
/// Various extensions to make Wlroots a bit more pleasant to use in Swift.
///

import Wlroots


// MARK: Wlroots compatibility structures

public struct float_rgba {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public mutating func withPtr<Result>(_ body: (UnsafePointer<Float>) -> Result) -> Result {
        withUnsafePointer(to: &self) {
            $0.withMemoryRebound(to: Float.self, capacity: 4, body)
        }
    }
}

public typealias matrix9 = (Float, Float, Float, Float, Float, Float, Float, Float, Float)


// MARK: Wlroots convenience extensions

/// Swift version of `wl_container_of`
public func wlContainer<R>(of: UnsafeMutableRawPointer, _ path: PartialKeyPath<R>) -> UnsafeMutablePointer<R> {
    (of - MemoryLayout<R>.offset(of: path)!).bindMemory(to: R.self, capacity: 1)
}

fileprivate func toString<T>(array: T) -> String {
    withUnsafePointer(to: array) {
        $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
            String(cString: $0)
        }
    }
}

public extension wlr_box {
    func contains(x: Int, y: Int) -> Bool {
        self.x <= x && x < self.x + self.width && self.y <= y && y < self.y + self.height
    }

    func scale(_ factor: Double) -> wlr_box {
        let scaledX = Double(self.x) * factor
        let scaledY = Double(self.y) * factor
        return wlr_box(
           x: Int32(round(scaledX)),
           y: Int32(round(scaledY)),
           width: Int32(round(Double(self.x + self.width) * factor - scaledX)),
           height: Int32(round(Double(self.y + self.height) * factor - scaledY))
        )
    }
}

public extension UnsafeMutablePointer where Pointee == wlr_surface {
    func popup(of parent: UnsafeMutablePointer<wlr_surface>) -> Bool {
        if wlr_surface_is_xdg_surface(parent) {
            return wlr_xdg_surface_from_wlr_surface(parent)!.pointee.popups.contains(
                \wlr_xdg_popup.link,
                where: { $0.pointee.parent == self }
            )
        } else {
            return false
        }
    }

    func subsurface(of parent: UnsafeMutablePointer<wlr_surface>) -> Bool {
#if WLROOTS_0_14
        parent.pointee.subsurfaces_above.contains(
            \wlr_subsurface.parent_link, where: { $0.pointee.surface == self }
        ) || parent.pointee.subsurfaces_below.contains(
            \wlr_subsurface.parent_link, where: { $0.pointee.surface == self }
        )
#else
        parent.pointee.current.subsurfaces_above.contains(
            \wlr_subsurface.current.link, where: { $0.pointee.surface == self }
        ) || parent.pointee.current.subsurfaces_below.contains(
            \wlr_subsurface.current.link, where: { $0.pointee.surface == self }
        )
#endif
    }

    func surfaces() -> [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] {
        var surfaces: [(UnsafeMutablePointer<wlr_surface>, Int32, Int32)] = []
        withUnsafeMutablePointer(to: &surfaces) { (surfacesPtr) in
            wlr_surface_for_each_surface(
                self,
                {
                    $3!.bindMemory(to: [(UnsafeMutablePointer < wlr_surface>, Int32, Int32)].self, capacity: 1)
                        .pointee
                        .append(($0!, $1, $2))
                },
                surfacesPtr
            )
        }
        return surfaces
    }
}


public struct WlListIterator<T>: IteratorProtocol {
    private let start: UnsafePointer<wl_list>
    private var current: UnsafeMutablePointer<T>
    private let path: WritableKeyPath<T, wl_list>
    private var exhausted: Bool = false

    fileprivate init(_ start: UnsafePointer<wl_list>, _ path: WritableKeyPath<T, wl_list>) {
        self.start = start
        self.current = wlContainer(of: UnsafeMutableRawPointer(start.pointee.next), path)
        self.path = path
    }

    public mutating func next() -> UnsafeMutablePointer<T>? {
        guard !exhausted else { return nil }

        if withUnsafePointer(to: &current.pointee[keyPath: path], { $0 != start }) {
            defer {
                current = wlContainer(
                    of: UnsafeMutableRawPointer(current.pointee[keyPath: path].next),
                    path
                )
            }
            return current
        } else {
            exhausted = true
            return nil
        }
    }
}

public struct WlListSequence<T>: Sequence {
    private let list: UnsafeMutablePointer<wl_list>
    private let path: WritableKeyPath<T, wl_list>

    fileprivate init(_ list: UnsafeMutablePointer<wl_list>, _ path: WritableKeyPath<T, wl_list>) {
        self.list = list
        self.path = path
    }

    public func makeIterator() -> WlListIterator<T> {
        return WlListIterator(list, path)
    }
}

public extension wl_list {
    /// Returns whether the given predicate holds for some element. Doesn't mutate the list, even though the method
    /// is marked as mutating.
    mutating func contains<T>(_ path: WritableKeyPath<T, wl_list>, where: (UnsafeMutablePointer<T>) -> Bool) -> Bool {
        var pos = wlContainer(of: UnsafeMutableRawPointer(self.next), path)
        while withUnsafePointer(to: &pos.pointee[keyPath: path], { $0 != &self }) {
            if `where`(pos) {
                return true
            }
            pos = wlContainer(of: UnsafeMutableRawPointer(pos.pointee[keyPath: path].next), path)
        }
        return false
    }

    mutating func sequence<T>(_ path: WritableKeyPath<T, wl_list>) -> WlListSequence<T> {
        return WlListSequence(&self, path)
    }
}


public extension UnsafeMutablePointer where Pointee == wlr_subsurface {
    func parentToplevel() -> UnsafeMutablePointer<wlr_xdg_surface>? {
        guard wlr_surface_is_xdg_surface(self.pointee.parent) else { return nil }

        var xdgSurface = wlr_xdg_surface_from_wlr_surface(self.pointee.parent)
        while xdgSurface != nil && xdgSurface?.pointee.role == WLR_XDG_SURFACE_ROLE_POPUP {
            xdgSurface = wlr_xdg_surface_from_wlr_surface(xdgSurface?.pointee.popup.pointee.parent)
        }
        return xdgSurface
    }
}


public extension UnsafeMutablePointer where Pointee == wlr_surface {
    func isXdgPopup() -> Bool {
        if wlr_surface_is_xdg_surface(self) {
            let xdgSurface = wlr_xdg_surface_from_wlr_surface(self)!
            return xdgSurface.pointee.role == WLR_XDG_SURFACE_ROLE_POPUP
        }
        return false
    }
}


public extension UnsafeMutablePointer where Pointee == wlr_output {
    var name: String {
        get {
#if WLROOTS_0_14
            return toString(array: self.pointee.name)
#else
            return String(cString: self.pointee.name)
#endif
        }
    }
}
