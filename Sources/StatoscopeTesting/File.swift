//
//  StateScopeLibraryTests.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import Statoscope

func ifChildScope(_ mirrorChild: Mirror.Child,
                  except: [ScopeProtocol],
                  _ block: ((_ child: ScopeProtocol, _ name: String, _ newExcept: [ScopeProtocol]) -> Void)) {
    guard let label = mirrorChild.label else {
        return
    }
    if let scopeChild = mirrorChild.value as? ScopeProtocol {
        if nil == except.first(where: { $0 === scopeChild}) {
            var exceptWithChild = except
            exceptWithChild.append(scopeChild)
            block(scopeChild, label, exceptWithChild)
        }
    }
    if String(describing: mirrorChild.value).contains("Subscope<") {
        if let publishedScopeChild = Mirror(reflecting: mirrorChild.value).children.first as? (String, ScopeProtocol) {
            if nil == except.first(where: { $0 === publishedScopeChild.1}) {
                var exceptWithChild = except
                exceptWithChild.append(publishedScopeChild.1)
                block(publishedScopeChild.1, label, exceptWithChild)
            }
        }
    }
}

extension ScopeProtocol {
    
    func allDeepPendingEffects() -> [String: [Any]] {
        var foundEffects = [String: [Any]]()
        pendingEffectsIterative(except: [self], foundEffects: &foundEffects)
        return foundEffects
    }
    private func pendingEffectsIterative(except: [ScopeProtocol], foundEffects: inout [String: [Any]]) {
        let mirror = Mirror(reflecting: self)
        mirror.children.forEach { child in
            ifChildScope(child, except: except) { child, _, newExcept in
                let scopeName = "\(child)"
                var existing = foundEffects[scopeName] ?? [Any]()
                existing.append(contentsOf: child.erasedEffects)
                foundEffects[scopeName] = existing
                child.pendingEffectsIterative(except: newExcept, foundEffects: &foundEffects)
            }
        }
    }
    
    func clearAllDeepPendingEffects() {
        clearAllDeepPendingEffectsIterative(except: [self])
    }
    private func clearAllDeepPendingEffectsIterative(except: [ScopeProtocol]) {
        let mirror = Mirror(reflecting: self)
        mirror.children.forEach { child in
            ifChildScope(child, except: except) { child, _, newExcept in
                child.clearEffects()
                child.clearAllDeepPendingEffectsIterative(except: newExcept)
            }
        }
    }
}

struct WeakScopeBox {
    weak var scope: ScopeProtocol?
}

extension ScopeProtocol {
    
    func allChildScopes() -> [ScopeProtocol] {
        var scopes: [ScopeProtocol] = [self]
        allChildScopeIterative(except: &scopes)
        return scopes
    }
    private func allChildScopeIterative(except: inout [ScopeProtocol]) {
        let mirror = Mirror(reflecting: self)
        mirror.children.forEach { child in
            ifChildScope(child, except: except) { child, _, newExcept in
                var except = newExcept
                allChildScopeIterative(except: &except)
            }
        }
    }
    func allChildScopesChecker() -> [WeakScopeBox] {
        allChildScopes().map { WeakScopeBox(scope: $0) }
    }
}

extension ScopeProtocol {
    @discardableResult
    func findChild<Subscope: Statoscope>(keyPath: [String],
                                         searchingChild: Subscope) -> ([String], Subscope)? {
        return findChildIterative(keyPath: keyPath, searchingChild: searchingChild, except: [self])
    }
    private func findChildIterative<Subscope: Statoscope>(keyPath: [String],
                                                            searchingChild: Subscope,
                                                            except: [ScopeProtocol]) -> ([String], Subscope)? {
        let mirror = Mirror(reflecting: self)
        var found: ([String], Subscope)? = nil
        mirror.children.forEach { child in
            ifChildScope(child, except: except) { child, name, newExcept in
                let newKeyPath = [keyPath, [name]].flatMap { $0 }
                if let childScope = child as? Subscope, searchingChild === child {
                    found = (newKeyPath, childScope)
                }
                guard found == nil else {
                    return
                }
                found = child.findChildIterative(keyPath: newKeyPath, searchingChild: searchingChild, except: newExcept)
            }
        }
        return found
    }
}
