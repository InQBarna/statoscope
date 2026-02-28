//
//  SuperStateMacro.swift
//  Statoscope
//
//  Created by Claude Code on 28/2/26.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Macro that expands @SuperState property declarations to add storage and accessor
///
/// Transforms:
/// ```swift
/// @SuperState var parent: ParentState
/// ```
///
/// Adds storage as peer:
/// ```swift
/// var _$parent: SuperStateBinding<ParentState> = .defaultValue
/// ```
///
/// And adds accessor to original property:
/// ```swift
/// var parent: ParentState {
///     get { _$parent.wrappedValue }
/// }
/// ```
public struct SuperStateMacro: AccessorMacro, PeerMacro {

    // MARK: - AccessorMacro

    /// Adds getter accessor that reads from the storage property
    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclSyntaxProtocol
    >(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: Declaration,
        in context: Context
    ) throws -> [AccessorDeclSyntax] {

        // Extract property declaration
        guard let property = declaration.as(VariableDeclSyntax.self),
              let binding = property.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            throw StatoscopeMacroError.message("@SuperState can only be applied to stored properties")
        }

        let propertyName = identifier.text
        let storageName = "_$\(propertyName)"

        // Generate getter that reads from storage
        let getter: AccessorDeclSyntax = """
        get { \(raw: storageName).wrappedValue }
        """

        return [getter]
    }

    // MARK: - PeerMacro

    /// Generates the storage property as a peer
    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclSyntaxProtocol
    >(
        of node: AttributeSyntax,
        providingPeersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] {

        // Extract property declaration
        guard let property = declaration.as(VariableDeclSyntax.self),
              let binding = property.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let typeAnnotation = binding.typeAnnotation else {
            throw StatoscopeMacroError.message("@SuperState requires explicit type annotation")
        }

        let propertyName = identifier.text
        let propertyType = typeAnnotation.type
        let storageName = "_$\(propertyName)"

        // Generate storage property
        let storageDecl: DeclSyntax = """
        var \(raw: storageName): SuperStateBinding<\(propertyType)> = .defaultValue
        """

        return [storageDecl]
    }
}
