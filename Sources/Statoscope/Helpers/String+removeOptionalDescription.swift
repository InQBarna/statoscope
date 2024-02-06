//
//  String+removeOptionalDescription.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

extension String {
    var removeOptionalDescription: String {
        if let minusIdx = self.firstIndex(of: "<"),
           self[self.startIndex...minusIdx] == "Optional<",
           self.last == ">" {
            return String(self[index(after: minusIdx)..<index(before: endIndex)])
        }
        return self
    }
}
