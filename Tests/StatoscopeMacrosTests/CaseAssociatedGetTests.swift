//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 16/3/24.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class CaseAssociatedGetTests: XCTestCase {

    func testCaseAssociatedGetters() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @CaseAssociatedGet
            enum When {
                case associatedBool(Bool)
                case associatedTuple(Bool, Int, String)
                case associatedObject(SomeObjectType)
                case associatedWithLabels(boolLabel: Bool, intLabel: Int, stringLabel: String)
                case nonAssociatedCase
            }
            """#,
            expandedSource: #"""
            enum When {
                case associatedBool(Bool)
                case associatedTuple(Bool, Int, String)
                case associatedObject(SomeObjectType)
                case associatedWithLabels(boolLabel: Bool, intLabel: Int, stringLabel: String)
                case nonAssociatedCase
            
                var associatedBool: Bool? {
                    switch self {
                        case .associatedBool(let associatedValue):
                        return associatedValue
                        default:
                        return nil
                    }
                }
            
                var associatedTuple: (Bool, Int, String)? {
                    switch self {
                        case .associatedTuple(let associatedValue):
                        return associatedValue
                        default:
                        return nil
                    }
                }
            
                var associatedObject: SomeObjectType? {
                    switch self {
                        case .associatedObject(let associatedValue):
                        return associatedValue
                        default:
                        return nil
                    }
                }
            
                var associatedWithLabels: (Bool, Int, String)? {
                    switch self {
                        case .associatedWithLabels(let associatedValue):
                        return associatedValue
                        default:
                        return nil
                    }
                }
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
