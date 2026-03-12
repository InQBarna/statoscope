//
//  SubStateMacro.swift
//  Statoscope
//
//  Created by Claude Code on 28/2/26.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Macro that expands @SubState property declarations to add storage and accessor with setter
///
/// Transforms:
/// ```swift
/// @SubState var child: ChildState?
/// ```
///
/// Adds storage as peer:
/// ```swift
/// var _$child: SubStateBinding<ChildState>? = nil
/// ```
///
/// And adds accessors to original property:
/// ```swift
/// var child: ChildState? {
///     get { _$child?.wrappedValue }
///     set {
///         if let newValue = newValue {
///             // Always create a fresh pending binding; wireChildren() creates/replaces the Store
///             _$child = SubStateBinding(wrappedValue: newValue)
///         } else {
///             _$child = nil
///         }
///     }
/// }
/// ```
public struct SubStateMacro: AccessorMacro, PeerMacro {

    // MARK: - AccessorMacro

    /// Adds getter and setter accessors that read/write through the storage property
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
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let typeAnnotation = binding.typeAnnotation else {
            throw StatoscopeMacroError.message("@SubState can only be applied to stored properties with explicit type")
        }

        // Validate that property type is optional
        guard typeAnnotation.type.is(OptionalTypeSyntax.self) else {
            let diagnostic = Diagnostic(
                node: Syntax(typeAnnotation),
                message: StatoscopeMacroDiagnostic.subStateNotOptional
            )
            context.diagnose(diagnostic)
            throw StatoscopeMacroError.message("@SubState properties must be optional (use ChildState?)")
        }

        let propertyName = identifier.text
        let storageName = "_$\(propertyName)"

        // Generate getter and setter
        let getter: AccessorDeclSyntax = """
        get { \(raw: storageName)?.wrappedValue }
        """

        let setter: AccessorDeclSyntax = """
        set {
            if let newValue = newValue {
                // Always create a fresh pending binding.
                // wireChildren() detects _isPending and creates (or replaces) the child Store.
                // Any existing Store is discarded; use the child Store's send() to update
                // child state in-place without replacing the Store.
                \(raw: storageName) = SubStateBinding(wrappedValue: newValue)
            } else {
                \(raw: storageName) = nil
            }
        }
        """

        return [getter, setter]
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
              let typeAnnotation = binding.typeAnnotation,
              let optionalType = typeAnnotation.type.as(OptionalTypeSyntax.self) else {
            throw StatoscopeMacroError.message("@SubState requires explicit optional type annotation (ChildState?)")
        }

        let propertyName = identifier.text
        let childType = optionalType.wrappedType
        let storageName = "_$\(propertyName)"

        // Generate storage property
        let storageDecl: DeclSyntax = """
        var \(raw: storageName): SubStateBinding<\(childType)>? = nil
        """

        return [storageDecl]
    }
}
