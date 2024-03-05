import Statoscope

private final class Counter: Scope {

    var viewDisplaysTotalCount: Int = 0

    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }
}
