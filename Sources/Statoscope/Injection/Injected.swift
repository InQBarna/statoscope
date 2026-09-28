//
//  Injected.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Declares an ambient dependency, resolved from the injection tree, using whatever default an
/// `Injectable`-conforming type declares (see that protocol's own doc for the two shapes it
/// supports — a concrete type's own default, or a protocol's via a named real implementation):
/// ```swift
/// final class MyScope: Statostore {
///     @Injected(DateProvider.self) var dates: DateProvider          // Injectable value type
///     @Injected(RealLogger.self) var logger: Logger                 // protocol type
/// }
/// ```
@propertyWrapper
public struct Injected<Value> {

    private let defaultValue: Value
    private var overwrittingValue: Value?

    /// Reaches for the type's own declared default — see `Injectable`'s own doc.
    public init<P: Injectable>(_ providerType: P.Type) where P.InjectedValue == Value {
        self.defaultValue = providerType.defaultValue
    }

    public static subscript<T: InjectionTreeNode>(
        _enclosingInstance enclosingInstance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            let storage = enclosingInstance[keyPath: storageKeyPath]
            if let overwrite = storage.overwrittingValue {
                return overwrite
            }
            return enclosingInstance._resolve(storage.defaultValue, appendingLog: String(describing: storageKeyPath))
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

protocol IsInjectedToMirror { }
extension Injected: IsInjectedToMirror { }
