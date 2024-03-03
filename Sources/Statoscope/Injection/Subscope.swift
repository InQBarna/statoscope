//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import Combine

public protocol IsSubscopeToMirror {}
protocol IsOptionalType {}
extension Optional: IsOptionalType {}

//
// A property wrapper
//  AND: triggers an objectwillChange on containing ObserverObject
//       when a new value is assigned. Only when the value is a new instance nil/instance/new
// Inject library uses also this property to keep track of parent-child relations
//  so it can navigate thru all model->submodel-> hierarchy for injection and debug
//
@propertyWrapper
public struct Subscope<Value: InjectionTreeNodeProtocol>: CustomStringConvertible, IsSubscopeToMirror {

    private var storage: Value

    public init(wrappedValue: Value) {
        storage = wrappedValue
    }

    public static subscript<T: InjectionTreeNode>(
        _enclosingInstance enclosingInstance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            let val: Value = enclosingInstance[keyPath: storageKeyPath].storage
            if nil != enclosingInstance.parentNode, enclosingInstance.parentNode is IsOptionalType {
                let optionalWrappedKeyPath = (\T?.self! as KeyPath<T?, T>).appending(path: wrappedKeyPath)
                enclosingInstance.assignChildOnPropertyWrapperGet(val, keyPath: optionalWrappedKeyPath)
            } else {
                enclosingInstance.assignChildOnPropertyWrapperGet(val, keyPath: wrappedKeyPath)
            }
            return val
        }
        set {
            // Enclosing ObservableObject will be notified when assigned:
            if let enclosingObservable = enclosingInstance as? (any ObservableObject) {
                let publisher = enclosingObservable.objectWillChange as any Publisher
                // swiftlint:disable:next force_cast
                (publisher as! ObservableObjectPublisher).send()
            }

            // Storage assignment
            enclosingInstance[keyPath: storageKeyPath].storage = newValue

            // Children maintenance (for injection retrieval)
            if nil != enclosingInstance.parentNode, enclosingInstance.parentNode is IsOptionalType {
                let optionalWrappedKeyPath = (\T?.self! as KeyPath<T?, T>).appending(path: wrappedKeyPath)
                enclosingInstance.assignChildOnPropertyWrapperGet(newValue, keyPath: optionalWrappedKeyPath)
            } else {
                enclosingInstance.assignChildOnPropertyWrapperSet(newValue, keyPath: wrappedKeyPath)
            }
        }
    }

    @available(*, unavailable,
        message: "@Published can only be applied to classes"
    )

    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError("\(newValue)") }
    }
    
    public var description: String {
        "\(storage)".removeOptionalDescription
    }
}
