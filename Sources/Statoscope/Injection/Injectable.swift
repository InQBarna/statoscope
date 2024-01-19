//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

public protocol Injectable {
    static var defaultValue: Self { get }
}
