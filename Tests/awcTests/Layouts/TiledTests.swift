import SwiftCheck
import XCTest

import DataStructures
import Libawc
import Wlroots
import testHelpers

extension wlr_box: Arbitrary {
    public static var arbitrary : Gen<wlr_box> {
        let positive = Int32.arbitrary.suchThat { $0 > 0 }
        let positionAndLength = Gen<(Int32, Int32)>.zip(positive, positive).suchThat {
            $0.0 &+ $0.1 > $0.0
        }
        return Gen<wlr_box>.compose { c in
            let (x, width) = c.generate(using: positionAndLength)
            let (y, height) = c.generate(using: positionAndLength)
            return wlr_box(x: x, y: y, width: width, height: height)
        }
    }
}

public final class TiledTests: XCTestCase {
    private let layout = Tiled<TestView, ()>(split: 0.5, delta: 0.05)

    func testSingleView() {
        property("stack with single view always takes full space") <- forAll { (box: wlr_box) in
            let stack = Stack.singleton(TestView())
            let workspace = Workspace(tag: "test", layout: self.layout, stack: stack)

            let arrangement = self.layout.doLayout(
                dataProvider: NoDataProvider(),
                output: Output(data: (), workspace: workspace),
                stack: stack,
                box: box
            )

            return arrangement.count == 1 && arrangement[0].2 == box
        }
    }    

    func testMultipleViews() {
        property("boxes don't overlap") <- forAll { (box: wlr_box, n: UInt) in
            let up = List(sequence: (0..<n).map { TestView(id: Int($0)) })
            let stack = Stack(up: up, focus: TestView(id: Int(n + 1)), down: List.empty)
            let workspace = Workspace(tag: "test", layout: self.layout, stack: stack)

            let arrangement = self.layout.doLayout(
                dataProvider: NoDataProvider(),
                output: Output(data: (), workspace: workspace),
                stack: stack,
                box: box
            )

            return arrangement.count == n + 1 && noOverlaps(boxes: arrangement.map { $0.2 })
        }
    }
}

fileprivate func noOverlaps(boxes: [wlr_box]) -> Bool {
    let vertices = boxes.map { 
        (left: $0.x, right: $0.y + $0.width, top: $0.y, bottom: $0.y + $0.height)
    }
    return vertices.allSatisfy { first in
        vertices.allSatisfy { other in
            first == other || (
                first.top < other.bottom || other.top < first.bottom
                || first.right < other.left || other.right < first.left
            )
        }
    }
}
