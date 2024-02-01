//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 1/2/24.
//

import Foundation

public class AnyWeakChainLink {
    weak var anyLink: ChainLink?
    init(_ anyLink: ChainLink? = nil) {
        self.anyLink = anyLink
    }
    init(expr: ChainLinkProtocol? = nil) {
        if let mandatory = expr as? ChainLink {
            self.anyLink = mandatory
        } else if let optTreeNode = expr as? ChainLink? {
            self.anyLink = optTreeNode
        } else {
            // assert(expr == nil, "assigning type \(String(describing: expr)) not known")
            self.anyLink = nil
        }
    }
}

extension AnyWeakChainLink: Equatable {
    public static func == (lhs: AnyWeakChainLink, rhs: AnyWeakChainLink) -> Bool {
        lhs.anyLink === rhs.anyLink
    }
}

fileprivate final class WeakChainLink<D: ChainLink>: AnyWeakChainLink {
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
