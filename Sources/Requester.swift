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


