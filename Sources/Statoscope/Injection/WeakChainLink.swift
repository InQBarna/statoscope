//
//  InjectionTreeNodeBox.swift
//
//
//  Created by Sergi Hernanz on 1/2/24.
//

import Foundation

class InjectionTreeNodeBox {
    weak var anyLink: InjectionTreeNode?
    init(_ anyLink: InjectionTreeNode? = nil) {
        self.anyLink = anyLink
    }
    init(expr: InjectionTreeNodeProtocol? = nil) {
        anyLink = Self.map(expr: expr)
    }
    
    static func map(expr: InjectionTreeNodeProtocol? = nil) -> InjectionTreeNode? {
        if let mandatory = expr as? InjectionTreeNode {
            // Class type
            return mandatory
        } else if let optTreeNode = expr as? InjectionTreeNode? {
            // Optional type
            return optTreeNode
        } else {
            // assert(expr == nil, "assigning type \(String(describing: expr)) not known")
            return nil
        }
    }
}

extension InjectionTreeNodeBox: Equatable {
    public static func == (lhs: InjectionTreeNodeBox, rhs: InjectionTreeNodeBox) -> Bool {
        lhs.anyLink === rhs.anyLink
    }
}

extension InjectionTreeNodeBox: InjectionTreeNodeProtocol {

    var childrenNodes: [InjectionTreeNodeProtocol] {
        anyLink?.childrenNodes ?? []
    }
    
    var rootNode: InjectionTreeNodeProtocol? {
        anyLink?.rootNode
    }
}

/*
fileprivate final class WeakChainLink<D: ChainLink>: AnyWeakChainLink, ChainLinkProtocol {
    var chainParent: ChainLinkProtocol? {
        get {
            link?.chainParent
        }
        set {
            link?.chainParent = newValue
        }
    }
    
    init(_ link: D) {
        super.init(link)
    }
    static func == (lhs: WeakChainLink, rhs: WeakChainLink) -> Bool {
        lhs.link === rhs.link
    }
    var link: D? {
        get {
            anyLink as? D
        }
        set {
            anyLink = newValue
        }
    }
}
*/
