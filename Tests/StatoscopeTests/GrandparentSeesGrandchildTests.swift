import XCTest
import Statoscope

// A grandparent's `state` must carry the whole live tree below it, not only its direct children's
// own fields: `state.child?.grandchild` is what a reducer reads to react to a descendant.
// (Kotlin mirrors descendants up to the root; PARITY_AUDIT.md Issue 17 and 21.)
//
// `state` is `_treeState` (own state plus every live descendant) plus what is injected from above; a parent embeds a child's `_treeState`,
// never its `state`, so `@SuperState` (child -> parent's `state`) and the embedding (parent -> child's `_treeState`) never recurse into each other.

// Reassigning an existing child by copying it keeps its grandchild inside the copied value; the state and the stores must stay consistent.
enum CopyReassign {
    @Reducer struct Leaf {
        struct State { var label: String = "" }
        enum When { case noop }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {}
    }
    @Reducer struct Mid {
        struct State { var value: Int = 0; @SubState var leaf: Leaf.State? }
        enum When { case noop }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {}
    }
    @Reducer struct Root {
        struct State { @SubState var mid: Mid.State? }
        enum When { case create, copyMidAndBump }
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .create:
                var m = Mid.State(); m.leaf = Leaf.State(label: "a"); state.mid = m
            case .copyMidAndBump:
                var m = state.mid!      // carries the grandchild's state, injected from the live tree
                m.value += 1
                state.mid = m
            }
        }
    }
}

final class GrandparentSeesGrandchildTests: XCTestCase {

    func testParentStateIncludesAGrandchildCreatedInOneUpdate() {
        let parent = DeepHierarchy.ParentReducer.Store(initialState: .init())
        parent.send(.createChildWithGrandchild)
        XCTAssertNotNil(parent.state.child?.grandchild)
    }

    func testParentStateIncludesAGrandchildCreatedByTheChildsOwnUpdate() {
        let parent = DeepHierarchy.ParentReducer.Store(initialState: .init())
        parent.send(.createChild)
        parent.children.child?.send(.openGrandchild)
        XCTAssertNotNil(parent.children.child?.children.grandchild, "sanity: the grandchild store exists")
        XCTAssertNotNil(parent.state.child?.grandchild, "the grandparent's state must see it too")
    }

    func testParentStateTracksAGrandchildsLaterChanges() {
        let parent = DeepHierarchy.ParentReducer.Store(initialState: .init())
        parent.send(.createChildWithGrandchild)
        parent.children.child?.children.grandchild?.send(.setLabel("changed"))
        XCTAssertEqual(parent.state.child?.grandchild?.label, "changed")
    }

    func testReassigningAChildCopiedWithItsGrandchildKeepsStateAndStoresConsistent() {
        let root = CopyReassign.Root.Store(initialState: .init())
        root.send(.create)
        let mid1 = root.children.mid!
        XCTAssertNotNil(mid1.children.leaf, "sanity: the grandchild store exists")

        root.send(.copyMidAndBump)
        let mid2 = root.children.mid!

        XCTAssertFalse(mid1 === mid2, "the child store is recreated")
        XCTAssertEqual(mid2.state.value, 1)
        let stateHasLeaf = mid2.state.leaf != nil
        let storeHasLeaf = mid2.children.leaf != nil
        XCTAssertEqual(stateHasLeaf, storeHasLeaf, "the recreated child's state says leaf=\(stateHasLeaf) but its stores say leaf=\(storeHasLeaf)")
        XCTAssertEqual(root.state.mid?.leaf != nil, storeHasLeaf, "the root's view of the tree disagrees with the stores")
    }
}
