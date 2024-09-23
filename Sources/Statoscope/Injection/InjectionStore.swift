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

    func register<T: AnyObject>(_ dependency: T) {
        let key = "\(type(of: dependency))".removeOptionalDescription
        injectedByClassDescription[key] = WeakDependency(dependency: dependency)
    }

    func registerValue<T: Any>(_ dependency: T) {
        let key = "\(type(of: dependency))".removeOptionalDescription
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
