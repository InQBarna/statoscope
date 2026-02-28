import Statoscope

enum Tutorial02b {

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

        struct Effect<Response: Decodable>: Statoscope.Effect, Equatable {
            let request: URLRequest
            func runEffect() async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }
        }
    }

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
            // Solution 1: Cancel any previous
            effectsState.cancelEffect { $0 is Network.Effect<DTO> }
            // Solution 2: do nothing if an effect is already running
            guard nil == effects.first(where: { $0 is Network.Effect<DTO> }) else {
                throw InvalidStateError()
            }

            effectsState.enqueue(
                Network.Effect<DTO>(request: try Network.buildURLRequestPosting(dto: DTO(count: newValue)))
                    .map(When.networkPostCompleted)
            )
        }
    }
}
