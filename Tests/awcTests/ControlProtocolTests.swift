import XCTest

import Libawc

public final class CtlProtocolDecoderTests: XCTestCase {
    func testShortReadsResultInRequest() {
        let decoder = CtlProtocolDecoder()

        var requests: [CtlRequest] = []

        requests = "\u{16}".withCString() {
            try! decoder.pushBytes(bytes: $0, count: 1)
        }
        XCTAssertTrue(requests.isEmpty)

        requests = "\0\0\0".withCString() {
            try! decoder.pushBytes(bytes: $0, count: 3)
        }
        XCTAssertTrue(requests.isEmpty)

        requests = "{\"cmd\":\"list_layouts\"}".withCString() {
            try! decoder.pushBytes(bytes: $0, count: strlen($0))
        }
        XCTAssertEqual(1, requests.count)
        XCTAssertEqual(CtlRequest.listLayouts, requests[0])
    }

    func testOneReadResultsInRequest() {
        let decoder = CtlProtocolDecoder()

        let requests = "\u{16}\0\0\0{\"cmd\":\"list_layouts\"}".withCString() {
            try! decoder.pushBytes(bytes: $0, count: 26)
        }
        XCTAssertEqual(1, requests.count)
        XCTAssertEqual(CtlRequest.listLayouts, requests[0])
    }

    func testDecodesTwoRequests() {
        let decoder = CtlProtocolDecoder()

        let data =
            "\u{16}\0\0\0{\"cmd\":\"list_layouts\"}"
            + "\u{26}\0\0\0{\"cmd\":\"set_layout\",\"layout_number\":1}"
        let requests = data.withCString() {
            try! decoder.pushBytes(bytes: $0, count: 68)
        }
        XCTAssertEqual(2, requests.count)
        XCTAssertEqual(CtlRequest.setLayout(1), requests[1])
    }
}
