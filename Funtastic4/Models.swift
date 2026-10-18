//
//  Models.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CoreLocation
import Foundation

struct Trip: Codable, Equatable {
    var zoneName: String
    var ownerName: String
    var isOwner: Bool
    var shareURL: URL?
    var name: String
    var destinationName: String
    var latitude: Double
    var longitude: Double

    var destination: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

struct Member: Identifiable {
    enum Status: String {
        case moving, stopped, arrived
    }

    var id: String
    var name: String
    var location: CLLocation
    var speed: Double
    var heading: Double
    var arrival: Date?
    var updatedAt: Date
    var status: Status

    func statusText(now: Date) -> String {
        let time = updatedAt.formatted(date: .omitted, time: .shortened)
        switch status {
        case .arrived:
            return "Arrived \(time)"
        case .stopped:
            return "Stopped since \(time)"
        case .moving:
            return now.timeIntervalSince(updatedAt) > Tuning.staleAfter ? "Not updating · last seen \(time)" : "Moving"
        }
    }
}
