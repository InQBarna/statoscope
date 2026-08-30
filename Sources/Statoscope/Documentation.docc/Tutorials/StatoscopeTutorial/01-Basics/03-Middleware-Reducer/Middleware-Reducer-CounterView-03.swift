@_spi(Internal) @testable import Statoscope
import SwiftUI

extension Tutorial03Reducer {

    static func sendCrashReport(error: any Error) { /* ... */ }

    private struct CounterView: View {

        @StateObject var model = CounterReducer.Store(initialState: CounterReducer.State())
            .addMiddleWare { store, when, forward in
                do {
                    print("WHEN: \(when)")
                    try forward(when)
                } catch {
                    Tutorial03Reducer.sendCrashReport(error: error)
                }
            }

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
