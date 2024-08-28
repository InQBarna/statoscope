//
//  DummyScopeImplementation.swift
//
//
//  Created by Sergi Hernanz on 26/8/24.
//

protocol DummyScopeImplementation: ScopeImplementation { }
extension DummyScopeImplementation {
    func update(_ when: When) throws { }
}

