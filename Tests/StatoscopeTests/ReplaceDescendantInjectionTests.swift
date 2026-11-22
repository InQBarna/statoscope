import XCTest
import Statoscope

// PARITY_AUDIT.md Issue 21 (Kotlin: ReplaceDescendantInjectionTest): what survives when a root
// replaces a grandchild by writing through the middle level (`state.mid?.leaf = ...`)?
struct RDIStamp: Injectable, Equatable {
    static var defaultValue: RDIStamp { RDIStamp(label: "missing") }
    var label: String
}

enum RDINested {
    @Reducer struct Leaf {
        struct State { var label: String = "" }
        enum When { case noop }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {}
    }
    @Reducer struct Mid {
        struct State { var value: Int = 0; var readStamp: String = ""; @SubState var leaf: Leaf.State? }
        enum When { case inject(String), read, bump }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .inject(let s): dependencies.inject(RDIStamp(label: s))
            case .read:
                let stamp: RDIStamp? = try? dependencies.resolve()
                state.readStamp = stamp?.label ?? "missing"
            case .bump: state.value += 1
            }
        }
    }
    @Reducer struct Root {
        struct State { @SubState var mid: Mid.State? }
        enum When { case create, replaceLeafThroughMid }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .create:
                var m = Mid.State(); m.leaf = Leaf.State(label: "a"); state.mid = m
            case .replaceLeafThroughMid:
                state.mid?.leaf = Leaf.State(label: "b")
            }
        }
    }
}

final class ReplaceDescendantInjectionTests: XCTestCase {
    func testReplacingALeafThroughTheMiddleRecreatesTheMiddleAndLosesItsInjection() {
        let root = RDINested.Root.Store(initialState: .init())
        root.send(.create)
        let mid1 = root.children.mid!
        mid1.send(.bump)
        mid1.send(.inject("injected"))
        mid1.send(.read)
        XCTAssertEqual(mid1.state.readStamp, "injected", "sanity: the injection resolves before the replacement")

        root.send(.replaceLeafThroughMid)
        let mid2 = root.children.mid!
        mid2.send(.read)

        XCTAssertFalse(mid1 === mid2, "the middle store is recreated")
        XCTAssertEqual(mid2.state.value, 1, "its state is carried over: the new store starts from the parent's copy")
        XCTAssertEqual(mid2.children.leaf?.state.label, "b")
        XCTAssertEqual(mid2.state.readStamp, "missing", "what the old store injected is lost")
    }
}
