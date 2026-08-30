@_spi(Internal) @testable import Statoscope

/// Tutorial 02: CloudCounter with State, When and Effects using Reducer pattern
enum Tutorial02Reducer {

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

    struct DTO: Codable, Equatable {
        let count: Int
    }

    @Reducer
    struct CloudCounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
            var viewShowsLoadingAndDisablesButtons: Bool = false
        }

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case networkPostCompleted(DTO)
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
        }

        private static func postNewValueToNetwork(newValue: Int, effectsState: inout EffectsState<When>) throws {
        }
    }
}
