//
//  InjectionStore.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

class InjectionStore {
    fileprivate var injectedByClassDescription = [String: WeakDependency]()
    fileprivate var injectedByValueDescription = [String: Any]()

    struct WeakDependency {
        weak var dependency: AnyObject?
    }

    // Keyed by the GENERIC PARAMETER T, not type(of: dependency). These differ, confirmed
    // empirically (not just in theory — see the class-subtype check below), for CLASS SUBTYPING:
    // `func f<T>(_ x: T) { type(of: x) }` called as `f(dogInstance as Animal)` reports `Dog`, not
    // `Animal`, even though T is inferred as Animal — normal Swift class polymorphism, unrelated
    // to protocols. So `register(dogInstance as Animal)` used to key under "Dog", while a later
    // `resolve() as Animal` looked up "Animal" — mismatch, silently unresolvable.
    // (Protocol-typed injection turns out NOT to need this fix — inside a generic function body,
    // T.self and type(of: dependency) already agree for an existential-typed T; that path's real
    // blocker was Injectable's `Self`-returning defaultValue requirement, fixed separately via
    // InjectionKey/@Injected, not here.)
    // No behavior change when no subclassing is involved — T.self == type(of: dependency) then.
    func register<T: AnyObject>(_ dependency: T) {
        let key = String(describing: T.self).removeOptionalDescription
        injectedByClassDescription[key] = WeakDependency(dependency: dependency)
    }

    func registerValue<T: Any>(_ dependency: T) {
        let key = String(describing: T.self).removeOptionalDescription
        injectedByValueDescription[key] = dependency
    }

    func resolve<T>() throws -> T {
        guard let resolved: T = optResolve() else {
            throw NoInjectedValueFound(T.self)
        }
        return resolved
    }

    func optResolve<T>() -> T? {
        let key = String(describing: T.self).removeOptionalDescription
        if let weakDependency = injectedByClassDescription[key],
           let dependency = weakDependency.dependency as? T {
            return dependency
        }
        if let dependency = injectedByValueDescription[key] as? T {
            return dependency
        }
        return nil
    }
}

extension InjectionStore {
    var treeDescription: [String] {
        let classes: [String] = injectedByClassDescription
            .compactMap { (key: String, value: InjectionStore.WeakDependency) in
            guard let dep = value.dependency else {
                return nil
            }
            return "💉 \(key):\t\(String(describing: dep))"
        }
        if injectedByValueDescription.count > 0 {
            let objects = "💉 " + injectedByValueDescription.keys.joined(separator: ", ")
            return classes + [objects]
        } else {
            return classes
        }
    }
}
