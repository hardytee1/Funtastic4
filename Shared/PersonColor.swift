//
//  PersonColor.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import SwiftUI

/// A color per person, the same on every phone and in the Live Activity (blue is kept for "me").
enum PersonColor {
    static func color(for id: String) -> Color {
        let palette: [Color] = [.red, .orange, .purple, .pink, .teal, .indigo, .brown, .mint]
        return palette[id.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % palette.count }]
    }
}
