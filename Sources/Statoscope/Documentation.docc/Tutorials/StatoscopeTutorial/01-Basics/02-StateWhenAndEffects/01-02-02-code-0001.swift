import Statoscope

extension Network {
    struct Effect<Response: Decodable>: Effect {
        let request: URLRequest
        func runEffect() async throws -> Response {
            try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
        }
    }
}
