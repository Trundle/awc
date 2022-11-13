import XCTest

import DataStructures


class LRUCacheTests: XCTestCase {
    func testCachesValues() {
        let cache: LRUCache<String, Int> = LRUCache(maxSize: 1)
        cache.add(key: "the key", value: 42)
        XCTAssertEqual(42, cache.get(forKey: "the key"))
    }

    func testDropsOldValues() {
        let cache: LRUCache<String, Int> = LRUCache(maxSize: 2)
        cache.add(key: "the key", value: 42)
        for i in 1...10 {
            cache.add(key: String(i), value: i)
            _ = cache.get(forKey: "the key")
        }
        XCTAssertEqual(42, cache.get(forKey: "the key"))
        XCTAssertEqual(10, cache.get(forKey: "10"))
        XCTAssertNil(cache.get(forKey: "9"))
    }

    func testSubscript() {
        let cache: LRUCache<String, Int> = LRUCache(maxSize: 1)
        cache["spam"] = 42

        XCTAssertEqual(42, cache["spam"])
        XCTAssertEqual(42, cache.get(forKey: "spam"))
    }
}
