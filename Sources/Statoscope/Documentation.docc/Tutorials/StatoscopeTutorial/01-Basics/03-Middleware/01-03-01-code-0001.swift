import Statoscope

private final class Counter: Scope, ObservableObject {

    @Published var viewDisplaysTotalCount: Int = 0

    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }

    func update(_ when: When) throws {
        /* ... */
    }
}
