//
//  Item.swift
//  CubeFlow
//
//  Created by Paul Sun on 3/2/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date = Date.now
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
