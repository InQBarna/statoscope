//
//  File.swift
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
        "\(type(of: self))(" +
            .newLine +
            Mirror(reflecting: self)
                .children
                .compactMap { (child) in
                    guard let label = child.label else {
                        return nil
                    }
                    let valueDescription: String
                    if let fixedDescription = child.value as? WithFixedDebugDescription {
                        valueDescription = fixedDescription.fixedDebugDescription
                    } else {
                        valueDescription = String(describing: child.value)
                    }
                    return "\(label): \(valueDescription)".indentDumpedObject()
                }
                .joined(separator: .newLine) +
            .newLine +
            self.effectsDescription() +
            ")"
    }
    
    private func effectsDescription() -> String {
        guard let statostore = self as? (any StoreProtocol) else {
            return ""
        }
        return statostore.effectsDescription()
    }
}

public extension StoreProtocol {
    fileprivate func effectsDescription() -> String {
        guard effectsState.effects.count > 0 else {
            return ""
        }
        let description = "effects: [" +
            .newLine +
            effectsState.effects
                .map { effect in
                    String(describing: effect)
                }
                .joined(separator: String.newLine) +
            .newLine +
            "]"
        return description.indentDumpedObject() +
            .newLine
    }
}
