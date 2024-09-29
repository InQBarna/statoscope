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
    except: [any ScopeImplementation],
    _ block: ((_ child: any ScopeImplementation, _ name: String, _ newExcept: [any ScopeImplementation]) -> Void)
) {
    guard let label = mirrorChild.label else {
        return
    }
    if let scopeChild = mirrorChild.value as? any ScopeImplementation {
        if nil == except.first(where: { $0 === scopeChild}) {
            var exceptWithChild = except
            exceptWithChild.append(scopeChild)
            block(scopeChild, label, exceptWithChild)
            return
        }
    }
    if mirrorChild.value is IsSubscopeToMirror {
        if let publishedScopeChild = Mirror(reflecting: mirrorChild.value)
            .children.first as? (String, any ScopeImplementation) {
            if nil == except.first(where: { $0 === publishedScopeChild.1}) {
                var exceptWithChild = except
                exceptWithChild.append(publishedScopeChild.1)
                block(publishedScopeChild.1, label, exceptWithChild)
            }
        }
    }
}

extension ScopeImplementation {

    public func _allChildScopes() -> [any ScopeImplementation] {
        var scopes: [any ScopeImplementation] = [self]
        allChildScopeIterative(except: &scopes)
        return scopes
    }

    private func allChildScopeIterative(except: inout [any ScopeImplementation]) {
        let mirror = Mirror(reflecting: self)
        mirror.children.forEach { child in
            ifChildScope(child, except: except) { child, _, newExcept in
                except = newExcept
                child.allChildScopeIterative(except: &except)
            }
        }
    }

}
