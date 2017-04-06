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
    public func race(_ right: Requester<T>) -> Requester<T> {
        let left = self
        return Requester<T> { completion in
            var leftRequest: RequestCancelable?
            var rightRequest: RequestCancelable?

            // done means that we already called the completion
            var done = false
            // number of childred exited so far
            var exited = 0

            func handler(other: RequestCancelable?) -> ((RequestResult<T>) -> Void) {
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

            leftRequest = left.request(handler(other: rightRequest))

            // Note that left could immediately return result (or just fail)
            // We don't need to start the right one in that case
            if !done {
                rightRequest = right.request(handler(other: leftRequest))
            }

            return DelegateRequestCancelable {
                leftRequest?.cancel()
                rightRequest?.cancel()
            }
        }
    }
}

class DelegateRequestCancelable: RequestCancelable {
    public var cancelImp: ((Void) -> (Void))?

    public init(cancelImp: @escaping (Void) -> Void) {
        self.cancelImp = cancelImp
    }

    func cancel() {
        guard let imp = cancelImp else {
            return
        }
        imp()
        self.cancelImp = nil
    }
}

private class SerialRequestCancelable: RequestCancelable {
    public var cancelable: RequestCancelable?
    
    public func cancel() {
        cancelable?.cancel()
        cancelable = nil
    }
}

private class EmptyRequestCancelable: RequestCancelable {
    func cancel() { }
}


