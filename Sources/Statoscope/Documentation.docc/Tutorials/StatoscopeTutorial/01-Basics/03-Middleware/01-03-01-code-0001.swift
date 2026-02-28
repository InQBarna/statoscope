import Statoscope

enum Tutorial03 {

    final class Counter: Statostore, ObservableObject {

        @Published var viewDisplaysTotalCount: Int = 0

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case errorCase  // Will throw an error
        }

        func update(_ when: When) throws {
        }
    }
}
