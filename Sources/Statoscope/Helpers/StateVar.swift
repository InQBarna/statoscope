//
//  StateVar.swift
//  
//
//  Created by Sergi Hernanz on 4/2/24.
//

import Foundation

/// Helper property wrapper to easily mock a protocollized var with nonmutating set
///
/// ## Usage example
/// ```swift
/// protocol SomeProtocol {
///   var variable1: String { get nonmutating set }
/// }
/// struct SomeStruct: SomeProtocol {
///   @StateVar var variable1: String
/// }
/// ````
@propertyWrapper
public class StateVar<Value> {
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    public var wrappedValue: Value
}
