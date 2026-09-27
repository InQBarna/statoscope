//
//  InjectedByKey.swift
//
//
//  Created by Claude Code on 26/9/26.
//

import Foundation

/// `Injected`'s counterpart for a protocol-typed dependency — see `InjectionKey`'s own doc for
/// why `Injectable` alone can't do this. Additive: existing `@Injected` code is untouched: this
/// is a second way to inject, not a replacement.
///
/// ```swift
/// let NetworkServiceKey = InjectionKey<NetworkService>(defaultValue: RealNetworkService())
///
/// final class MyScope: Statostore {
///     @InjectedByKey(NetworkServiceKey) var service: NetworkService
/// }
/// ```
@propertyWrapper
public struct InjectedByKey<Value> {

    private let key: InjectionKey<Value>
    private var overwrittingValue: Value?

    public init(_ key: InjectionKey<Value>) {
        self.key = key
    }

    /// Reaches for the key through its `InjectionKeyProviding` conforming type instead of a
    /// separately-named global — see that protocol's own doc.
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
                assertionFailure("InjectedByKey is a read-only property, only assignable for previews or ui tests")
            }
        }
    }

    @available(*, unavailable,
        message: "InjectedByKey can only be applied to classes"
    )
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError("\(newValue)") }
    }
}

extension InjectedByKey: IsInjectedToMirror { }
