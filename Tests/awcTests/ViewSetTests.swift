import Libawc
import testHelpers

import XCTest
import SwiftCheck


// MARK: Equatable implementations for assertions

extension Stack: Equatable where T: Equatable {
    public static func ==(lhs: Stack<T>, rhs: Stack<T>) -> Bool {
        lhs.toList() == rhs.toList()
    }
}

extension Workspace: Equatable where L == TestLayout {
    public static func ==(lhs: Workspace<TestLayout>, rhs: Workspace<TestLayout>) -> Bool {
        lhs.tag == rhs.tag && lhs.stack == rhs.stack
    }
}

extension Output: Equatable where L == TestLayout {
    public static func ==(lhs: Output<TestLayout>, rhs: Output<TestLayout>) -> Bool {
        lhs.workspace == rhs.workspace
    }
}

extension ViewSet: Equatable where L == TestLayout {
    public static func ==(lhs: ViewSet<TestLayout, TestView>, rhs: ViewSet<TestLayout, TestView>) -> Bool {
        lhs.current == rhs.current
            && lhs.visible.sorted(by: { $0.workspace.tag > $1.workspace.tag })
                == rhs.visible.sorted(by: { $0.workspace.tag > $1.workspace.tag })
            && lhs.hidden.sorted(by: { $0.tag > $1.tag }) == rhs.hidden.sorted(by: { $0.tag > $1.tag })
            && equalFloating(lhs, rhs)
    }

    private static func equalFloating(
        _ lhs: ViewSet<TestLayout, TestView>,
        _ rhs: ViewSet<TestLayout, TestView>
    ) -> Bool {
        for workspace in lhs.workspaces() {
            if let stack = workspace.stack {
                for view in stack.toList() {
                    if lhs.floating[view] != rhs.floating[view] {
                        return false
                    }
                }
            }
        }
        return true
    }
}


// MARK: Arbitrary implementations

extension ViewSet: Arbitrary where L == TestLayout {
    public static var arbitrary : Gen<ViewSet<L, View>> {
        Gen<ViewSet<TestLayout, TestView>>.compose { c in
            let layout = TestLayout()

            let numberOfWorkspaces = c.generate(using: Gen<Int>.fromElements(in: 1...20))
            let numberOfOutputs = c.generate(using: Gen<Int>.fromElements(in: 1...numberOfWorkspaces))

            var views: [[TestView]] = []
            var seen: Set<Int> = []
            for _ in 0..<numberOfWorkspaces {
                let perWorkspaceIds: [Int] = c.generate()
                views.append(perWorkspaceIds.filter { !seen.contains($0) }.map { TestView(id: $0) })
                seen.formUnion(perWorkspaceIds)
            }

            var workspaces: [Workspace<TestLayout>] = views.enumerated().map { (i, views) in
                let stack: Stack<TestView>?
                if views.isEmpty {
                    stack = nil
                } else {
                    stack = Stack(up: List(collection: views.dropLast()), focus: views.last!, down: List.empty)
                }
                return Workspace(tag: String(i), layout: layout, stack: stack)
            }

            let workspace = workspaces.removeLast()
            let current = Output(data: (), workspace: workspace)

            var visible: [Output<TestLayout>] = []
            for _ in 1..<numberOfOutputs {
                visible.append(Output(data: (), workspace: workspaces.removeLast()))
            }

            return ViewSet<TestLayout, TestView>(current: current, visible: visible, hidden: workspaces)
        }
    }
}


public final class ViewSetTests: XCTestCase {

    func testMapWorkspacesOnEmptyViewSet() {
        let viewSet = self.createEmptyViewSet()

        XCTAssertEqual(viewSet.mapWorkspaces { $0 }, viewSet)
    }

    func testMapWorkspaces() {
        property("mapWorkspaces with identity returns workspace again") <- forAll {
            (viewSet: ViewSet<TestLayout, TestView>) in
            viewSet.mapWorkspaces { $0 } == viewSet
        }

        property("mapWorkspaces maps all workspaces with f") <- forAll { (viewSet: ViewSet<TestLayout, TestView>) in
            let mappedViewSet = viewSet.mapWorkspaces { $0.replace(tag: $0.tag + " mapped") }

            return viewSet.workspaces().map { $0.tag + " mapped" } == mappedViewSet.workspaces().map { $0.tag }
        }
    }

    func testGreedyView() {
        property("greedyView returns unmodified ViewSet for unknown tag") <- forAll {
            (viewSet: ViewSet<TestLayout, TestView>) in
            viewSet.greedyView(tag: "unknown") == viewSet
        }

        property("greedyView returns unmodified ViewSet for current tag") <- forAll {
            (viewSet: ViewSet<TestLayout, TestView>) in
            viewSet.greedyView(tag: viewSet.current.workspace.tag) == viewSet
        }

        property("greedyView swaps workspaces of visible outputs") <- forAll {
            (viewSet: ViewSet<TestLayout, TestView>) in
            !viewSet.visible.isEmpty ==>
                viewSet
                    .greedyView(tag: viewSet.visible.first!.workspace.tag)
                    .greedyView(tag: viewSet.current.workspace.tag)
                == viewSet
        }
    }

    func testReflexivity() {
        // Doesn't really test ViewSet, but rather that our Equatable implementation is sane
        property("viewSet is equal to itself") <- forAll { (viewSet: ViewSet<TestLayout, TestView>) in
            return viewSet == viewSet
        }
    }

    private func createEmptyViewSet() -> ViewSet<TestLayout, TestView> {
        let workspace = Workspace(tag: "test", layout: TestLayout())
        let output = Output(data: (), workspace: workspace)
        return ViewSet<TestLayout, TestView>(current: output, hidden: [])
    }
}
