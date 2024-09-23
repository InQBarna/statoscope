//
//  Scope+DebugDescription.swift
//  
//
//  Created by Sergi Hernanz on 22/2/24.
//

import Foundation

extension String {
    static var newLine: String = "\n"
    static var newLineIndented: String = "\n  "
    func indentDumpedObject() -> Self {
        "  " +
        replacingOccurrences(of: String.newLine, with: String.newLineIndented)
    }
}

protocol WithFixedDebugDescription {
    var fixedDebugDescription: String { get }
}

extension Published: WithFixedDebugDescription {
    var fixedDebugDescription: String {
        guard let storageValue = Mirror(reflecting: self)
            .descendant("storage")
            .map(Mirror.init)?.children
            .first?.value else {
            return String(describing: self)
        }
        if let value = (storageValue as? Publisher)
            .map(Mirror.init)?.descendant("subject", "currentValue") {
            return String(describing: value)
        } else {
            return String(describing: storageValue)
        }
    }
}

public extension Scope {
    var debugDescription: String {
        describeObject(self, appending: self.effectsDescription())
    }

    private func effectsDescription() -> String {
        guard let statostore = self as? (any ScopeImplementation) else {
            return ""
        }
        return statostore.effectsDescription()
    }
}

fileprivate extension ScopeImplementation {
    func effectsDescription() -> String {
        guard effectsState.effects.count > 0 else {
            return ""
        }
        let description = "effects: [" +
            .newLine +
            effectsState.effects
                .map { effect in
                    describeObject(effect)
                }
                .joined(separator: .newLine) +
            .newLine +
            "]"
        return description.indentDumpedObject() +
            .newLine
    }
}

func describeObject(_ object: Any, appending: String = "") -> String {
    let mirror = Mirror(reflecting: object)
    let mirrorChildren = mirror.children
    if mirror.displayStyle == .optional && mirror.children.isEmpty {
        return "nil"
    } else if mirrorChildren.count == 0 {
        return String(describing: object) + appending
    } else if let anyEffect = object as? IsAnyEffectToMirror {
        return describeObject(anyEffect.objectToBeDescribed)
    } else {
        let childrenDescribed: [String] = mirrorChildren
            .compactMap { (child) in
                guard !(child.value is IsInjectedToMirror) else {
                    return nil
                }
                guard let label = child.label else {
                    return describeObject(child.value)
                }
                let valueDescription: String
                if let fixedDescription = child.value as? WithFixedDebugDescription {
                    valueDescription = fixedDescription.fixedDebugDescription
                } else if child.value is IsSubscopeToMirror {
                    valueDescription = String(describing: child.value)
                } else if let anyEffect = child.value as? IsAnyEffectToMirror {
                    valueDescription = describeObject(anyEffect.objectToBeDescribed)
                } else {
                    valueDescription = describeObject(child.value)
                }
                return "\(label): \(valueDescription)".indentDumpedObject()
            }
        if let firstDescribed = childrenDescribed.first,
           childrenDescribed.count == 1, mirror.displayStyle == .enum {
            // return "\(type(of: object))(\(firstDescribed))" + appending
            return .newLine + firstDescribed + appending
        } else {
            return "\(type(of: object))(" +
                .newLine +
                childrenDescribed.joined(separator: .newLine) +
                .newLine +
                appending +
            ")"
        }
    }
}
