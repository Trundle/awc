import SwiftCheck
import XCTest

import DataStructures
import Libawc
import Wlroots
import testHelpers

// Another Swift tuples workaround
fileprivate struct TestConfiguration {
    let nViews: Int
    let limit: Int
    let focusDown: Int
}

extension TestConfiguration: Arbitrary {
    static var arbitrary: Gen<TestConfiguration> {
        let smallInt = Gen<Int>.choose((1, 16))
        return Gen<TestConfiguration>.compose {
            TestConfiguration(
                nViews: $0.generate(using: smallInt),
                limit: $0.generate(using: smallInt),
                focusDown: $0.generate(using: smallInt)
            )
        }
    }
}

public final class CappedTests: XCTestCase {
    func testLimitsViews() {
        property("limits views") <- forAll { (config: TestConfiguration) in
            var stack = Stack.singleton(TestView())
            for i in 1..<config.nViews {
                stack = stack.insert(TestView(id: i))
            }
            for _ in 1...config.focusDown {
                stack = stack.focusDown()
            }
            let layout = Capped(
                layout: Tiled<TestView, ()>(split: 0.5, delta: 0.05),
                limit: config.limit)
            let workspace = Workspace(tag: "test", layout: layout)
            let output = Output(data: (), workspace: workspace)

            let arrangement = layout
                .doLayout(
                    dataProvider: NoDataProvider(),
                    output: output,
                    stack: stack,
                    box: wlr_box(x: 0, y: 0, width: 1024, height: 768))

            return arrangement.count == min(config.limit, config.nViews)
        }
    }    
}
