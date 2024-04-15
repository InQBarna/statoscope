import Statoscope

enum Network {
    static func buildURLRequestPosting(dto: DTO) throws -> URLRequest {
        guard let url = URL(string: "http://statoscope.com") else {
            throw InvalidStateError()
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(dto)
        return request
    }
}

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
        effectsState.enqueue(
            AnyEffect {
                let request = try Network.buildURLRequestPosting(dto: DTO(count: self.viewDisplaysTotalCount))
                let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                return When.networkPostCompleted(resDTO)
            }
        )
    }
}
