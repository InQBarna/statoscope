//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation

/// An Scope is the specification of a piece of the app's state and business model
///
/// Should define
/// * Member variables with the state
/// * When events that
/// * Is an InjectionTreeNode to communicate with other scopes
public protocol Scope:
    InjectionTreeNode &
    CustomDebugStringConvertible &
    AnyObject {
    associatedtype When: Sendable
}
