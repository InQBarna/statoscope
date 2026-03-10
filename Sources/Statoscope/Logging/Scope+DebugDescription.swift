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
    static var tab: String = "\t"
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
            return describeObject(value)
        } else {
            return describeObject(storageValue)
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

/// Returns a human-readable type name for logging.
///
/// For `@Reducer`-generated nested `Store` classes the simple type name is just
/// `"Store"`, which is ambiguous in logs. When that happens we fall back to the
/// fully-qualified name (e.g. `"MyReducer.Store"`), stripping the module prefix.
func scopeTypeName(for type: Any.Type) -> String {
    let simpleName = String(describing: type)
    guard simpleName == "Store" else { return simpleName }
    // Nested Store: strip module prefix from the fully-qualified reflection name.
    // String(reflecting:) returns "ModuleName.ParentType.Store" → drop "ModuleName."
    let fullName = String(reflecting: type)
    if let dotRange = fullName.range(of: ".") {
        return String(fullName[dotRange.upperBound...])
    }
    return fullName
}

func describeObject(_ object: Any, appending: String = "") -> String {
    var inoutObjects: [AnyObject] = []
    return describeObject(object, objects: &inoutObjects, appending: appending)
}

private func printCollection(
    _ mirrorChildren: Mirror.Children,
    _ objects: inout [AnyObject],
    _ appending: String
) -> String {
    "[" +
    .newLine +
    mirrorChildren.map { item in
        describeObject(item.value, objects: &objects)
    }
    .joined(separator: ",\n")
    .indentDumpedObject() +
    .newLine +
    "]" + appending
}

private func printDictionary(
    _ mirrorChildren: Mirror.Children,
    _ objects: inout [AnyObject],
    _ appending: String
) -> String {
    "[" +
    .newLine +
    mirrorChildren.map { item in
        if let (key, value) = item.value as? (Any, Any) {
            describeObject(key, objects: &objects) +
            ":" + .tab +
            describeObject(value, objects: &objects)
        } else {
            describeObject(item.value, objects: &objects)
        }
    }
    .joined(separator: ",\n")
    .indentDumpedObject() +
    .newLine +
    "]" + appending
}

private func printObject(
    _ object: Any,
    _ mirrorChildren: Mirror.Children,
    _ objects: inout [AnyObject],
    _ appending: String
) -> String {
    let childrenDescribed: [String] = mirrorChildren
        .compactMap { (child) in
            guard !(child.value is IsInjectedToMirror) else {
                return nil
            }
            guard let label = child.label else {
                // Be carefull calling describeObject here
                //  it creates an infinite recursion.
                // For example for [AnyCancellable]
                // Fixed in displayStyle .collection or .dictionary above
                return describeObject(child.value, objects: &objects)
            }
            let valueDescription: String
            if let fixedDescription = child.value as? WithFixedDebugDescription {
                valueDescription = fixedDescription.fixedDebugDescription
            } else if child.value is IsSubscopeToMirror {
                valueDescription = String(describing: child.value)
            } else if let anyEffect = child.value as? HasObjectToBeDescribedForMirror {
                valueDescription = describeObject(anyEffect.objectToBeDescribed, objects: &objects)
            } else {
                valueDescription = describeObject(child.value, objects: &objects)
            }
            return "\(label): \(valueDescription)".indentDumpedObject()
        }
    return "\(scopeTypeName(for: type(of: object)))(" +
        .newLine +
    childrenDescribed.joined(separator: .newLine) +
        .newLine +
    appending +
    ")"
}

private func describeObject(
    _ object: Any,
    objects: inout [AnyObject],
    appending: String = ""
) -> String {
    let mirror = Mirror(reflecting: object)
    let mirrorChildren = mirror.children
    if mirror.displayStyle == .class {
        let classObject = object as AnyObject
        guard nil == objects.firstIndex(where: { $0 === classObject }) else {
            return "‼️ infinite describeObject recursion avoided ‼️"
        }
        objects.append(classObject)
    }
    if mirror.displayStyle == .optional && mirror.children.isEmpty {
        return "nil" + appending
    } else if mirrorChildren.count == 0 {
        if object is Scope {
            return "\(scopeTypeName(for: type(of: object)))" + appending
        } else {
            return String(describing: object) + appending
        }
    } else if let anyEffect = object as? HasObjectToBeDescribedForMirror {
        return describeObject(anyEffect.objectToBeDescribed, objects: &objects, appending: appending)
    } else if mirror.displayStyle == .collection {
        return printCollection(mirrorChildren, &objects, appending)
    } else if mirror.displayStyle == .dictionary {
        return printDictionary(mirrorChildren, &objects, appending)
    } else if mirror.displayStyle == .enum,
              let firstChild = mirrorChildren.first {
        return "\(firstChild.label ?? "_"): \(describeObject(firstChild.value, objects: &objects))" + appending
    } else {
        return printObject(object, mirrorChildren, &objects, appending)
    }
}
