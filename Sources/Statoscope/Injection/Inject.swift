//
//  Inject.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
@propertyWrapper
public struct Inject<Value: Injectable> {

    private var initialValue: Value
    public init(wrappedValue: Value) {
        self.initialValue = wrappedValue
    }

    public static subscript<T: InjectionTreeNode>(
        _enclosingInstance enclosingInstance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            (try? enclosingInstance._resolveUnsafe(appendingLog: String(describing: storageKeyPath))) ??
            enclosingInstance[keyPath: storageKeyPath].initialValue
        }
        set {
            enclosingInstance.injectObject(newValue)
        }
    }

    @available(*, unavailable,
        message: "@Inject can only be applied to classes"
    )

    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError("\(newValue)") }
    }
}
