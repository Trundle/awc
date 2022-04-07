import SwiftCheck
import XCTest

import Libawc


fileprivate extension Stack where T == Int {
    static func ==(lhs: Stack<Int>, rhs: Stack<Int>) -> Bool {
        return lhs.up == rhs.up && lhs.focus == rhs.focus && lhs.down == rhs.down
    }
}

extension List: Arbitrary where T == Int {
    public static var arbitrary: Gen<List<Int>> {
        Gen<List<Int>>.compose { 
            let array: [Int] = $0.generate()
            return List(sequence: array)
        }
    }
}


extension Stack: Arbitrary where T == Int {
    public static var arbitrary: Gen<Stack<Int>> {
        return Gen<Stack<Int>>.compose {
            Stack(up: $0.generate(), focus: $0.generate(), down: $0.generate())
        }
    }

    var count: Int {
        get {
            self.reduce(0, { (count, _) in count + 1 })
        }
    }
}


class StackTests: XCTestCase {
    func testToArrayReturnsRightOrder() {
        let stack = Stack(up: List(sequence: [3, 2, 1]), focus: 4, down: List(sequence: [5, 6, 7]))

        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7], stack.toArray())
    }

    func testInsert() {
        XCTAssertEqual([1, 0], Stack.singleton(0).insert(1).toArray())

        XCTAssertEqual(
            [1, 2, 3, 4],
            Stack(up: List(sequence: [2, 1]), focus: 4, down: List.empty).insert(3).toArray())

        XCTAssertEqual(
            [1, 2, 3, 4, 5],
            Stack(
                up: List(sequence: [2, 1]),
                focus: 4,
                down: List(sequence: [5])
            ).insert(3).toArray())
    }

    func testReverse() {
        property("reverse() reverses stack") <- forAll { (stack: Stack<Int>) in
            stack.reverse().toArray() == stack.toArray().reversed()
        }

        property("reversing reversed stack results in original stack again") <- forAll {
            (stack: Stack<Int>) in
            stack.reverse().reverse() == stack
        }
    }

    func testMakeIterator() {
        property("iterator returns elements in correct order") <- forAll { (stack: Stack<Int>) in
            // reversed() is a Sequence method (which uses the iterator), reverse() comes
            // from our Stack
            stack.reversed() == stack.reverse().toArray()
        }
    }

    func testContains() {
        property("contains() returns true for all elements in stack") <- forAll {
            (stack: Stack<Int>) in
            stack.reduce(true, { (result, element) in result && stack.contains(element) })
        }
    }

    func testFocus() {
        property("focusing first element results in empty up stack and has the same elements")
        <- forAll { (stack: Stack<Int>) in
            let newStack = stack.focus(nth: 0)
            return newStack.up.isEmpty && newStack.toArray() == stack.toArray()
        }

        property("focusing last element results in empty down stack and has the same elements")
        <- forAll { (stack: Stack<Int>) in
            let newStack = stack.focus(nth: stack.count - 1)
            return newStack.down.isEmpty && newStack.toArray() == stack.toArray()
        }

        property("focusing past number of elements returns unchanged stack") <- forAll {
            (stack: Stack<Int>, toAdd: UInt8) in
            stack.focus(nth: stack.count + Int(toAdd)) == stack
        }

        property("focusing element < 0 returns unchanged stack") <- forAll {
            (stack: Stack<Int>, n: UInt8) in
            stack.focus(nth: -Int(1 &+ n)) == stack
        }
    }

    func testFocusDown() {
        property("focusDown() wraps around") <- forAll { (stack: Stack<Int>) in
            var newStack = stack
            for _ in 0..<stack.count {
                newStack = newStack.focusDown()
            }

            return newStack == stack
        }
    }

    func testFocusUp() {
        property("focusUp() wraps around") <- forAll { (stack: Stack<Int>) in
            var newStack = stack
            for _ in 0..<stack.count {
                newStack = newStack.focusUp()
            }

            return newStack == stack
        }
    }

    func testFilter() {
        property("filter() with predicate that is always false returns nil") <- forAll {
            (stack: Stack<Int>) in
            stack.filter { (_) in false } == nil
        }

        property("filter() wtih predicate that is always true returns original stack") <- forAll {
            (stack: Stack<Int>) in
            stack.filter { (_) in true }! == stack
        }
    }
}
