//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

@propertyWrapper
struct Injected<Value: Injectable> {
    private var overwrittingValue: Value?
#if false
    // Need some mechanism to invalidate this cached value, to be created
    private var cachedValue: Value?
#endif
    static subscript<T: ChainLink>(
        _enclosingInstance enclosingInstance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            do {
                if let overwrite = enclosingInstance[keyPath: storageKeyPath].overwrittingValue {
                    return overwrite
                }
#if false
                if let cached = enclosingInstance[keyPath: storageKeyPath].cachedValue {
                    return cached
                }
                let result: Value = try enclosingInstance.resolveObject()
                enclosingInstance[keyPath: storageKeyPath].cachedValue  = result
                return result
#else
                return try enclosingInstance.resolveObject()
#endif
            } catch {
                return Value.defaultValue
            }
        }
        set {
            if nil != NSClassFromString("XCTest") ||
               ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                enclosingInstance[keyPath: storageKeyPath].overwrittingValue = newValue
            } else {
                assertionFailure("Injected is a read-only property, only assignable for previews or ui tests")
            }
        }
    }
    @available(*, unavailable,
        message: "@Injected can only be applied to classes"
    )
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
}
