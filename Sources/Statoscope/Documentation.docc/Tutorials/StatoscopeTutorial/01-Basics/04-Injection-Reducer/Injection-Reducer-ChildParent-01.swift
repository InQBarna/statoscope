@Reducer
struct ChildCounter {
    struct State {
        var value: Int = 0
        // Child also declares the same dependency — resolved from parent's tree
        @ReducerInjected var logger: AuditLogger
    }

    enum When {
        case add(Int)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .add(let n):
            state.logger.log("child add \(n)")
            state.value += n
        }
    }
}

@Reducer
struct ParentWithChild {
    struct State {
        var label: String = ""
        @ReducerInjected var logger: AuditLogger
        @SubState var child: ChildCounter.State?
    }

    enum When {
        case labelChanged(String)
        case openChild
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .labelChanged(let text):
            state.logger.log("label: \(text)")
            state.label = text

        case .openChild:
            state.logger.log("opening child")
            state.child = ChildCounter.State()
        }
    }
}
