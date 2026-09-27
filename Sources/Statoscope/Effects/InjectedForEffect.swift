//
//  InjectedEffect.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 6/6/25.
//

/// Backs `@InjectedParam` on an `@EffectStruct` function — the macro generates
/// `@InjectedForEffect(key) var x: T` on the synthesized struct for a parameter marked
/// `@InjectedParam(key) x: T`.
///
/// `box` is declared first, deliberately — `Effect._injectNode`'s reflection walk (below) grabs
/// each wrapped property's *first* stored property and checks it against `AnyEffectInjectable`.
@propertyWrapper
public struct InjectedForEffect<Value>: CustomDebugStringConvertible {
    private let box = InjectionBox()
    private let key: InjectionKey<Value>

    public init(_ key: InjectionKey<Value>) {
        self.key = key
    }

    /// Reaches for the key through its `InjectionKeyProviding` conforming type instead of a
    /// separately-named global — see that protocol's own doc. Also covers any `Injectable` type,
    /// which conforms to `InjectionKeyProviding` automatically.
    public init<P: InjectionKeyProviding>(_ providerType: P.Type) where P.InjectedValue == Value {
        self.key = providerType.injectionKey
    }

    public var wrappedValue: Value {
        box.node?._resolve(key) ?? key.defaultValue
    }

    final class InjectionBox {
        var node: InjectionTreeNode?
    }

    public var debugDescription: String {
        String(describing: wrappedValue)
    }
}

extension InjectedForEffect: HasObjectToBeDescribedForMirror {
    var objectToBeDescribed: Any {
        return wrappedValue
    }
}

extension InjectedForEffect.InjectionBox: AnyEffectInjectable {
    public func _injectNode(_ node: InjectionTreeNode) {
        self.node = node
    }
}

extension InjectedForEffect: Equatable {
    public static func == (lhs: InjectedForEffect<Value>, rhs: InjectedForEffect<Value>) -> Bool {
        type(of: lhs) == type(of: rhs)
    }
}

/// Marks an `@EffectStruct` function parameter as resolved from the injection tree (via
/// `@InjectedForEffect` on the generated struct) rather than stored/compared as an ordinary
/// parameter. Purely a marker at the call site — `wrappedValue` is never read for anything but
/// passthrough. Always takes a key (an `InjectionKey<T>` value, or any `InjectionKeyProviding`
/// type via `SomeType.self`) — the macro reads it from the attribute's own source text to
/// generate the struct's property, never from this wrapper's runtime state, so the argument here
/// only needs to make `@InjectedParam(key) name: T` valid Swift at the function declaration
/// (SE-0293 property wrappers on parameters support this).
@propertyWrapper
public struct InjectedParam<T> {
    public var wrappedValue: T
    public init(wrappedValue: T, _ key: InjectionKey<T>) {
        self.wrappedValue = wrappedValue
    }

    /// Reaches for the key through its `InjectionKeyProviding` conforming type instead of a
    /// separately-named global — see that protocol's own doc. Also covers any `Injectable` type,
    /// which conforms to `InjectionKeyProviding` automatically.
    public init<P: InjectionKeyProviding>(wrappedValue: T, _ providerType: P.Type) where P.InjectedValue == T {
        self.wrappedValue = wrappedValue
    }
}

protocol AnyEffectInjectable {
    mutating func _injectNode(_ node: InjectionTreeNode)
}
extension Effect {
    public func _injectNode(_ node: InjectionTreeNode) {
        var mirror = Mirror(reflecting: self)
        while let current = mirror.superclassMirror {
            mirror = current
        }
        for child in mirror.children {
            guard var wrapper = Mirror(reflecting: child.value).children.first?.value as? AnyEffectInjectable else {
                continue
            }
            wrapper._injectNode(node)
        }
    }
}
