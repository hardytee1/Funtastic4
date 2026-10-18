//
//  LocationTracker.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CoreLocation

/// Every tuning number in one place.
enum Tuning {
    static let minDistance: CLLocationDistance = 250
    static let minInterval: TimeInterval = 30
    static let maxAccuracy: CLLocationAccuracy = 50
    static let arrivalRadius: CLLocationDistance = 100
    static let routeMaxAge: TimeInterval = 180
    static let staleAfter: TimeInterval = 120
    static let refreshInterval: Duration = .seconds(15)
    static let farAnnounce: CLLocationDistance = 400
    static let nearAnnounce: CLLocationDistance = 80
    static let offRouteDistance: CLLocationDistance = 60
    static let offRouteFixes = 4
    static let rerouteInterval: TimeInterval = 20
    static let stoppedReminderAfter: TimeInterval = 300
    static let heartbeat: TimeInterval = 60
    static let activityRestartAfter: TimeInterval = 7 * 3600
}

/// The last position we published.
struct SentFix {
    var location: CLLocation
    var date: Date
    var wasStationary: Bool
}

enum LocationTracker {
    /// Streams GPS updates until the calling task is cancelled. The background session keeps them
    /// coming with the screen locked or another app open.
    static func run(onUpdate: (CLLocationUpdate) -> Void) async throws {
        let service = CLServiceSession(authorization: .whenInUse)
        let background = CLBackgroundActivitySession()
        defer {
            background.invalidate()
            service.invalidate()
        }
        for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
            onUpdate(update)
        }
    }

    /// Whether this fix should be published. It must be accurate enough, and then it is sent when
    /// it is the first one, when we have arrived, when the rider just stopped, or when the rider is
    /// at least 250 m and 30 s past the last one. Distance is measured from the last sent spot, so
    /// GPS wobble while parked never counts as movement.
    static func shouldSend(_ location: CLLocation, isStationary: Bool, destination: CLLocation,
                           last: SentFix?, now: Date) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Tuning.maxAccuracy else { return false }
        guard let last else { return true }
        if location.distance(from: destination) <= Tuning.arrivalRadius { return true }
        if isStationary { return !last.wasStationary }
        return location.distance(from: last.location) >= Tuning.minDistance
            && now.timeIntervalSince(last.date) >= Tuning.minInterval
    }
}
