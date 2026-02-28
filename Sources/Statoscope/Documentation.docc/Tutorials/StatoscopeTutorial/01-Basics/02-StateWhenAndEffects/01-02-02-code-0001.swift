import Statoscope

enum Tutorial02b {

    enum Network {
        struct Effect<Response: Decodable>: Statoscope.Effect, Equatable {
            let request: URLRequest
            func runEffect() async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }
        }
    }
}
