//
//  RequesterTests.swift
//  Requester
//
//  Created by Pavel Sharanda on {TODAY}.
//  Copyright © 2017 Requester. All rights reserved.
//

import Foundation
import XCTest
import Requester

class RequesterTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        //// XCTAssertEqual(Requester().text, "Hello, World!")
    }
}

#if os(Linux)
extension RequesterTests {
    static var allTests : [(String, (RequesterTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
#endif
