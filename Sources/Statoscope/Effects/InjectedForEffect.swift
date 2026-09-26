//
//  InjectedEffect.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 6/6/25.
//

@propertyWrapper
public struct InjectedForEffect<Value: Injectable>: CustomDebugStringConvertible {
    private let box = InjectionBox<Value>()

    public init() {}

    public var wrappedValue: Value {
        box.node?._resolve() ?? .defaultValue
    }

    final class InjectionBox<T: Injectable> {
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

/// `InjectedForEffect`'s counterpart for a protocol-typed effect dependency — see
/// `InjectionKey`'s own doc for why `Injectable` alone can't do this. Backs `@InjectedParamByKey`
/// on an `@EffectStruct` function: the macro generates `@InjectedForEffectByKey(key) var x: T` on
/// the synthesized struct in place of `@InjectedForEffect var x: T`.
///
/// `box` is declared first, deliberately — `Effect._injectNode`'s reflection walk
/// (`InjectedForEffect.swift`, below) grabs each wrapped property's *first* stored property and
/// checks it against `AnyEffectInjectable`; this must mirror `InjectedForEffect`'s own layout.
@propertyWrapper
public struct InjectedForEffectByKey<Value>: CustomDebugStringConvertible {
    private let box = InjectionBox()
    private let key: InjectionKey<Value>

    public init(_ key: InjectionKey<Value>) {
        self.key = key
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

extension InjectedForEffectByKey: HasObjectToBeDescribedForMirror {
    var objectToBeDescribed: Any {
        return wrappedValue
    }
}

extension InjectedForEffectByKey.InjectionBox: AnyEffectInjectable {
    public func _injectNode(_ node: InjectionTreeNode) {
        self.node = node
    }
}

extension InjectedForEffectByKey: Equatable {
    public static func == (lhs: InjectedForEffectByKey<Value>, rhs: InjectedForEffectByKey<Value>) -> Bool {
        type(of: lhs) == type(of: rhs)
    }
}

/// Marks an `@EffectStruct` function parameter as resolved from the injection tree (via
/// `@InjectedForEffect` on the generated struct) rather than stored/compared as an ordinary
/// parameter. Purely a marker at the call site — `wrappedValue` is never read for anything but
/// passthrough; not constrained to `Injectable` because nothing here ever needs a default (that's
/// `InjectedForEffect`'s job, downstream, on the generated struct).
@propertyWrapper
public struct InjectedParam<T> {
    public var wrappedValue: T
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}

/// `InjectedParam`'s counterpart for a protocol-typed effect dependency — see `InjectionKey`'s
/// own doc for why `Injectable` alone can't do this. `@EffectStruct` generates
/// `@InjectedForEffectByKey(key)` on the effect struct for a parameter marked this way, instead
/// of `@InjectedForEffect`. The `key` argument here only needs to make `@InjectedParamByKey(key)
/// name: T` valid Swift at the function declaration (SE-0293 property wrappers on parameters
/// support this) — the macro reads the key from the attribute's own source text to generate the
/// struct's property, never from this wrapper's runtime state.
@propertyWrapper
public struct InjectedParamByKey<T> {
    public var wrappedValue: T
    public init(wrappedValue: T, _ key: InjectionKey<T>) {
        self.wrappedValue = wrappedValue
    }
}

extension InjectedForEffect: Equatable {
    public static func == (lhs: InjectedForEffect<Value>, rhs: InjectedForEffect<Value>) -> Bool {
        type(of: lhs) == type(of: rhs)
    }
}

protocol AnyEffectInjectable {
    mutating func _injectNode(_ node: InjectionTreeNode)
}
extension InjectedForEffect.InjectionBox: AnyEffectInjectable {
    public func _injectNode(_ node: InjectionTreeNode) {
        self.node = node
    }
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
