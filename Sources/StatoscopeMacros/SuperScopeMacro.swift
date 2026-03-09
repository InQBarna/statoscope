//
//  SuperScopeMacro.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 09/03/26.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Macro that expands @SuperScope property declarations to add storage and accessor
///
/// Used in `Reducer.State` to reference a parent Statostore that has not yet been
/// migrated to the Reducer pattern. The `@Reducer` macro detects `@SuperScope`
/// properties and generates a matching `@Superscope` property on the Store class,
/// injecting a `ParentStoreBinding` into the state getter.
///
/// Transforms:
/// ```swift
/// @SuperScope(observed: true) var parent: ParentStore
/// ```
///
/// Adds storage as peer:
/// ```swift
/// var _$parent: ParentStoreBinding<ParentStore> = .defaultValue
/// ```
///
/// And adds accessor to original property:
/// ```swift
/// var parent: ParentStore {
///     get { _$parent.wrappedValue }
/// }
/// ```
public struct SuperScopeMacro: AccessorMacro, PeerMacro {

    // MARK: - AccessorMacro

    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclSyntaxProtocol
    >(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: Declaration,
        in context: Context
    ) throws -> [AccessorDeclSyntax] {

        guard let property = declaration.as(VariableDeclSyntax.self),
              let binding = property.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            throw StatoscopeMacroError.message("@SuperScope can only be applied to stored properties")
        }

        let storageName = "_$\(identifier.text)"

        let getter: AccessorDeclSyntax = """
        get { \(raw: storageName).wrappedValue }
        """

        return [getter]
    }

    // MARK: - PeerMacro

    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclSyntaxProtocol
    >(
        of node: AttributeSyntax,
        providingPeersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] {

        guard let property = declaration.as(VariableDeclSyntax.self),
              let binding = property.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let typeAnnotation = binding.typeAnnotation else {
            throw StatoscopeMacroError.message("@SuperScope requires explicit type annotation")
        }

        let propertyName = identifier.text
        let propertyType = typeAnnotation.type
        let storageName = "_$\(propertyName)"

        let storageDecl: DeclSyntax = """
        var \(raw: storageName): ParentStoreBinding<\(propertyType)> = .defaultValue
        """

        return [storageDecl]
    }
}
