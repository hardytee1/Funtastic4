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

    /// Opens Google Maps with turn-by-turn directions in two-wheeler mode (the web page if the app is missing).
    var navigationURL: URL {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(latitude),\(longitude)&travelmode=two-wheeler&dir_action=navigate")!
    }
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
    /// The route to the destination, thinned out (see `RouteShape`); empty when there is none.
    var route: [CLLocationCoordinate2D] = []

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

    /// A short line for tight spaces: the arrival time and how it compares with mine, or why there is none.
    func etaSummary(comparedTo mine: Date?, now: Date) -> String {
        switch status {
        case .arrived: return "Arrived"
        case .stopped: return "Stopped"
        case .moving: break
        }
        if now.timeIntervalSince(updatedAt) > Tuning.staleAfter { return "Not updating" }
        guard let arrival else { return "—" }
        let time = arrival.formatted(date: .omitted, time: .shortened)
        guard let mine else { return time }
        let minutes = Int((arrival.timeIntervalSince(mine) / 60).rounded())
        return minutes == 0 ? "\(time) · same time" : "\(time) · \(minutes > 0 ? "+" : "−")\(abs(minutes)) min"
    }
}
