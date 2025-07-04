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

@propertyWrapper
public struct InjectedParam<T: Injectable> {
    public var wrappedValue: T
    public init(wrappedValue: T) {
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
