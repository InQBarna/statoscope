//
//  ReducerInjectedMacro.swift
//  Statoscope
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Macro that expands @ReducerInjected property declarations in a Reducer's State struct
///
/// Transforms:
/// ```swift
/// @ReducerInjected var logger: Logger
/// ```
///
/// Adds storage as peer:
/// ```swift
/// var _$logger: InjectedBinding<Logger> = .defaultValue
/// ```
///
/// And adds accessor to original property:
/// ```swift
/// var logger: Logger {
///     get { _$logger.wrappedValue }
/// }
/// ```
///
/// The `@Reducer` macro then detects `_$name: InjectedBinding<T>` storage properties
/// and generates injection code in the Store's state getter so the binding resolves
/// from the live injection tree at access time.
public struct ReducerInjectedMacro: AccessorMacro, PeerMacro {

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

        guard let property = declaration.as(VariableDeclSyntax.self),
              let binding = property.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            throw StatoscopeMacroError.message("@ReducerInjected can only be applied to stored properties")
        }

        let propertyName = identifier.text
        let storageName = "_$\(propertyName)"

        let getter: AccessorDeclSyntax = """
        get { \(raw: storageName).wrappedValue }
        """

        return [getter]
    }

    // MARK: - PeerMacro

    /// Generates the InjectedBinding storage property as a peer
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
            throw StatoscopeMacroError.message("@ReducerInjected requires explicit type annotation")
        }

        let propertyName = identifier.text
        let propertyType = typeAnnotation.type
        let storageName = "_$\(propertyName)"

        let storageDecl: DeclSyntax = """
        var \(raw: storageName): InjectedBinding<\(propertyType)> = .defaultValue
        """

        return [storageDecl]
    }
}
