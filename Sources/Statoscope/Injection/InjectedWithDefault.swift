//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

@propertyWrapper
public struct InjectedWithDefault<Value> {

    private var overwrittingValue: Value?
    private var defaultValue: Value
#if false
    // Need some mechanism to invalidate this cached value, to be created and then we can recover caches
    private var cachedValue: Value?
#endif

    public init(_ defaultValue: Value) {
        self.defaultValue = defaultValue
    }

    public static subscript<T: InjectionTreeNode>(
        _enclosingInstance enclosingInstance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
#if false
            if let cached = enclosingInstance[keyPath: storageKeyPath].cachedValue {
                return cached
            }
            let result: Value = try enclosingInstance.resolveObject()
            enclosingInstance[keyPath: storageKeyPath].cachedValue  = result
            return result
#else
            do {
                return try enclosingInstance.resolveUnsafe()
            } catch {
                return enclosingInstance[keyPath: storageKeyPath].defaultValue
            }
#endif
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

    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError("\(newValue)") }
    }
}
