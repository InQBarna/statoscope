//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope

extension StoreProtocol {
    public static func GIVEN(_ builder: @escaping () throws -> Self) rethrows -> StoreTestPlan<Self> {
        StoreTestPlan(given: builder)
    }
}
