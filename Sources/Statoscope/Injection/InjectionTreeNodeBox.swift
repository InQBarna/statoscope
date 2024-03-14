//
//  InjectionTreeNodeBox.swift
//
//
//  Created by Sergi Hernanz on 1/2/24.
//

import Foundation

class InjectionTreeNodeBox {
    weak var anyLink: InjectionTreeNode?
    var parentKeyPath: AnyKeyPath?
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
    static func == (lhs: InjectionTreeNodeBox, rhs: InjectionTreeNodeBox) -> Bool {
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
