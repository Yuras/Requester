//
//  Created by Pavel Sharanda
//  Copyright © 2017 Requester. All rights reserved.
//

import Foundation

public protocol RequestCancelable {
    func cancel()
}

public enum RequestResult<T> {
    case success(T)
    case failure(Error)
    case cancelled
}

public enum RequestEither<T, U> {
    case left(T)
    case right(U)
}

public struct Requester<T> {
    
    private let requestImpl: (@escaping (RequestResult<T>) -> Void)->(RequestCancelable)
    
    public init(request: @escaping (@escaping (RequestResult<T>) -> Void)->(RequestCancelable)) {
        requestImpl = request
    }
    
    public init(result: RequestResult<T>) {
        requestImpl =  { completion in
            completion(result)
            return EmptyRequestCancelable()
        }
    }
    
    public func request(_ completion: @escaping (RequestResult<T>) -> Void) -> RequestCancelable {
        return requestImpl(completion)
    }
    
    public func request() -> RequestCancelable {
        return request { _ in }
    }
    
    public func then<U>(_ requester: @escaping (T)->Requester<U>) -> Requester<U> {
        return Requester<U> { completion  in
            let serial = SerialRequestCancelable()
            serial.cancelable = self.request { result in
                switch result {
                case .success(let value):
                    serial.cancelable = requester(value).request(completion)
                case .failure(let error):
                    completion(.failure(error))
                case .cancelled:
                    completion(.cancelled)
                }
            }
            return serial
        }
    }
    
    public func map<U>(_ transform: @escaping (T)-> U) -> Requester<U> {
        return Requester<U> { completion in
            return self.request { result in
                switch result {
                case .success(let value):
                    completion(.success(transform(value)))
                case .failure(let error):
                    completion(.failure(error))
                case .cancelled:
                    completion(.cancelled)
                }
            }
        }
    }
    
    public func flatMap<U>(_ transform: @escaping (T)-> RequestResult<U>) -> Requester<U> {
        return Requester<U> { completion in
            return self.request { result in
                switch result {
                case .success(let value):
                    completion(transform(value))
                case .failure(let error):
                    completion(.failure(error))
                case .cancelled:
                    completion(.cancelled)
                }
            }
        }
    }
    
    public func onSuccess(_ handler:  @escaping(T) -> Void) -> Requester<T> {
        return Requester { completion in
            return self.request { result in
                switch result {
                case .success(let value):
                    handler(value)
                    completion(.success(value))
                case .failure(let error):
                    completion(.failure(error))
                case .cancelled:
                    completion(.cancelled)
                }
            }
        }
    }

    public func onFailure(_ handler:  @escaping(Error) -> Void) -> Requester<T> {
        return Requester { completion in
            return self.request { result in
                switch result {
                case .success(let value):
                    completion(.success(value))
                case .failure(let error):
                    handler(error)
                    completion(.failure(error))
                case .cancelled:
                    completion(.cancelled)
                }
            }
        }
    }
    
    public func onCancelled(_ handler:  @escaping() -> Void) -> Requester<T> {
        return Requester { completion in
            return self.request { result in
                switch result {
                case .success(let value):
                    completion(.success(value))
                case .failure(let error):
                    completion(.failure(error))
                case .cancelled:
                    handler()
                    completion(.cancelled)
                }
            }
        }
    }

    /**
     Run two requests concurrently, return the result of the first successfull one, other one will be cancelled. When one of them fails, other one is cancelled. On cancel, it cancelles both children.
     */
    public func race<U>(_ right: Requester<U>) -> Requester<RequestEither<T,U>> {
        let left = self
        return Requester<RequestEither<T,U>> { completion in
            var leftRequest: RequestCancelable?
            var rightRequest: RequestCancelable?

            // done means that we already called the completion
            var done = false
            // number of childred exited so far
            var exited = 0

            func handler(other: RequestCancelable?) -> ((RequestResult<RequestEither<T,U>>) -> Void) {
                return { result in
                    exited += 1

                    guard !done else {
                        // other one already called completion, nothing to do here
                        return
                    }

                    switch result {
                    case .success(let value):
                        // we are the winner!
                        done = true
                        other?.cancel()
                        completion(.success(value))
                    case .failure(let error):
                        // we are the failing winner...
                        done = true
                        other?.cancel()
                        completion(.failure(error))
                    case .cancelled:
                        if exited == 2 {
                            // we are the last cancelled child, lets notify parent
                            done = true
                            completion(.cancelled)
                        }
                    }
                }
            }

            leftRequest = left.map{.left($0)}.request(handler(other: rightRequest))

            // Note that left could immediately return result (or just fail)
            // We don't need to start the right one in that case
            if !done {
                rightRequest = right.map{.right($0)}.request(handler(other: leftRequest))
            }

            return DelegateRequestCancelable {
                leftRequest?.cancel()
                rightRequest?.cancel()
            }
        }
    }

    /** Run two request concurrently, wait for both to succeed and return both results. If one fails, then other one will be cancelled.
     */
    public func concurrently<U>(_ right: Requester<U>) -> Requester<(T, U)> {
        let left = self
        return Requester<(T,U)> { completion in
            var leftRequest: RequestCancelable?
            var rightRequest: RequestCancelable?

            // done means that we already called the completion
            var done = false
            // number of childred exited so far
            var exited = 0

            func handler<R>(other: RequestCancelable?, block: @escaping (R)->Void) -> ((RequestResult<R>) -> Void) {
                return { result in
                    exited += 1

                    guard !done else {
                        // other one already called completion, nothing to do here
                        return
                    }

                    switch result {
                    case .success(let value):
                        block(value)
                    case .failure(let error):
                        done = true
                        other?.cancel()
                        completion(.failure(error))
                    case .cancelled:
                        if exited == 2 {
                            // we are the last cancelled child, lets notify parent
                            done = true
                            completion(.cancelled)
                        }
                    }
                }
            }

            var t: T?
            var u: U?

            func onResult() {
                guard let t = t else {
                    return
                }
                guard let u = u else {
                    return
                }
                // both results are available
                done = true
                completion(.success(t,u))
            }

            leftRequest = left.request(handler(other: rightRequest) { value in
                t = value
                onResult()
            })

            // Note that left could immediately fail
            // We don't need to start the right one in that case
            if !done {
                rightRequest = right.request(handler(other: leftRequest) { value in
                    u = value
                    onResult()
                })
            }

            return DelegateRequestCancelable {
                leftRequest?.cancel()
                rightRequest?.cancel()
            }
        }
    }

    /**
     Run a number of requests one by one in a sequence
     */
    public static func sequence(_ requests: [Requester<T>]) -> Requester<[T]> {
        let empty = Requester<[T]>(result:.success([]))
        return requests.reduce(empty) { left, right in
            left.then { result in
                right.map { t in
                    result + [t]
                }
            }
        }
    }

    /**
     Run a number of requests concurrently
     */
    public static func concurrently(_ requests: [Requester<T>]) -> Requester<[T]> {
        let empty = Requester<[T]>(result:.success([]))
        return requests.reduce(empty) { left, right in
            left.concurrently(right).map { (result, t) in
                result + [t]
            }
        }
    }
}

private class DelegateRequestCancelable: RequestCancelable {
    var cancelImp: ((Void) -> (Void))?

    init(cancelImp: @escaping (Void) -> Void) {
        self.cancelImp = cancelImp
    }

    func cancel() {
        cancelImp?()
        cancelImp = nil
    }
}

private class SerialRequestCancelable: RequestCancelable {
    var cancelable: RequestCancelable?
    
    func cancel() {
        cancelable?.cancel()
        cancelable = nil
    }
}

private class EmptyRequestCancelable: RequestCancelable {
    func cancel() { }
}


