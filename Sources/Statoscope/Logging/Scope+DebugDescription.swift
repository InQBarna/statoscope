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
                    return "\(label): \(child.value)".indentDumpedObject()
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
