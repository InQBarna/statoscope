//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

public protocol ChainLinkProtocol { 
    var parentAssigned: Bool { get }
    var chainParent: AnyWeakChainLink? { get }
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

// Objc runtime associated object keys
fileprivate var injectionStoreKey: UInt8 = 0
fileprivate var parentStoreKey: UInt8 = 0
fileprivate var childrenStoreKey: UInt8 = 0

extension ChainLink {
    fileprivate var children: NSMutableArray { // [AnyWeakTreeNode] {
        get {
            return associatedObject(base: self, key: &childrenStoreKey, initialiser: { [] })
        }
    }
    fileprivate var weakParent: AnyWeakChainLink? {
        get {
            return optionalAssociatedObject(base: self, key: &parentStoreKey, initialiser: { AnyWeakChainLink(nil) })
        }
    }
    var injectionStore: InjectionStore {
        get {
            return associatedObject(base: self, key: &injectionStoreKey, initialiser: { InjectionStore() })
        }
    }
    
    fileprivate func resolve<T>() throws -> T {
        try injectionStore.resolve()
    }
}

public extension ChainLink {
    
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

    var chainParent: AnyWeakChainLink? { weakParent }
    var parentAssigned: Bool { weakParent?.anyLink != nil }
    func assignChild<Value>(_ child: Value?) where Value : ChainLinkProtocol {
        if let newInjTreeNode = child {
            if !children.contains(newInjTreeNode) {
                children.add(AnyWeakChainLink(expr: newInjTreeNode))
            }
            newInjTreeNode.chainParent?.anyLink = self
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
        while let weakParentLink = node.weakParent?.anyLink {
            node = weakParentLink
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
        let childTree = children
            .map { child -> [String] in
                guard let treeNode = child as? AnyWeakChainLink  else {
                    return []
                }
                return treeNode.anyLink?.getPrintTree(whitespaces: whitespaces + 4) ?? []
            }
            .flatMap {
                $0
            }
        return [[selfAndDepsDescription], childTree].flatMap { $0 }
    }
}

extension ChainLink {
    func resolveSuperscope<T: Injectable>(searchInStore: Bool = false) throws -> T {
        var node: ChainLink? = self
        while let nonNilNode = node {
            node = nonNilNode.weakParent?.anyLink
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
    
    func resolveObject<T: Injectable>(keyPath: String?) throws -> T {
        var node: ChainLink? = self
        while let iterator = node {
            node = iterator.weakParent?.anyLink
            if let inStoreFound: T = iterator.injectionStore.optResolve() {
                return inStoreFound
            }
        }
        print("No injected value found: \"\(String(describing: T.self).removeOptionalDescription)\" at: \"\(keyPath ?? String(describing: type(of: self)))\"")
        self.getPrintRootTree().forEach {
            print("\($0)")
        }
        throw NoInjectedValueFound(T.self)
    }
}

public extension ChainLinkProtocol {
    var chainParent: AnyWeakChainLink? {
        fatalError("Don't try implementing ChainLinkProtocol, " +
                   " this is an internal helper for optional-nonoptional property wrapping")
    }
    func assignChild<Value: ChainLinkProtocol>(_: Value?) {
        fatalError("Don't try implementing ChainLinkProtocol, " +
                   " this is an internal helper for optional-nonoptional property wrapping")
    }
    var parentAssigned: Bool {
        fatalError("Don't try implementing ChainLinkProtocol, " +
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
            newInjTreeNode.chainParent?.anyLink = self
        }
    }
    public var chainParent: AnyWeakChainLink? {
        return self?.weakParent
    }
    public var parentAssigned: Bool {
        switch self {
        case .none: return true
        case .some(let chainLink): return chainLink.chainParent?.anyLink != nil
        }
    }
}
