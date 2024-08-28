//
//  InjectionTreeNode.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Artifact protocol, please refer to ``InjectionTreeNode`` for features
///  This protocol simply enables both InjectionTreeNode and InjectionTreeNode? 
///  struct to conform to the same protocol and be used in the Subscope property wrapper
public protocol InjectionTreeNodeProtocol {
    /// Returns the ancestor in the injection tree node
    var parentNode: InjectionTreeNodeProtocol? { get set }
    // TODO: parentKeyPath and parentNode to be merged into a single property ?
    /// Returns the ancestor keyPath to the current node
    var keyPathToSelfOnParent: AnyKeyPath? { get set }
    /// Returns the descendants in the injection tree node
    var childrenNodes: [InjectionTreeNodeProtocol] { get }
    /// Returns the root ancestor of the inection tree node
    var rootNode: InjectionTreeNodeProtocol? { get }
}

/// Represents a node in a tree of dependencies search to achieve a dependency 
/// injection similar to what environmentObject achieves in swiftUI
///
/// By conforming to this protocol, your class object automatically synthesizes
/// * An injection store to hold ad-hoc injected values
/// * Parent + children properties to connect to a dependency tree, enabled when using the ``Subscope`` property wrapper
/// ### Ad-hoc injections
/// Inject an object into a Tree node by calling injectObject. Please note the object is retained.
/// ```swift
/// let node: YourScope = ...
/// node.injectObject(InjectedClock(currentDate: { Date(timeIntervalSinceReferenceDate: 0) }))
/// ```
/// Later you can resolve the object either by calling
/// ```swift
/// final class YourScope: Statostore {
///   func update(_ when: When) throws {
///      let clock: InjectedClock = self.resolve()
///      print("current time: \(clock.currentTime)")
///   }
/// }
/// ```
/// or using the Injected property wrapper
/// ```swift
/// final class YourScope: Statostore {
///   @Injected var clock: InjectedClock
///   func update(_ when: When) throws {
///      print("current time: \(clock.currentTime)")
///   }
/// }
/// ```
/// ### Superscope injections
/// When another scope is inside your superscopes tree, an automatic injection occurs. Please see the example:
/// ```swift
/// final class YourScope: Statostore {
///   let name: String
///   @Subscope var childScope: YourChildScope?
/// }
/// final class YourChildScope: Statostore {
/// }
/// ```
/// Superscope can be retrieved either by calling
/// ```swift
/// final class YourChildScope: Statostore {
///   func update(_ when: When) throws {
///      let superscope: YourScope = self.resolve()
///      print("Name: \(superscope.name)")
///   }
/// }
/// ```
/// or using the Injected property wrapper
/// ```swift
/// final class YourChildScope: Statostore {
///   @Superscope var superscope: YourScope
///   func update(_ when: When) throws {
///      print("Name: \(superscope.name)")
///   }
/// }
/// ```
public protocol InjectionTreeNode: InjectionTreeNodeProtocol, AnyObject {
    @discardableResult func injectObject<T>(_ obj: T) -> Self
    /// Searches and returns the requested type inside the injection store or up to the injection tree
    ///
    /// Method will search first in ad-hoc injected objects and later up in the injection tree.
    /// * Returns The found injected value or default value if not found
    func resolve<T: Injectable>() -> T
    /// Searches and returns the requested type inside the injection store or up to the injection tree
    ///
    /// Method will search first in ad-hoc injected objects and later up in the injection tree.
    /// * Returns The found injected value or throws ``NoInjectedValueFound`` if not found
    func resolveUnsafe<T>() throws -> T
}

public extension InjectionTreeNode {

    var parentNode: InjectionTreeNodeProtocol? {
        get {
            weakParent?.anyLink
        }
        set {
            weakParent?.anyLink = InjectionTreeNodeBox.map(expr: newValue)
        }
    }

    var keyPathToSelfOnParent: AnyKeyPath? {
        get {
            weakParent?.keyPathToSelfOnParent
        }
        set {
            // parentNode and parentKeyPath needs a refactor so they are assigned alltogether
            //  in the meantime... assert correct usage
            assert(newValue == nil || weakParent != nil)
            weakParent?.keyPathToSelfOnParent = newValue
        }
    }

    @discardableResult
    func injectObject<T>(_ obj: T) -> Self {
        injectionStore.registerValue(obj)
        return self
    }

    func resolve<T: Injectable>() -> T {
        do {
            return try resolveUnsafe()
        } catch {
            return T.defaultValue
        }
    }

    func resolveUnsafe<T>() throws -> T {
        var node: InjectionTreeNode? = self
        while let iterator = node {
            node = iterator.weakParent?.anyLink
            if let foundInStore: T = iterator.injectionStore.optResolve() {
                return foundInStore
            }
            if let foundInAncestor = iterator as? T {
                return foundInAncestor
            }
        }
        throw NoInjectedValueFound(T.self, injectionTreeDescription: self.rootTreeDescription())
    }

    var rootNode: InjectionTreeNodeProtocol? {
        root
    }

    var childrenNodes: [InjectionTreeNodeProtocol] {
        children
            .map {
                // swiftlint:disable:next force_cast
                $0 as! InjectionTreeNodeBox
            }
    }
}

extension InjectionTreeNode {

    @discardableResult
    public func injectSuperscopeForTesting<T: AnyObject>(_ obj: T) -> Self {
        injectionStore.registerValue(obj)
        return self
    }

}

// Objc runtime associated object keys
private var injectionStoreKey: UInt8 = 0
private var parentStoreKey: UInt8 = 0
private var childrenStoreKey: UInt8 = 0

fileprivate extension InjectionTreeNode {
    var children: NSMutableArray { // [AnyWeakTreeNode] {
        return associatedObject(base: self, key: &childrenStoreKey, initialiser: { [] })
    }
    var weakParent: InjectionTreeNodeBox? {
        return optionalAssociatedObject(base: self, key: &parentStoreKey, initialiser: { InjectionTreeNodeBox(nil) })
    }
    var injectionStore: InjectionStore {
        return associatedObject(base: self, key: &injectionStoreKey, initialiser: { InjectionStore() })
    }
}

// Tree maintenance
extension InjectionTreeNode {

    var root: InjectionTreeNode {
        var node: InjectionTreeNode = self
        while let weakParentLink = node.weakParent?.anyLink {
            node = weakParentLink
        }
        return node
    }

    var selfRootKeyPath: AnyKeyPath {
        guard var node: InjectionTreeNode = weakParent?.anyLink,
              let keyPathToSelfOnParent else {
            return \Self.self
        }

        var keyPath: AnyKeyPath = keyPathToSelfOnParent
        while let weakParent = node.weakParent,
              let weakParentLink = weakParent.anyLink {
            node = weakParentLink
            if let appendableKP = weakParent.keyPathToSelfOnParent,
               let newLKeyPath = appendableKP.appending(path: keyPath) {
                keyPath = newLKeyPath
            }
        }
        return keyPath
    }

    func assignChildOnPropertyWrapperGet<Value: InjectionTreeNodeProtocol>(_ value: Value?, keyPath: AnyKeyPath) {
        if value?.parentNode != nil {
            return
        }
        assignChildAndCleanupChain(value, keyPath: keyPath)
    }

    func assignChildOnPropertyWrapperSet<Value: InjectionTreeNodeProtocol>(_ value: Value?, keyPath: AnyKeyPath) {
        assignChildAndCleanupChain(value, keyPath: keyPath)
    }

    fileprivate func assignChildAndCleanupChain<Value: InjectionTreeNodeProtocol>(
        _ newValue: Value?,
        keyPath: AnyKeyPath
    ) {
        assignChild(newValue, keyPath: keyPath)
        cleanupChildren()
        // Debug
        // enclosingInstance.root.printRootTree()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak root = root] in
            root?.cleanupChildren()
            // root?.printRootTree()
        }
    }

    fileprivate func assignChild<Value: InjectionTreeNodeProtocol>(_ child: Value?, keyPath: AnyKeyPath) {
        if var newInjTreeNode = child {
            if !children.contains(newInjTreeNode) {
                children.add(InjectionTreeNodeBox(expr: newInjTreeNode))
            }
            newInjTreeNode.parentNode = self
            newInjTreeNode.keyPathToSelfOnParent = keyPath
        }
    }

    fileprivate func cleanupChildren() {
        let allChildren = children
            .map {
                // swiftlint:disable:next force_cast
                $0 as! InjectionTreeNodeBox
            }
        allChildren.forEach { child in
            child.anyLink?.cleanupChildren()
        }
        let discardable = allChildren
            .filter { $0.anyLink == nil }
        children.removeObjects(in: discardable)
    }
}

// Debugging
extension InjectionTreeNode {

    public var injectedTreeDescription: String {
        injectedTree
            .joined(separator: "\n")
    }

    public var injectedTree: [String] {
        [
            [
                "NODE: <\(Unmanaged.passUnretained(self).toOpaque()): \(type(of: self))>"
                // String(describing: self).removeOptionalDescription,
            ],
            injectionStore.treeDescription.map { "  " + $0 }
        ]
            .flatMap { $0 }
    }

    func rootTreeDescription(whitespaces: Int = 0) -> [String] {
        root.treeDescription(whitespaces: whitespaces)
    }

    func treeDescription(whitespaces: Int = 0) -> [String] {
        let whitespacesString = (0...whitespaces).map { _ in " " }.joined()
        let selfAndDepsDescription = injectedTree
            .map { whitespacesString + $0 }
            .joined(separator: "\n")
        let childTree = children
            .map { child -> [String] in
                guard let treeNode = child as? InjectionTreeNodeBox else {
                    return []
                }
                return treeNode.anyLink?.treeDescription(whitespaces: whitespaces + 4) ?? []
            }
            .flatMap {
                $0
            }
        return [[selfAndDepsDescription], childTree].flatMap { $0 }
    }
}

public extension InjectionTreeNodeProtocol {
    var parentNode: InjectionTreeNodeProtocol? {
        get {
            fatalError("Don't try implementing ChainLinkProtocol, " +
                       " this is an internal helper for optional-nonoptional property wrapping")
        }
        set {
            fatalError("Trying to set value \(String(describing: newValue)) to parentNode. " +
                       "Don't try implementing ChainLinkProtocol, " +
                       " this is an internal helper for optional-nonoptional property wrapping")
        }
    }
}

extension Optional: InjectionTreeNodeProtocol where Wrapped: InjectionTreeNode {

    public var parentNode: InjectionTreeNodeProtocol? {
        get {
            return self?.parentNode
        }
        set {
            self?.parentNode = newValue
        }
    }

    public var keyPathToSelfOnParent: AnyKeyPath? {
        get {
            return self?.keyPathToSelfOnParent
        }
        set {
            self?.keyPathToSelfOnParent = newValue
        }
    }

    public var childrenNodes: [InjectionTreeNodeProtocol] {
        self?.childrenNodes ?? []
    }

    public var rootNode: InjectionTreeNodeProtocol? {
        self?.rootNode
    }
}
