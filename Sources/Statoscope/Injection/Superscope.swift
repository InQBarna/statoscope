//
//  Superscope.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import Combine

// TODO: Decouple from ObservableObject
@propertyWrapper
public struct Superscope<Value: Injectable & ObservableObject>: CustomStringConvertible {

    private var observed: Bool = false
    private var cancellable: AnyCancellable?
    private var overwrittingValue: Value?

    public init(observed: Bool = false) {
        self.observed = observed
    }

    public static subscript<T: InjectionTreeNode & ObservableObject>(
        _enclosingInstance enclosingInstance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            // Debug value
            if let overwrite = enclosingInstance[keyPath: storageKeyPath].overwrittingValue {
                return overwrite
            }

            // return try enclosingInstance.resolve()
            let foundSuper: Value = enclosingInstance.resolve()

            // Listen to parent
            if enclosingInstance[keyPath: storageKeyPath].observed,
               nil == enclosingInstance[keyPath: storageKeyPath].cancellable {
                enclosingInstance[keyPath: storageKeyPath].cancellable =
                foundSuper.objectWillChange.sink(receiveValue: { [weak enclosingInstance] _ in
                    // no compila lo de debajo ??
                    // instance?.objectWillChange.send()
                    if let publisher = enclosingInstance?.objectWillChange {
                        // swiftlint:disable:next force_cast
                        (publisher as! ObservableObjectPublisher).send()
                    }
                })
            }
            return foundSuper
        }
        set {
            if nil != NSClassFromString("XCTest") ||
               ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                enclosingInstance[keyPath: storageKeyPath].overwrittingValue = newValue
            } else {
                fatalError("Don't assign values to an injected property wrapper")
            }
        }
    }

    @available(*, unavailable,
        message: "@Superscope can only be applied to Injectable"
    )

    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError("\(newValue)") }
    }

    public var description: String {
        if let overwrittingValue {
            return "\(overwrittingValue)" // .removeOptionalDescription
        } else {
            return "\(Value.self)"
        }
    }
}
