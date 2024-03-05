import Statoscope

private final class Counter: Scope {

    var viewDisplaysTotalCount: Int = 0

    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }

    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount = viewDisplaysTotalCount + 1
        case .userTappedDecrementButton:
            viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
        }
    }
}
