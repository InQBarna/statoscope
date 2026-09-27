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
///
/// Inherits `InjectionKeyProviding` so every conforming type automatically gets an
/// `injectionKey` — `@Injected(SomeInjectableType.self)` works for any `Injectable` type with
/// zero further changes to that type, the same way it does for a genuine protocol whose default
/// implementation conforms to `InjectionKeyProviding` directly.
public protocol Injectable: InjectionKeyProviding where InjectedValue == Self {
    static var defaultValue: Self { get }
}

extension Injectable {
    public static var injectionKey: InjectionKey<Self> { InjectionKey(defaultValue: defaultValue) }
}
