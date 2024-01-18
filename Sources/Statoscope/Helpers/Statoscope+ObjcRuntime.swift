//
//  Statoscope+ObjcRuntime.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

internal func associatedObject<ValueType: AnyObject>(base: AnyObject, key: UnsafePointer<UInt8>, initialiser: () -> ValueType) -> ValueType {
    guard let associated = objc_getAssociatedObject(base, key) as? ValueType else {
        let associated = initialiser()
        objc_setAssociatedObject(base, key, associated,
                                 .OBJC_ASSOCIATION_RETAIN)
        return associated
    }
    return associated
}

internal func optionalAssociatedObject<ValueType: AnyObject>(base: AnyObject, key: UnsafePointer<UInt8>, initialiser: () -> ValueType?) -> ValueType? {
    guard let associated = objc_getAssociatedObject(base, key) as? ValueType else {
        let associated = initialiser()
        if associated != nil {
            objc_setAssociatedObject(base, key, associated!,.OBJC_ASSOCIATION_RETAIN)
        }
        return associated
    }
    return associated
}

internal func associateObject<ValueType: AnyObject>(base: AnyObject, key: UnsafePointer<UInt8>, value: ValueType){
    objc_setAssociatedObject(base, key, value, .OBJC_ASSOCIATION_RETAIN)
}

internal func associateOptionalObject<ValueType: AnyObject>(base: AnyObject, key: UnsafePointer<UInt8>, value: ValueType?){
    objc_setAssociatedObject(base, key, value, .OBJC_ASSOCIATION_RETAIN)
}
