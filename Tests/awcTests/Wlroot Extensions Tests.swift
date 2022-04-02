import SwiftCheck
import XCTest

import Libawc
import Wlroots


class FloatRgbaTests: XCTestCase {
    func testPacking() {
        property("float_rgba's internal structure are 4 consecutive floats") <- forAll {
            (r: Float, g: Float, b: Float, a: Float) in
            var value = float_rgba(r: r, g: g, b: b, a: a)
            let collected = value.withPtr {
                ($0[0], $0[1], $0[2], $0[3])
            }

            return collected == (r, g, b, a)
        }
    }
}

class WlrBoxTests: XCTestCase {
    func testContains() {
        property("contains() returns true for values in box") <- forAll(Gen<Int>.choose((1, 10))) {
            (x: Int) in
            forAll(Gen<Int>.choose((1, 10))) { (y: Int) in
                let box = wlr_box(x: 1, y: 1, width: 10, height: 10)
                return box.contains(x: x, y: y)
            }
        }

        property("empty box doesn't contain anything") <- forAll { (x: Int, y: Int) in
            let box = wlr_box(x: 0, y: 0, width: 0, height: 0)
            return !box.contains(x: x, y: y)
        }
    }
}
