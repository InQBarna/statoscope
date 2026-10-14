//
//  AutoConnectedView.swift
//  Statoscope
//

import SwiftUI

// MARK: - ReducerStoreProtocol

/// Protocol that generated `@Reducer` Store classes conform to.
public protocol ReducerStoreProtocol: ObservableObject {
    associatedtype State
    associatedtype When
    var state: State { get }
    func _dispatch(_ when: When)
}

// MARK: - ReducerStoreView

/// Root connector between a `@Reducer`-generated Store and a `StoreViewProtocol` view.
///
/// Renders the view with the store's current state and injects `store` into the SwiftUI
/// environment, exactly once — the one true-root injection every `ConnectedChild` further down
/// the tree resolves against via `ReducerKeyPath`.
///
/// Place the `NavigationStack` **inside** the root `StoreViewProtocol` view so the injected
/// store is an ancestor of the stack and propagates through all pushed destinations:
///
/// ```swift
/// struct AppRootView: StoreViewProtocol {
///     var model: AppReducer.State
///     var send: (AppReducer.When) -> Void
///     var body: some View {
///         NavigationStack { ... }   // ← inside ReducerStoreView, so store reaches destinations
///     }
/// }
/// ReducerStoreView<AppReducer.Store, AppRootView>(store: store)
/// ```
public struct ReducerStoreView<S: ReducerStoreProtocol, V: StoreViewProtocol>: View
    where S.State == V.State, S.When == V.When {

    @ObservedObject public var store: S

    public init(store: S) {
        self.store = store
    }

    public var body: some View {
        V(model: store.state, send: store._dispatch)
            .environmentObject(store)
    }
}

// MARK: - ConnectedChild

/// Embeds a child view connected to a descendant Store, resolved via an explicit
/// `ReducerKeyPath` from the root — safe at any nesting depth, through any number of
/// `.navigationDestination`/`.sheet`/`.fullScreenCover` levels, because resolution never depends
/// on where *this* view happens to sit in the hierarchy, only on the root Store (reached once,
/// via `@EnvironmentObject`, injected by `ReducerStoreView`) and the path carried in explicitly.
///
/// Renders nothing if the path resolves to `nil` (e.g. the `@SubState` it points to is currently
/// `nil`) — a normal, momentary state for content that hasn't been created yet, not an error.
///
/// ```swift
/// ConnectedChild(ownPath.append(\.child, as: ChildReducer.self)) { state, send, childPath in
///     ChildView(model: state, send: send, ownPath: childPath)
/// }
/// ```
public struct ConnectedChild<
    RootReducer: Reducer, CurrentReducer: Reducer, V: View
>: View {

    @EnvironmentObject private var root: RootReducer.OwnStore
    private let path: ReducerKeyPath<RootReducer, CurrentReducer>
    private let content: (
        CurrentReducer.State,
        @escaping (CurrentReducer.When) -> Void,
        ReducerKeyPath<RootReducer, CurrentReducer>
    ) -> V

    public init(
        _ path: ReducerKeyPath<RootReducer, CurrentReducer>,
        @ViewBuilder content: @escaping (
            CurrentReducer.State,
            @escaping (CurrentReducer.When) -> Void,
            ReducerKeyPath<RootReducer, CurrentReducer>
        ) -> V
    ) {
        self.path = path
        self.content = content
    }

    public var body: some View {
        if let store = path.resolve(from: root) {
            _ObservedChildContent(store: store, path: path, content: content)
        }
    }
}

/// Two observation layers are required, not one: `root`'s `objectWillChange` only fires for the
/// *root's own* `@SubState` mutations (creating/destroying a descendant is always a mutation
/// somewhere up that chain) — it does NOT fire when an already-resolved descendant Store
/// processes its own, independent events, since that's a separate `ObservableObject`. Without
/// this second `@ObservedObject` layer, a descendant's own state changes silently fail to
/// trigger a re-render here.
private struct _ObservedChildContent<
    RootReducer: Reducer, CurrentReducer: Reducer, V: View
>: View {
    @ObservedObject var store: CurrentReducer.OwnStore
    let path: ReducerKeyPath<RootReducer, CurrentReducer>
    let content: (
        CurrentReducer.State,
        @escaping (CurrentReducer.When) -> Void,
        ReducerKeyPath<RootReducer, CurrentReducer>
    ) -> V

    var body: some View {
        content(store.state, store._dispatch, path)
    }
}

// MARK: - Reducer.bind — reusable presentation Binding for StoreViewProtocol views

extension Reducer {
    /// Builds a `Binding<Bool>` from an already-resolved `model`/`send` pair — the shape every
    /// `StoreViewProtocol` view already has — instead of a live store reference.
    ///
    /// - Parameters:
    ///   - keyPath: An optional property on `State` — the binding reads `true` while it's
    ///     non-nil in `model`.
    ///   - model: The `State` snapshot already in scope in a `StoreViewProtocol` view's body.
    ///   - dismissWhen: Sent via `send` when the binding is set to `false`.
    ///   - send: The dispatch closure already in scope in a `StoreViewProtocol` view's body.
    /// - Returns: `true` while `model[keyPath: keyPath] != nil`; setting it to `false` calls
    ///   `send(dismissWhen)`. Setting it to `true` has no effect, matching the instance-based
    ///   overload below.
    ///
    /// ## Example
    /// ```swift
    /// struct MyAccountView: StoreViewProtocol {
    ///     var model: MyAccountReducer.State
    ///     var send: (MyAccountReducer.When) -> Void
    ///     var body: some View {
    ///         Text("Account")
    ///             .alert(
    ///                 "Error",
    ///                 isPresented: MyAccountReducer.bind(\.errorMessage, in: model, dismissWhen: .dismissError, send: send),
    ///                 actions: {}
    ///             )
    ///     }
    /// }
    /// ```
    public static func bind<Value>(
        _ keyPath: KeyPath<State, Value?>,
        in model: State,
        dismissWhen: When,
        send: @escaping (When) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] != nil },
            set: { if !$0 { send(dismissWhen) } }
        )
    }
}

// MARK: - ReducerStoreProtocol.bind — reusable presentation Binding

extension ReducerStoreProtocol {
    /// Builds a `Binding<Bool>` for presenting/dismissing UI driven by an optional property
    /// on `state`, exposed here so you can wire up your own `.sheet`/`.popover`/
    /// `.fullScreenCover`/`.navigationDestination`/custom presentation without reimplementing
    /// the `Binding(get:set:)` boilerplate by hand.
    ///
    /// - Parameters:
    ///   - keyPath: An optional property on `State` — the binding reads `true` while it's
    ///     non-nil. Doesn't have to be a `@SubState` child; any optional `State` property works
    ///     (e.g. `var alertMessage: String?` for a `.alert(isPresented:)` binding).
    ///   - dismissWhen: Sent to `update()` when the binding is set to `false` — e.g. the user
    ///     swipes back or taps outside a sheet. Typically the same `When` case that clears
    ///     `keyPath` back to `nil`.
    /// - Returns: `true` while `state[keyPath: keyPath] != nil`; setting it to `false` sends
    ///   `dismissWhen`. Setting it to `true` has no effect — presentation is driven by state,
    ///   not by the binding.
    ///
    /// ## Example
    /// ```swift
    /// struct MyAccountView: View {
    ///     @ObservedObject var store: MyAccountReducer.Store
    ///     var body: some View {
    ///         Text("Account")
    ///             .sheet(isPresented: store.bind(\.signIn, dismissWhen: .userDismissedSignIn)) {
    ///                 // ...
    ///             }
    ///     }
    /// }
    /// ```
    public func bind<Value>(
        _ keyPath: KeyPath<State, Value?>,
        dismissWhen: When
    ) -> Binding<Bool> {
        Binding(
            get: { self.state[keyPath: keyPath] != nil },
            set: { if !$0 { self._dispatch(dismissWhen) } }
        )
    }
}
