//
//  Injected.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Declares an ambient dependency, resolved from the injection tree. `Value` can be any
/// `Injectable`-conforming type (gets its key for free, see `Injectable`'s own doc) or any real
/// Swift protocol whose default implementation conforms to `InjectionKeyProviding`:
/// ```swift
/// final class MyScope: Statostore {
///     @Injected(DateProvider.self) var dates: DateProvider          // Injectable value type
///     @Injected(RealLogger.self) var logger: Logger                 // protocol type
///     @Injected(someExplicitKey) var other: OtherType                // one-off InjectionKey value
/// }
/// ```
@propertyWrapper
public struct Injected<Value> {

    private let key: InjectionKey<Value>
    private var overwrittingValue: Value?

    public init(_ key: InjectionKey<Value>) {
        self.key = key
    }

    /// Reaches for the key through its `InjectionKeyProviding` conforming type instead of a
    /// separately-named global — see that protocol's own doc. Also covers any `Injectable` type,
    /// which conforms to `InjectionKeyProviding` automatically.
    public init<P: InjectionKeyProviding>(_ providerType: P.Type) where P.InjectedValue == Value {
        self.key = providerType.injectionKey
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
            return enclosingInstance._resolve(storage.key, appendingLog: String(describing: storageKeyPath))
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
