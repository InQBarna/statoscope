import Statoscope

struct DTO: Codable {
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

    func update(_ when: When) throws {}
}
