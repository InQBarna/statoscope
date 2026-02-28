import Statoscope

enum Tutorial02 {

    struct DTO: Codable, Equatable {
        let count: Int
    }

    final class CloudCounter: ScopeImplementation {
        var viewDisplaysTotalCount: Int = 0
        var viewShowsLoadingAndDisablesButtons: Bool = false

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case networkPostCompleted(DTO)
        }

        func update(_ when: When) throws {
            switch when {
            case .userTappedIncrementButton:
                viewDisplaysTotalCount = viewDisplaysTotalCount + 1
                viewShowsLoadingAndDisablesButtons = true
                try postNewValueToNetwork(newValue: viewDisplaysTotalCount)

            case .userTappedDecrementButton:
                guard viewDisplaysTotalCount > 0 else {
                    return
                }
                viewDisplaysTotalCount = viewDisplaysTotalCount - 1
                viewShowsLoadingAndDisablesButtons = true
                try postNewValueToNetwork(newValue: viewDisplaysTotalCount)

            case .networkPostCompleted(let remoteCounter):
                viewShowsLoadingAndDisablesButtons = false
                viewDisplaysTotalCount = remoteCounter.count
            }
        }

        private func postNewValueToNetwork(newValue: Int) throws {
        }
    }
}
