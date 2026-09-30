//
//  Subscope.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import Combine

public protocol IsSubscopeToMirror {}
protocol IsOptionalType {
    var isNil: Bool { get }
}
extension Optional: IsOptionalType {
    var isNil: Bool {
        self == nil
    }
}

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
            if nil != enclosingInstance._parentNode, enclosingInstance._parentNode is IsOptionalType {
                let optionalWrappedKeyPath = (\T?.self! as KeyPath<T?, T>).appending(path: wrappedKeyPath)
                enclosingInstance.assignChildOnPropertyWrapperGet(val, keyPath: optionalWrappedKeyPath)
            } else {
                enclosingInstance.assignChildOnPropertyWrapperGet(val, keyPath: wrappedKeyPath)
            }
            return val
        }
        set {
            if let storageOpt = enclosingInstance[keyPath: storageKeyPath].storage as? IsOptionalType,
               let newOptValue = newValue as? IsOptionalType,
               storageOpt.isNil && newOptValue.isNil {
                return
            }

            // Enclosing ObservableObject will be notified when assigned:
            if let enclosingObservable = enclosingInstance as? (any ObservableObject) {
                let publisher = enclosingObservable.objectWillChange as any Publisher
                // swiftlint:disable:next force_cast
                (publisher as! ObservableObjectPublisher).send()
            }

            // Was this child already parented before this assignment? Read before
            // assignChildOnPropertyWrapperSet below (which sets _parentNode) so that
            // @SuperScope(observed: true)'s relay — wired further down — only ever gets wired
            // once per child instance. Re-wiring an already-wired child on a redundant
            // reassignment would add a duplicate Combine subscription, firing the child's
            // objectWillChange more than once for a single ancestor mutation.
            let wasAlreadyParented = newValue._parentNode != nil

            // Storage assignment
            enclosingInstance[keyPath: storageKeyPath].storage = newValue

            // Children maintenance (for injection retrieval)
            if nil != enclosingInstance._parentNode, enclosingInstance._parentNode is IsOptionalType {
                let optionalWrappedKeyPath = (\T?.self! as KeyPath<T?, T>).appending(path: wrappedKeyPath)
                enclosingInstance.assignChildOnPropertyWrapperSet(
                    newValue,
                    keyPath: optionalWrappedKeyPath,
                    isOptional: true
                )
            } else {
                enclosingInstance.assignChildOnPropertyWrapperSet(
                    newValue,
                    keyPath: wrappedKeyPath,
                    isOptional: false
                )
            }

            // Wire any @SuperScope(observed: true) relay now that _parentNode is established
            // (resolveAncestor needs it to find this child's ancestors) — a Reducer's Store
            // hosted as a classic Statostore's @Subscope child never goes through
            // Store<R>.applyChildSlots, which is what wires this relay for @SubState children.
            if !wasAlreadyParented {
                (newValue as? any _SuperSlotWireable)?._wireSuperSlots()
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
