//
//  EnvironmentInjectionCrashDemo.swift
//  Statoscope
//
//  Demonstrates the @EnvironmentObject propagation failure that occurs when a child-store
//  connector is resolved lazily inside navigation/presentation content, and the fix:
//  `ReducerKeyPath` — an explicit, position-based path from the root Store down to a
//  descendant, carried through ordinary `init` parameters rather than resolved from any global.
//  See `ReducerKeyPath`'s own documentation for the full mechanism and why it's needed.
//
//  Preview "Crash reproduction": shows the ORIGINAL bug (hand-rolled, raw @EnvironmentObject,
//  bypassing the library entirely) that motivated this whole design. `ConnectedChild` never
//  reproduces this crash — it resolves through the root Store (injected exactly once) plus an
//  explicit `ReducerKeyPath`, never a level-specific `@EnvironmentObject` lookup.
//
//  NOTE: Xcode Previews may not crash here because the Preview host injects its own
//  environment. Run on a simulator or device to see the crash.
//

#if DEBUG
import SwiftUI
import Statoscope

// MARK: - The ORIGINAL bug, hand-rolled, bypassing the library

/// Minimal ReducerStoreProtocol conforming parent store
final class _DemoParentStore: ObservableObject, ReducerStoreProtocol {
    struct State {
        var title: String = "Parent"
        var child: _DemoChildStore? = nil
    }
    enum When {
        case showChild
        case hideChild
    }

    @Published var state: State = State()

    init() {}

    func _dispatch(_ when: When) {
        switch when {
        case .showChild:
            state.child = _DemoChildStore()
        case .hideChild:
            state.child = nil
        }
        objectWillChange.send()
    }

    var child: _DemoChildStore? { state.child }
}

/// Minimal ReducerStoreProtocol conforming child store
final class _DemoChildStore: ObservableObject, ReducerStoreProtocol {
    struct State {
        var label: String = "Child view rendered ✓"
    }
    enum When {}

    @Published var state: State = State()

    func _dispatch(_ when: When) {}
}

/// The child view — a StoreViewProtocol-like view
private struct _DemoChildPresentedView: View {
    let model: _DemoChildStore.State
    let send: (_DemoChildStore.When) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.label)
                .font(.headline)
            Text("@EnvironmentObject was resolved successfully")
                .foregroundColor(.green)
        }
        .padding()
    }
}

/// Hand-rolls the exact pattern that used to crash: a connector resolving `@EnvironmentObject`
/// lazily, inside a `NavigationLink` destination closure. This is the historical motivation for
/// this whole design — kept as a standalone repro, independent of the library's own connector.
private struct _HandRolledUnsafeConnector: View {
    @EnvironmentObject private var parentStore: _DemoParentStore
    let content: (_DemoChildStore.State, @escaping (_DemoChildStore.When) -> Void) -> _DemoChildPresentedView

    var body: some View {
        if let childStore = parentStore.child {
            content(childStore.state, childStore._dispatch)
        }
    }
}

private struct _DemoParentView: View {
    let model: _DemoParentStore.State
    let send: (_DemoParentStore.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Navigate to child") {
                send(.showChild)
            }

            NavigationLink(
                isActive: Binding(
                    get: { model.child != nil },
                    set: { if !$0 { send(.hideChild) } }
                ),
                destination: {
                    // ← body evaluated here, AFTER push.
                    // On device: @EnvironmentObject lookup for _DemoParentStore fails → CRASH
                    _HandRolledUnsafeConnector(content: _DemoChildPresentedView.init)
                }
            ) {
                EmptyView()
            }
            #if !os(macOS)
            .isDetailLink(false)
            #endif

            Text("↑ Tapping the button above will crash on device/simulator\nbut may survive in Xcode Preview")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Demo — original bug (hand-rolled)")
    }
}

private struct _StoreViewBridge: View, StoreViewProtocol {
    typealias State = _DemoParentStore.State
    typealias When = _DemoParentStore.When

    let model: State
    let send: (When) -> Void

    init(model: State, send: @escaping (When) -> Void) {
        self.model = model
        self.send = send
    }

    var body: some View {
        // INTENTIONALLY the anti-pattern: NavigationView wraps ReducerStoreView, rather than
        // the other way around (as ReducerStoreView's own doc requires) — this is what recreates
        // the original bug. The fixed demo below follows the documented convention.
        NavigationView { _DemoParentView(model: model, send: send) }
    }
}

#Preview("Crash reproduction — run on simulator to see crash") {
    let store = _DemoParentStore()
    return ReducerStoreView<_DemoParentStore, _StoreViewBridge>(store: store)
}

// MARK: - The fix: ReducerKeyPath, two levels deep (parent → child → grandchild)
//
// Everything above hand-conforms minimal stores to ReducerStoreProtocol, to keep the repro
// self-contained — but `ConnectedChild`/`ReducerKeyPath` are keyed on real `Reducer` types (to
// get `Reducer.OwnStore` and the macro-generated hop registration), so the fix itself is best
// shown with a real `@Reducer`/`@SubState` chain — exactly what a library consumer writes, and
// deep enough (two pushes) to exercise the actual problem: SwiftUI detaches a
// `.navigationDestination`'s content from wherever the pushing view happens to be nested, so an
// `@EnvironmentObject` injected anywhere but the true root is unreachable past the first level.

@Reducer
private struct _RealDemoGrandchildReducer {
    struct State {
        var label: String = "Grandchild view rendered ✓ (2 pushes deep)"
    }
    enum When {}

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {}
}

@Reducer
private struct _RealDemoChildReducer {
    struct State {
        var label: String = "Child view rendered ✓"
        @SubState var grandchild: _RealDemoGrandchildReducer.State?
    }
    enum When {
        case showGrandchild
        case hideGrandchild
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showGrandchild:
            state.grandchild = _RealDemoGrandchildReducer.State()
        case .hideGrandchild:
            state.grandchild = nil
        }
    }
}

@Reducer
private struct _RealDemoParentReducer {
    struct State {
        var title: String = "Parent"
        @SubState var child: _RealDemoChildReducer.State?
        // Not a child scope — plain data on this reducer's own State. Presenting UI driven
        // by this needs no live store, no @EnvironmentObject, no path resolution:
        // `Reducer.bind(_:in:dismissWhen:send:)` is a direct fit.
        var infoMessage: String?
    }
    enum When {
        case showChild
        case hideChild
        case showInfo
        case dismissInfo
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showChild:
            state.child = _RealDemoChildReducer.State()
        case .hideChild:
            state.child = nil
        case .showInfo:
            state.infoMessage = "This alert's Binding was built by Reducer.bind — no live store involved."
        case .dismissInfo:
            state.infoMessage = nil
        }
    }
}

private struct _RealDemoGrandchildPresentedView: View {
    let model: _RealDemoGrandchildReducer.State
    let send: (_RealDemoGrandchildReducer.When) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.label)
                .font(.headline)
            Text("Resolved through 2 nested .navigationDestination levels")
                .foregroundColor(.green)
        }
        .padding()
        .navigationTitle("Grandchild")
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoChildPresentedView: View {
    let model: _RealDemoChildReducer.State
    let send: (_RealDemoChildReducer.When) -> Void
    let ownPath: ReducerKeyPath<_RealDemoParentReducer, _RealDemoChildReducer>

    var body: some View {
        VStack(spacing: 16) {
            Text(model.label)
                .font(.headline)
            Button("Navigate to grandchild") {
                send(.showGrandchild)
            }
        }
        .padding()
        .navigationTitle("Child")
        .navigationDestination(
            isPresented: _RealDemoChildReducer.bind(\.grandchild, in: model, dismissWhen: .hideGrandchild, send: send)
        ) {
            ConnectedChild(ownPath.append(\.grandchild, as: _RealDemoGrandchildReducer.self)) { state, send, _ in
                _RealDemoGrandchildPresentedView(model: state, send: send)
            }
        }
    }
}

/// The real macro-backed fix: an explicit `ReducerKeyPath`, carried via `ownPath`, resolved by
/// `ConnectedChild` — paired with `bind`, via `.navigationDestination`.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoFixedParentView: View {
    let model: _RealDemoParentReducer.State
    let send: (_RealDemoParentReducer.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Navigate to child") {
                send(.showChild)
            }

            Text("↑ Works on device/simulator, 2 levels deep — real bind + ConnectedChild + ReducerKeyPath")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Real @Reducer — ReducerKeyPath fix")
        .navigationDestination(isPresented: _RealDemoParentReducer.bind(\.child, in: model, dismissWhen: .hideChild, send: send)) {
            ConnectedChild(ReducerKeyPath<_RealDemoParentReducer, _RealDemoParentReducer>.root.append(\.child, as: _RealDemoChildReducer.self)) { state, send, childPath in
                _RealDemoChildPresentedView(model: state, send: send, ownPath: childPath)
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoFixedStoreViewBridge: View, StoreViewProtocol {
    typealias State = _RealDemoParentReducer.State
    typealias When = _RealDemoParentReducer.When
    let model: State
    let send: (When) -> Void
    init(model: State, send: @escaping (When) -> Void) {
        self.model = model; self.send = send
    }
    var body: some View {
        NavigationStack { _RealDemoFixedParentView(model: model, send: send) }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private func _makeRealDemoFixedPreview() -> some View {
    let store = _RealDemoParentReducer.Store(initialState: _RealDemoParentReducer.State())
    return ReducerStoreView<_RealDemoParentReducer.Store, _RealDemoFixedStoreViewBridge>(store: store)
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
#Preview("Real @Reducer — ReducerKeyPath fix, 2 levels deep") {
    _makeRealDemoFixedPreview()
}
#endif
