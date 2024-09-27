import Statoscope
import SwiftUI

private struct CounterView: View {

    @StateObject var model = Counter()
        .addMiddleWare { store, when, forward in
            do {
                print("WHEN: \(when)")
                try forward(when)
            } catch {
                sendCrashReport(error)
            }
        }

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
