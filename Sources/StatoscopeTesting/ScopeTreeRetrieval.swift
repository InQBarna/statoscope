//
//  File 2.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation
import Statoscope

internal func ifChildScope(
    _ mirrorChild: Mirror.Child,
    except: [any Scope],
    _ block: ((_ child: any Scope, _ name: String, _ newExcept: [any Scope]) -> Void)
) {
    guard let label = mirrorChild.label else {
        return
    }
    if let scopeChild = mirrorChild.value as? any Scope {
        if nil == except.first(where: { $0 === scopeChild}) {
            var exceptWithChild = except
            exceptWithChild.append(scopeChild)
            block(scopeChild, label, exceptWithChild)
            return
        }
    }
    if String(describing: mirrorChild.value).contains("Subscope<") {
        if let publishedScopeChild = Mirror(reflecting: mirrorChild.value).children.first as? (String, any Scope) {
            if nil == except.first(where: { $0 === publishedScopeChild.1}) {
                var exceptWithChild = except
                exceptWithChild.append(publishedScopeChild.1)
                block(publishedScopeChild.1, label, exceptWithChild)
            }
        }
    }
}

extension Scope {
    
    public func allChildScopes() -> [any Scope] {
        var scopes: [any Scope] = [self]
        allChildScopeIterative(except: &scopes)
        return scopes
    }

    private func allChildScopeIterative(except: inout [any Scope]) {
        let mirror = Mirror(reflecting: self)
        mirror.children.forEach { child in
            ifChildScope(child, except: except) { child, _, newExcept in
                except = newExcept
                child.allChildScopeIterative(except: &except)
            }
        }
    }
    
}
