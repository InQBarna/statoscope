//
//  AutoConnectedView.swift
//  Statoscope
//

import SwiftUI

// Typealias used by macro-generated `build<Name>View` methods so generated code doesn't
// require `import SwiftUI` in the file where `@Reducer` is applied.
public typealias _StatoscopeView = SwiftUI.View

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
/// environment so that `build<Name>View` methods and `AutoConnectedView` can resolve
/// the store from any descendant — including navigation destinations.
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

// MARK: - AutoConnectedView

/// Embeds a child view connected to a child store, resolved from the parent store via a `KeyPath`.
///
/// Reads the parent store from `@EnvironmentObject`, navigates to the child store,
/// and — if non-nil — renders the child view observing that store.
///
/// ## Requirement
/// The parent store must be in the SwiftUI environment via `.environmentObject(store)`.
/// `ReducerStoreView` injects it automatically.
public struct AutoConnectedView<
    ParentStore: ReducerStoreProtocol,
    ChildStore: ReducerStoreProtocol,
    V: StoreViewProtocol
>: View where ChildStore.State == V.State, ChildStore.When == V.When {

    @EnvironmentObject private var parentStore: ParentStore
    private let keyPath: KeyPath<ParentStore, ChildStore?>

    public init(_ keyPath: KeyPath<ParentStore, ChildStore?>) {
        self.keyPath = keyPath
    }

    public var body: some View {
        if let childStore = parentStore[keyPath: keyPath] {
            _ConnectedChildView<ChildStore, V>(store: childStore)
        }
    }
}

private struct _ConnectedChildView<S: ReducerStoreProtocol, V: StoreViewProtocol>: View
    where S.State == V.State, S.When == V.When {

    @ObservedObject var store: S

    var body: some View {
        V(model: store.state, send: store._dispatch)
            .environmentObject(store)
    }
}

// MARK: - ReducerObservedView

/// Observes a `ReducerStoreProtocol` store and renders a view closure with its current state,
/// injecting the store into the SwiftUI environment so `build<Name>View` navigation methods work.
///
/// Use this instead of a hand-written `@ObservedObject` wrapper whenever the view tree contains
/// navigation to child scopes via `build<Name>View`.
///
/// ```swift
/// ReducerObservedView(store: store) { state, dispatch in
///     MyAccountPresentedView(model: state, send: dispatch)
/// }
/// ```
public struct ReducerObservedView<S: ReducerStoreProtocol, V: View>: View {
    @ObservedObject public var store: S
    private let content: (S.State, @escaping (S.When) -> Void) -> V

    public init(store: S, @ViewBuilder content: @escaping (S.State, @escaping (S.When) -> Void) -> V) {
        self.store = store
        self.content = content
    }

    public var body: some View {
        content(store.state, store._dispatch)
            .environmentObject(store)
    }
}

// MARK: - _ReducerChildObservingView (private shared helper)

private struct _ReducerChildObservingView<S: ReducerStoreProtocol, V: View>: View {
    @ObservedObject var store: S
    let content: (S.State, @escaping (S.When) -> Void) -> V

    var body: some View {
        content(store.state, store._dispatch)
            .environmentObject(store)
    }
}

// MARK: - _ReducerChildViewConnector

/// Used by macro-generated `build<Name>View` methods to connect a child store to a view closure.
///
/// Reads the parent store from `@EnvironmentObject`, navigates to the child store via
/// `storeKeyPath`, and — if non-nil — renders `content` observing that child store.
///
/// Prefer the Store instance method `store.build<Name>View { ... }` over this type directly,
/// as it avoids `@EnvironmentObject` propagation through `NavigationLink` destinations.
public struct _ReducerChildViewConnector<
    ParentStore: ReducerStoreProtocol,
    ChildStore: ReducerStoreProtocol,
    V: View
>: View {

    @EnvironmentObject private var parentStore: ParentStore
    private let storeKeyPath: KeyPath<ParentStore, ChildStore?>
    private let content: (ChildStore.State, @escaping (ChildStore.When) -> Void) -> V

    public init(
        storeKeyPath: KeyPath<ParentStore, ChildStore?>,
        content: @escaping (ChildStore.State, @escaping (ChildStore.When) -> Void) -> V
    ) {
        self.storeKeyPath = storeKeyPath
        self.content = content
    }

    public var body: some View {
        if let childStore = parentStore[keyPath: storeKeyPath] {
            _ReducerChildObservingView(store: childStore, content: content)
        }
    }
}

// MARK: - _ReducerChildNavigationConnector

/// Navigation-safe connector generated by `build<Name>PresentedView(isPresented:content:)`.
///
/// Unlike `_ReducerChildViewConnector`, this view IS the NavigationLink — it resolves
/// `@EnvironmentObject` in its own `body` (sibling render context, not lazily as a destination),
/// captures the parent store reference, and builds the destination using that direct reference.
///
/// This avoids the crash that occurs when a parent store was injected below the NavigationView
/// level and `@EnvironmentObject` resolution fails inside a lazy NavigationLink destination.
///
/// Usage (via macro-generated static method on the Reducer):
/// ```swift
/// MyAccountReducer.buildSignInPresentedView(
///     dismissWhen: .userTapsBackFromSignInOrLogin,
///     content: SignInPresentedView.init
/// )
/// ```
/// The `isPresented` binding is derived internally from the keypath — no manual
/// `Binding<Bool>` construction needed.
public struct _ReducerChildNavigationConnector<
    ParentStore: ReducerStoreProtocol,
    ChildStore: ReducerStoreProtocol,
    V: View
>: View {

    // Resolved here — in the sibling body render context, NOT in a lazy destination closure.
    @EnvironmentObject private var parentStore: ParentStore
    private let storeKeyPath: KeyPath<ParentStore, ChildStore?>
    private let dismissWhen: ParentStore.When
    private let content: (ChildStore.State, @escaping (ChildStore.When) -> Void) -> V

    public init(
        storeKeyPath: KeyPath<ParentStore, ChildStore?>,
        dismissWhen: ParentStore.When,
        content: @escaping (ChildStore.State, @escaping (ChildStore.When) -> Void) -> V
    ) {
        self.storeKeyPath = storeKeyPath
        self.dismissWhen = dismissWhen
        self.content = content
    }

    public var body: some View {
        // `parentStore` captured here (sibling body — @EnvironmentObject is available).
        // The destination closure captures it by direct reference — no @EnvironmentObject
        // lookup happens when SwiftUI lazily evaluates the destination.
        let capturedStore = parentStore
        let capturedDismissWhen = dismissWhen
        NavigationLink(
            isActive: Binding(
                get: { capturedStore[keyPath: storeKeyPath] != nil },
                set: { if !$0 { capturedStore._dispatch(capturedDismissWhen) } }
            ),
            destination: {
                if let childStore = capturedStore[keyPath: storeKeyPath] {
                    _ReducerChildObservingView(store: childStore, content: content)
                }
            }
        ) { EmptyView() }
        #if !os(macOS)
        .isDetailLink(false)
        #endif
    }
}
