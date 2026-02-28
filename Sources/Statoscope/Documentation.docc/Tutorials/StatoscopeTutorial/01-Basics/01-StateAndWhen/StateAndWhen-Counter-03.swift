import Statoscope

enum Tutorial0101 {

    final class Counter: Statostore, ObservableObject {

        @Published var viewDisplaysTotalCount: Int = 0

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
        }
    }
}
