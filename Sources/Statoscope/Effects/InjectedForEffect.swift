//
//  InjectionBox.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 6/6/25.
//

@propertyWrapper
public struct InjectedForEffect<Value: Injectable> {
    private let box = InjectionBox<Value>()

    public init() {}

    public var wrappedValue: Value {
        box.node?._resolve() ?? .defaultValue
    }
    
    final class InjectionBox<Value: Injectable> {
        var node: InjectionTreeNode?
    }
}

protocol AnyEffectInjectable {
    mutating func _injectNode(_ node: InjectionTreeNode)
}
extension InjectedForEffect: AnyEffectInjectable {
    public mutating func _injectNode(_ node: InjectionTreeNode) {
        box.node = node
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
