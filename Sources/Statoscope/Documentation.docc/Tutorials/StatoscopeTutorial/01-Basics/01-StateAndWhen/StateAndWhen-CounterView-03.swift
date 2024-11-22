import Statoscope
import SwiftUI

struct CounterView: View {
    @ObservedObject var model = Counter()
    var body: some View {
        CounterViewDecoupled(
            viewDisplaysTotalCount: "\(model.viewDisplaysTotalCount)",
            action: { model.send($0) }
        )
    }
}

struct CounterViewDecoupled: View {
    let viewDisplaysTotalCount: String
    let action: (Counter.When) -> Void
    var body: some View {
        VStack {
            Text(viewDisplaysTotalCount)
            HStack {
                Button("+") {
                    action(.userTappedIncrementButton)
                }
                Button("-") {
                    action(.userTappedDecrementButton)
                }
            }
        }
    }
}
