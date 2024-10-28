//
//  DummyScopeImplementation.swift
//
//
//  Created by Sergi Hernanz on 26/8/24.
//

public protocol DummyScopeImplementation: ScopeImplementation { }
public extension DummyScopeImplementation {
    func update(_ when: When) throws { }
}

