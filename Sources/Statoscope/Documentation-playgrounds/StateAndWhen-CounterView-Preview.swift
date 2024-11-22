//
//  CounterView.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 22/11/24.
//

import SwiftUI

private struct CounterView: View {
    var body: some View {
        VStack {
            Text("0")
            HStack {
                Button("+") {
                }
                Button("-") {
                }
            }
        }
    }
}

#Preview {
    CounterView()
}