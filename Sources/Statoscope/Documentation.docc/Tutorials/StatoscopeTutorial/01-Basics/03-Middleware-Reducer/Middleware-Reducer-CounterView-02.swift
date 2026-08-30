@_spi(Internal) @testable import Statoscope
import SwiftUI

extension Tutorial03Reducer {

    static func sendCrashReport(error: any Error) { /* ... */ }

    private struct CounterView: View {

        @StateObject var model = CounterReducer.Store(initialState: CounterReducer.State())

        var body: some View {
            VStack {
                Text("\(model.state.viewDisplaysTotalCount)")
                HStack {
                    Button("+") {
                        model.send(.userTappedIncrementButton)
                    }
                    Button("-") {
                        model.send(.userTappedDecrementButton)
                    }
                }
            }
        }
    }

}
