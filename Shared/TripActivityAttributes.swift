//
//  TripActivityAttributes.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import ActivityKit
import Foundation

/// What the Live Activity shows. The app starts and updates it, the widget extension draws it, so both share this file.
nonisolated struct TripActivityAttributes: ActivityAttributes, Hashable {
    nonisolated struct ContentState: Codable, Hashable {
        /// When I arrive, once MapKit has told us.
        var myArrival: Date?
        /// Everyone else in arrival order, already worded for a small space (see `Member.etaSummary`).
        var friends: [Friend]
        /// Set on the last update, so the card can say so before it goes away.
        var arrived = false
    }

    nonisolated struct Friend: Codable, Hashable {
        var id: String
        var name: String
        var summary: String
    }

    var tripName: String
    var destinationName: String
}
