//
//  Created by Pavel Sharanda on 06.04.17.
//  Copyright © 2017 Requester. All rights reserved.
//

import Foundation

extension DispatchQueue {
    
    private typealias Cancelation = () -> Void
    
    private class DispatchQueueCancelable: RequestCancelable {
        private var cancelableClosure: DispatchQueue.Cancelation?
        
        init(cancelableClosure: @escaping DispatchQueue.Cancelation) {
            self.cancelableClosure = cancelableClosure
        }
        
        func cancel() {
            cancelableClosure?()
            cancelableClosure = nil
        }
    }
    
    public func after(timeInterval: TimeInterval, block: @escaping (Bool)->Void) ->  RequestCancelable {
        var cancelled = false
        
        let cancelableClosure = {
            cancelled = true
        }
        
        asyncAfter(deadline: .now() + timeInterval) {
            block(cancelled)
        }
        
        return DispatchQueueCancelable(cancelableClosure: cancelableClosure);
    }
    
    public func run<T>(task: @escaping (Bool)->T, completionQueue: DispatchQueue = .main, completion: @escaping (T)->Void) -> RequestCancelable {
        var cancelled = false
        
        let cancelableClosure = {
            cancelled = true
        }
        
        async {
            let result = task(cancelled)
            completionQueue.async {
                completion(result)
            }
        }
        
        return DispatchQueueCancelable(cancelableClosure: cancelableClosure);
    }
}
