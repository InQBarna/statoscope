import XCTest
import Statoscope

// A descendant that arrives already populated inside a new subtree (a parent's update assigns a child whose state carries a grandchild)
// is a new store like any other: its `defaultTrigger` fires too. Parity with statoscope-kotlin, which fires every activation.
// The triggers run only after every level's state is committed, so a trigger reading `@SuperState` sees the final tree.
enum NestedDefaultTrigger {
    @Reducer struct Leaf {
        struct State { var started = false; var sawMidValue: Int? = nil; @SuperState var mid: Mid.State }
        enum When { case start }
        static var defaultTrigger: When? { .start }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            state.started = true
            state.sawMidValue = state.mid.value
        }
    }
    @Reducer struct Mid {
        struct State: Injectable {
            static var defaultValue: State { State() }
            var value: Int = 0; var started = false; @SubState var leaf: Leaf.State?
        }
        enum When { case start }
        static var defaultTrigger: When? { .start }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            state.started = true
        }
    }
    @Reducer struct Root {
        struct State { @SubState var mid: Mid.State? }
        enum When { case createPopulated }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            var m = Mid.State(); m.value = 7; m.leaf = Leaf.State(); state.mid = m
        }
    }
}

final class NestedDefaultTriggerTests: XCTestCase {

    func testAPrePopulatedDescendantFiresItsDefaultTrigger() {
        let root = NestedDefaultTrigger.Root.Store(initialState: .init())
        root.send(.createPopulated)
        XCTAssertEqual(root.state.mid?.started, true)
        XCTAssertEqual(root.state.mid?.leaf?.started, true, "the grandchild arrived populated and must fire its own defaultTrigger")
    }

    func testTheNestedTriggerSeesTheCommittedParentState() {
        let root = NestedDefaultTrigger.Root.Store(initialState: .init())
        root.send(.createPopulated)
        XCTAssertEqual(root.state.mid?.leaf?.sawMidValue, 7)
    }
}
