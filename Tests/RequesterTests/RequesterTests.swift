//
//  Created by Pavel Sharanda
//  Copyright © 2017 Requester. All rights reserved.
//

import Foundation
import XCTest
import Requester

func requestHello(completion: @escaping (RequestResult<String>) -> Void)->(RequestCancelable) {
    return DispatchQueue.main.after(timeInterval: 0.2) { cancelled in
        if cancelled {
            completion(.cancelled)
        } else {
            completion(.success("Hello"))
        }
    }
}

func requestError(completion: @escaping (RequestResult<String>) -> Void)->(RequestCancelable) {
    return DispatchQueue.main.after(timeInterval: 0.2) { cancelled in
        if cancelled {
            completion(.cancelled)
        } else {
            completion(.failure(NSError(domain: "requester", code: -1, userInfo: nil)))
        }
    }
}

func requestWorld(head: String, completion: @escaping (RequestResult<String>) -> Void)->(RequestCancelable) {
    return DispatchQueue.main.after(timeInterval: 0.2) { cancelled in
        if cancelled {
            completion(.cancelled)
        } else {
            completion(.success(head + "World"))
        }
    }
}

func requestPunctuation(head: String, completion: @escaping (RequestResult<String>) -> Void)->(RequestCancelable) {
    return DispatchQueue.main.after(timeInterval: 1) { cancelled in
        if cancelled {
            completion(.cancelled)
        } else {
            completion(.success(head + "!!!"))
        }
    }
}

class RequesterTests: XCTestCase {
    
    func testRequest() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestHello)
        
        _ = r.request {
            switch $0 {
            case .success(let value):
                XCTAssertEqual("Hello", value)
            case .cancelled:
                XCTFail("should not be cancelled")
            case .failure(_):
                XCTFail("should not error")
            }
            expect.fulfill()
        }
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testRequestError() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestError)
        _ = r.request {
            switch $0 {
            case .success(_):
                XCTFail("should not have value")
            case .cancelled:
                XCTFail("should not be cancelled")
            case .failure(let error):
                XCTAssertEqual(-1, (error as NSError).code)
            }
            expect.fulfill()
        }
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testRequestCancel() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestHello)
        
        let c = r.request {
            switch $0 {
            case .success(_):
                XCTFail("should not have value")
            case .cancelled:
                break
            case .failure(_):
                XCTFail("should not error")
            }
            expect.fulfill()
        }
        
        c.cancel()
        
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThen() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestHello)
            .then { result in
                return Requester {
                    return requestWorld(head: result, completion: $0)
                }
            }
            .then { result in
                return Requester {
                    return requestPunctuation(head: result, completion: $0)
                }
            }
        
        _ = r.request {
            switch $0 {
            case .success(let value):
                XCTAssertEqual("HelloWorld!!!", value)
            case .cancelled:
                XCTFail("should not be cancelled")
            case .failure(_):
                XCTFail("should not error")
            }
            expect.fulfill()
        }
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThenError() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestHello)
            .then { result in
                return Requester(request: requestError)
            }
            .then { result in
                return Requester {
                    return requestPunctuation(head: result, completion: $0)
                }
            }
        
        _ = r.request {
            switch $0 {
            case .success(_):
                XCTFail("should not have value")
            case .cancelled:
                XCTFail("should not be cancelled")
            case .failure(let error):
                XCTAssertEqual(-1, (error as NSError).code)
            }
            expect.fulfill()
        }
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThenCancel() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestHello)
            .then { result in
                return Requester {
                    return requestWorld(head: result, completion: $0)
                }
            }
            .then { result in
                return Requester {
                    return requestPunctuation(head: result, completion: $0)
                }
            }
        
        let c = r.request {
            switch $0 {
            case .success(_):
                XCTFail("should not have value")
            case .cancelled:
                break
            case .failure(_):
                XCTFail("should not error")
            }
            expect.fulfill()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            c.cancel()
        }
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testOnSuccess() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestHello)
            .onSuccess {
                XCTAssertEqual("Hello", $0)
                expect.fulfill()
            }.onCancelled {
                XCTFail("should not be cancelled")
                expect.fulfill()
            }.onFailure { _ in
                XCTFail("error")
                expect.fulfill()
            }
        
        _ = r.request()
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testOnError() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestError)
            .onSuccess { _ in
                XCTFail("should not have value")
                expect.fulfill()
            }.onCancelled {
                XCTFail("should not be cancelled")
                expect.fulfill()
            }.onFailure { error in
                XCTAssertEqual(-1, (error as NSError).code)
                expect.fulfill()
            }
        
        
        _ = r.request()
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testOnCancel() {
        
        let expect = expectation(description: "result")
        
        let r = Requester(request: requestHello)
            .onSuccess { _ in
                XCTFail("should not have value")
                expect.fulfill()
            }.onCancelled {
                expect.fulfill()
            }.onFailure { _ in
                XCTFail("should not error")
                expect.fulfill()
        }
        let c = r.request()
        
        c.cancel()
        
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
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
