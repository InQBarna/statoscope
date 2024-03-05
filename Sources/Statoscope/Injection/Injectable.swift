//
//  Injectable.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Implemented by objects thata can be used by the injection property wrappers
///
/// Only objects implementing this protocol can be used by the injection property wrappers
/// * ``Injected``: To use an Injectable instance in your scope.
/// * ``Superscope``: To use a superscope in your scope, automatically retrieved
/// * ``Subscope``: To retain subscopes that may need access to superscopes
public protocol Injectable {
    static var defaultValue: Self { get }
}
