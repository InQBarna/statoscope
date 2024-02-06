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
    except: [any StoreProtocol],
    _ block: ((_ child: any StoreProtocol, _ name: String, _ newExcept: [any StoreProtocol]) -> Void)
) {
    guard let label = mirrorChild.label else {
        return
    }
    if let scopeChild = mirrorChild.value as? any StoreProtocol {
        if nil == except.first(where: { $0.state === scopeChild.state}) {
            var exceptWithChild = except
            exceptWithChild.append(scopeChild)
            block(scopeChild, label, exceptWithChild)
            return
        }
    }
    if String(describing: mirrorChild.value).contains("Subscope<") {
        if let publishedScopeChild = Mirror(reflecting: mirrorChild.value).children.first as? (String, any StoreProtocol) {
            if nil == except.first(where: { $0.state === publishedScopeChild.1.state}) {
                var exceptWithChild = except
                exceptWithChild.append(publishedScopeChild.1)
                block(publishedScopeChild.1, label, exceptWithChild)
            }
        }
    }
}

extension StoreProtocol {
    
    public func allChildScopes() -> [any StoreProtocol] {
        var scopes: [any StoreProtocol] = [self]
        allChildScopeIterative(except: &scopes)
        return scopes
    }

    private func allChildScopeIterative(except: inout [any StoreProtocol]) {
        let mirror = Mirror(reflecting: self)
        mirror.children.forEach { child in
            ifChildScope(child, except: except) { child, _, newExcept in
                except = newExcept
                child.allChildScopeIterative(except: &except)
            }
        }
    }
    
}
