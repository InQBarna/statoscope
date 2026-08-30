@Reducer
struct AuditedCounter {
    struct State {
        var count: Int = 0
        var lastMessage: String = ""

        /// Dependency declared once on State.
        /// The @Reducer macro generates injection in the Store's state getter.
        @ReducerInjected var logger: AuditLogger
    }

    enum When {
        case increment
        case decrement
        case reset
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .increment:
            let msg = "increment: \(state.count) → \(state.count + 1)"
            state.logger.log(msg)
            state.lastMessage = msg
            state.count += 1

        case .decrement:
            let msg = "decrement: \(state.count) → \(state.count - 1)"
            state.logger.log(msg)
            state.lastMessage = msg
            state.count -= 1

        case .reset:
            let msg = "reset"
            state.logger.log(msg)
            state.lastMessage = msg
            state.count = 0
        }
    }
}
