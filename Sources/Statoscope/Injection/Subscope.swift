//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import Combine

//
// A property wrapper
//  AND: triggers an objectwillChange on containing ObserverObject
//       when a new value is assigned. Only when the value is a new instance nil/instance/new
// Inject library uses also this property to keep track of parent-child relations
//  so it can navigate thru all model->submodel-> hierarchy for injection and debug
//
@propertyWrapper
public struct Subscope<Value: ChainLinkProtocol> {

    private var storage: Value

    public init(wrappedValue: Value) {
        storage = wrappedValue
    }
    
    static private func assignChildChain<T: ChainLink & ObservableObject>(
        _ enclosingInstance: T,
        _ newValue: Value
    ) {
        enclosingInstance.assignChild(newValue)
        enclosingInstance.cleanupChildren()
        
        // Debug
        // enclosingInstance.root.printRootTree()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak root = enclosingInstance.root] in
            root?.cleanupChildren()
            // root?.printRootTree()
        }
    }
    
    public static subscript<T: ChainLink & ObservableObject>(
        _enclosingInstance enclosingInstance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            let val: Value = enclosingInstance[keyPath: storageKeyPath].storage
            if !val.parentAssigned {
                Self.assignChildChain(enclosingInstance, val)
            }
            return val
        }
        set {
            // Enclosing ObservableObject will be notified when assigned:
            let publisher = enclosingInstance.objectWillChange
            (publisher as! ObservableObjectPublisher).send()
            
            // Storage assignment
            enclosingInstance[keyPath: storageKeyPath].storage = newValue
            
            // Children maintenance (for injection retrieval)
            Self.assignChildChain(enclosingInstance, newValue)
        }
    }

    @available(*, unavailable,
        message: "@Published can only be applied to classes"
    )
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
}
