//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Artifact protocol to make both mandatory and optional subscopes conform to same protocol and be enabled in Subscope property wrapper
public protocol ChainLinkProtocol {
    var parentAssigned: Bool { get }
    var chainParent: AnyWeakChainLink? { get }
    func assignChildOnPropertyWrapperGet<Value: ChainLinkProtocol>(_: Value?)
    func assignChildOnPropertyWrapperSet<Value: ChainLinkProtocol>(_: Value?)
}

/// Represents a node in a tree of dependencies search
///
/// Helper to achieve dependency injection and retrieval by holding a list of children nodes and a link to the parent
/// when a dependency is requested to a node, it can be searched up to the root of the tree
public protocol ChainLink: ChainLinkProtocol, AnyObject {
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
    
    func assignChildOnPropertyWrapperGet<Value: ChainLinkProtocol>(_ value: Value?) {
        if value?.parentAssigned ?? false {
            return
        }
        assignChildAndCleanupChain(value)
    }
    
    func assignChildOnPropertyWrapperSet<Value: ChainLinkProtocol>(_ value: Value?) {
        assignChildAndCleanupChain(value)
    }
    
    // Must be added as public extension
    var chainParent: AnyWeakChainLink? { weakParent }
    
    // Must be added as public extension
    var parentAssigned: Bool { weakParent?.anyLink != nil }
}

// Objc runtime associated object keys
fileprivate var injectionStoreKey: UInt8 = 0
fileprivate var parentStoreKey: UInt8 = 0
fileprivate var childrenStoreKey: UInt8 = 0

fileprivate extension ChainLink {
    var children: NSMutableArray { // [AnyWeakTreeNode] {
        get {
            return associatedObject(base: self, key: &childrenStoreKey, initialiser: { [] })
        }
    }
    var weakParent: AnyWeakChainLink? {
        get {
            return optionalAssociatedObject(base: self, key: &parentStoreKey, initialiser: { AnyWeakChainLink(nil) })
        }
    }
    var injectionStore: InjectionStore {
        get {
            return associatedObject(base: self, key: &injectionStoreKey, initialiser: { InjectionStore() })
        }
    }
    
    func resolve<T>() throws -> T {
        try injectionStore.resolve()
    }
}

// ChainLink Maintenance and log
extension ChainLink {
    
    func assignChildAndCleanupChain<Value: ChainLinkProtocol>(_ newValue: Value?) {

        assignChild(newValue)
        cleanupChildren()
        
        // Debug
        // enclosingInstance.root.printRootTree()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak root = root] in
            root?.cleanupChildren()
            // root?.printRootTree()
        }
    }

    func assignChild<Value>(_ child: Value?) where Value : ChainLinkProtocol {
        if let newInjTreeNode = child {
            if !children.contains(newInjTreeNode) {
                children.add(AnyWeakChainLink(expr: newInjTreeNode))
            }
            newInjTreeNode.chainParent?.anyLink = self
        }
    }

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

    var treeDescription: [String] {
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
    func assignChildNode<Value: ChainLinkProtocol>(_: Value?) {
        fatalError("Don't try implementing ChainLinkProtocol, " +
                   " this is an internal helper for optional-nonoptional property wrapping")
    }
    var parentAssigned: Bool {
        fatalError("Don't try implementing ChainLinkProtocol, " +
                   " this is an internal helper for optional-nonoptional property wrapping")
    }
}

extension Optional: ChainLinkProtocol where Wrapped: ChainLink {
    
    public func assignChildOnPropertyWrapperGet<Value: ChainLinkProtocol>(_ value: Value?) {
        self?.assignChildOnPropertyWrapperGet(value)
    }
    
    public func assignChildOnPropertyWrapperSet<Value: ChainLinkProtocol>(_ value: Value?) {
        self?.assignChildOnPropertyWrapperSet(value)
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
