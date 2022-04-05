import awc_config
import Wlroots

public enum ConfigError: Error {
    case invalidLayout
}

private class CappedMapper<View, OutputData>: AnyLayoutMapper {
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func flatMap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData> {
        AnyLayout.wrap(Capped(layout: layout, limit: self.limit))
    }
}

private class MagnifiedMapper<View, OutputData>: AnyLayoutMapper {
    private let magnification: Double

    init(magnification: Double) {
        self.magnification = magnification
    }

    func flatMap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData> {
        AnyLayout.wrap(Magnified(layout: layout, magnification: self.magnification))
    }
}

private class ReflectedMapper<View, OutputData>: AnyLayoutMapper {
    private let direction: AwcDirection

    init(direction: AwcDirection) {
        self.direction = direction
    }

    func flatMap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData> {
        AnyLayout.wrap(Reflected(layout: layout, direction: self.direction))
    }
}

private class RotatedMapper<View, OutputData>: AnyLayoutMapper {
    func flatMap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData> {
        AnyLayout.wrap(Rotated(layout: layout))
    }
}

private class ChooseLayoutMapper<View, OutputData>: AnyLayoutMapper {
    private let right: AnyLayout<View, OutputData>

    init(right: AnyLayout<View, OutputData>) {
        self.right = right
    }

    func flatMap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData>
    where L.View == View, L.OutputData == OutputData
    {
        right.flatMap(ChooseLayoutInnerMapper(layout))
    }
}

private class ChooseLayoutInnerMapper<Left: Layout>: AnyLayoutMapper {
    typealias View = Left.View
    typealias OutputData = Left.OutputData

    private let left: Left

    init(_ left: Left) {
        self.left = left
    }

    func flatMap<L: Layout>(_ layout: L) -> AnyLayout<L.View, L.OutputData>
    where L.View == View, L.OutputData == OutputData
    {
        AnyLayout.wrap(Choose(self.left, layout))
    }
}

public func buildLayout<View: Equatable, OutputData>(
    _ op: UnsafePointer<AwcLayoutOp>,
    _ numberOfOps: Int
) throws -> AnyLayout<View, OutputData>
{
    var opsLeft = numberOfOps
    var currentOp = op
    var layouts: [AnyLayout<View, OutputData>] = []
    while opsLeft > 0 {
        switch (currentOp.pointee.tag) {
        case AwcLayoutOp_Choose:
            guard let right = layouts.popLast(), let left = layouts.popLast() else {
                throw ConfigError.invalidLayout
            }
            layouts.append(left.flatMap(ChooseLayoutMapper(right: right)))
        case AwcLayoutOp_Full:
            layouts.append(AnyLayout.wrap(Full()))
        case AwcLayoutOp_Capped:
            guard let layout = layouts.popLast() else {
                throw ConfigError.invalidLayout
            }
            layouts.append(layout.flatMap(CappedMapper(limit: currentOp.pointee.capped)))
        case AwcLayoutOp_Magnify:
            guard let layout = layouts.popLast() else {
                throw ConfigError.invalidLayout
            }
            layouts.append(layout.flatMap(MagnifiedMapper(magnification: currentOp.pointee.magnify)))
        case AwcLayoutOp_Reflected:
            guard let layout = layouts.popLast() else {
                throw ConfigError.invalidLayout
            }
            layouts.append(layout.flatMap(ReflectedMapper(direction: currentOp.pointee.reflected)))
        case AwcLayoutOp_Rotated:
            guard let layout = layouts.popLast() else {
                throw ConfigError.invalidLayout
            }
            layouts.append(layout.flatMap(RotatedMapper()))
        case AwcLayoutOp_Tiled:
            let tiled = currentOp.pointee.tiled
            layouts.append(AnyLayout.wrap(Tiled(split: tiled.split, delta: tiled.delta)))
        default:
            throw ConfigError.invalidLayout
        }

        opsLeft -= 1
        currentOp += 1
    }

    if layouts.count != 1 {
        throw ConfigError.invalidLayout
    }
    return layouts.first!
}
