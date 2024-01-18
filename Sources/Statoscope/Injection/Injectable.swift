//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

protocol Injectable {
    static var defaultValue: Self { get }
}

public struct NoInjectedValueFound: Error {
    let type: String
    init<T>(_ type: T) {
        self.type = String(describing: type).removeOptionalDescription
    }
}

public struct ReadOnlyInjectionProperty: Error { }

