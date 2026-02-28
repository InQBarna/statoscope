import Statoscope
import SwiftUI

extension Tutorial03 {

    func sendCrashReport(error: any Error) { /* ... */ }

    private struct CounterView: View {

        @StateObject var model = Counter()

        var body: some View {
            VStack {
                Text("\(model.viewDisplaysTotalCount)")
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
