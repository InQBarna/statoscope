//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

public protocol ChainLinkProtocol {
    var parentAssigned: Bool { get }
    var exprParent: AnyWeakChainLink? { get }
    func assignChild<Value: ChainLinkProtocol>(_: Value?)
}

public protocol ChainLink: ChainLinkProtocol, AnyObject { }

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

final class WeakChainLink<D: ChainLink>: AnyWeakChainLink {
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

fileprivate var injectionStoreKey: UInt8 = 43
fileprivate var parentStoreKey: UInt8 = 43
fileprivate var childrenStoreKey: UInt8 = 43
extension ChainLink {
    fileprivate var children: NSMutableArray { // [AnyWeakTreeNode] {
        get {
            return associatedObject(base: self, key: &childrenStoreKey, initialiser: { [] })
        }
    }
    fileprivate var parent: AnyWeakChainLink? {
        get {
            return optionalAssociatedObject(base: self, key: &parentStoreKey, initialiser: { AnyWeakChainLink(nil) })
        }
    }
    var injectionStore: InjectionStore {
        get {
            return associatedObject(base: self, key: &injectionStoreKey, initialiser: { InjectionStore() })
        }
    }
    @discardableResult
    func injectSuperscope<T: AnyObject>(_ obj: T) -> Self {
        injectionStore.registerValue(obj)
        return self
    }
    @discardableResult
    func injectObject<T>(_ obj: T) -> Self {
        injectionStore.registerValue(obj)
        return self
    }
    // remote fileprivate and expose for easier rootable implementation
    fileprivate func resolve<T>() throws -> T {
        try injectionStore.resolve()
    }

    // Implementing ChainLinkProtocol
    var exprParent: AnyWeakChainLink? { parent }
    var parentAssigned: Bool { parent?.anyLink != nil }
    func assignChild<Value>(_ child: Value?) where Value : ChainLinkProtocol {
        if let newInjTreeNode = child {
            if !children.contains(newInjTreeNode) {
                children.add(AnyWeakChainLink(expr: newInjTreeNode))
            }
            newInjTreeNode.exprParent?.anyLink = self
        }
    }
}

// ChainLink Maintenance and log
extension ChainLink {
    func cleanupChildren() {
        let allChildren = children
            .map { $0 as! AnyWeakChainLink }
        allChildren.forEach { child in
            child.anyLink?.cleanupChildren()
        }
        let discardable = allChildren
            .filter { $0.anyLink == nil }
        children.removeObjects(in: discardable)
    }
    fileprivate var treeDescription: [String] {
        [
            [
                "NODE: <\(Unmanaged.passUnretained(self).toOpaque()): \(self)>"
                //String(describing: self).removeOptionalDescription,
            ],
            injectionStore.treeDescription.map { "  " + $0 }
        ]
            .flatMap { $0 }
    }
    var root: ChainLink {
        var node: ChainLink = self
        while let parent = node.parent?.anyLink {
            node = parent
        }
        return node
    }
    func printRootTree(whitespaces: Int = 0) {
        getPrintRootTree().forEach {
            print($0)
        }
    }
    func getPrintRootTree(whitespaces: Int = 0) -> [String] {
        root.getPrintTree(whitespaces: whitespaces)
    }
    func printTree(whitespaces: Int = 0) {
        getPrintTree().forEach {
            print($0)
        }
    }
    func getPrintTree(whitespaces: Int = 0) -> [String] {
        let whitespacesString = (0...whitespaces).map { _ in " " }.joined()
        let selfAndDepsDescription = treeDescription
            .map { whitespacesString + $0 }
            .joined(separator: "\n")
        print("\(selfAndDepsDescription)")
        return children
            .map { child -> [String] in
                guard let treeNode = child as? AnyWeakChainLink  else {
                    return []
                }
                return treeNode.anyLink?.getPrintTree(whitespaces: whitespaces + 4) ?? []
            }
            .flatMap {
                $0
            }
    }
}

extension ChainLink {
    func resolveSuperscope<T: Injectable>(searchInStore: Bool = false) throws -> T {
        var node: ChainLink? = self
        while let nonNilNode = node {
            node = nonNilNode.parent?.anyLink
            if let found = nonNilNode as? T {
                return found
            }
            if searchInStore,
               let inStoreFound: T = nonNilNode.injectionStore.optResolve() {
                return inStoreFound
            }
        }
        print("No injected value found \(String(describing: T.self).removeOptionalDescription)")
        print("\(self.getPrintRootTree())")
        throw NoInjectedValueFound(T.self)
        // return T.defaultValue
    }
    
    func resolveObject<T: Injectable>() throws -> T {
        var node: ChainLink? = self
        while let iterator = node {
            node = iterator.parent?.anyLink
            if let inStoreFound: T = iterator.injectionStore.optResolve() {
                return inStoreFound
            }
        }
        print("No injected value found \(String(describing: T.self).removeOptionalDescription)")
        print("\(self.getPrintRootTree())")
        throw NoInjectedValueFound(T.self)
    }
}

extension ChainLinkProtocol {
    var exprParent: AnyWeakChainLink? {
        fatalError("Don't try implementing ExpressibleAsInjectionTreeNode, " +
                   " this is an internal helper for optional-nonoptional property wrapping")
    }
    func assignChild<Value: ChainLinkProtocol>(_: Value?) {
        fatalError("Don't try implementing ExpressibleAsInjectionTreeNode, " +
                   " this is an internal helper for optional-nonoptional property wrapping")
    }
    var parentAssigned: Bool {
        fatalError("Don't try implementing ExpressibleAsInjectionTreeNode, " +
                   " this is an internal helper for optional-nonoptional property wrapping")
    }
}

extension Optional: ChainLinkProtocol where Wrapped: ChainLink {
    public func assignChild<Value>(_ child: Value?) where Value : ChainLinkProtocol {
        if let newInjTreeNode = child {
            if !(self?.children.contains(newInjTreeNode) ?? false) {
                // self?.children.add(WeakTreeNode(newInjTreeNode))
                self?.children.add(AnyWeakChainLink(expr: newInjTreeNode))
            }
            newInjTreeNode.exprParent?.anyLink = self
        }
    }
    public var exprParent: AnyWeakChainLink? {
        return self?.parent
    }
    public var parentAssigned: Bool {
        switch self {
        case .none: return true
        case .some(let chainLink): return chainLink.exprParent?.anyLink != nil
        }
    }
}
