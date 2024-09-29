//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 11/3/24.
//

import Foundation

public protocol StoreProtocol {
    associatedtype ScopeImpl: ScopeImplementation

    /// The state handled by the store.
    ///
    /// The state object should implement the ``Scope`` protocol, providing
    /// * Usable inside injection tree
    /// * Member variables with the Scope's state
    var _scopeImpl: ScopeImpl { get }

    /// Public method to send events to the store
    ///
    /// Usually UI or system notitications send messages to stores using a When case
    /// * Parameter when: the typed event case to send to the store
    @discardableResult
    func send(_ when: ScopeImpl.When) -> Self

    /// Public method to send events to the store
    ///
    /// Usually UI or system notitications send messages to stores using a When case
    ///
    /// # Discussion
    /// Different from ``send(_:)`` because this method throws any unexpected
    /// exception. Use this method for debugging or unit testing
    ///
    /// * Parameter when: the typed event case to send to the store
    @discardableResult
    func sendUnsafe(_ when: ScopeImpl.When) throws -> Self
}

extension StoreProtocol {
    @discardableResult
    public func send(_ when: ScopeImpl.When) -> Self {
        _scopeImpl._sendImplementation(when)
        return self
    }

    @discardableResult
    public func sendUnsafe(_ when: ScopeImpl.When) throws -> Self {
        try _scopeImpl._unsafeSendImplementation(when)
        return self
    }
}

struct Store<ScopeImpl: Scope> {
    let scopeImpl: ScopeImpl
}
