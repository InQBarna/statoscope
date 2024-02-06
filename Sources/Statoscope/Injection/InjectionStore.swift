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

    struct WeakDependency: Hashable {
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.dependency === rhs.dependency
        }
        weak var dependency: AnyObject?
        func hash(into hasher: inout Hasher) {
            if let dependency = dependency {
                hasher.combine(ObjectIdentifier(dependency))
            }
        }
    }

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

    func copy(into: InjectionStore) {
        into.injectedByClassDescription.merge(injectedByClassDescription) { lhs, _ in lhs }
    }
}

extension InjectionStore {
    var treeDescription: [String] {
        let classes: [String] = injectedByClassDescription
            .compactMap { (key: String, value: InjectionStore.WeakDependency) in
            guard let dep = value.dependency else {
                return nil
            }
            return "+ \(key):\t\(dep)"
        }
        if injectedByValueDescription.count > 0 {
            let objects = "+++ " + injectedByValueDescription.keys.joined(separator: ", ")
            return classes + [objects]
        } else {
            return classes
        }
    }
}
