//
//  TripStore.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CoreLocation
import MapKit
import Observation

/// The active trip and the loop that runs on every GPS update: gate, ETA, publish.
@Observable
final class TripStore {
    static let shared = TripStore()
    static let nameKey = "riderName"
    private static let tripKey = "activeTrip"

    private(set) var trip: Trip?
    private(set) var members: [String: Member] = [:]
    private(set) var errorText: String?
    let myID = "me"

    private var locationTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var lastSend: SentFix?
    private var arrivalDate: Date?
    private var etaDate: Date?

    var sortedMembers: [Member] {
        members.values.sorted { ($0.arrival ?? .distantFuture, $0.name) < ($1.arrival ?? .distantFuture, $1.name) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.tripKey) {
            trip = try? JSONDecoder().decode(Trip.self, from: data)
        }
    }

    func startTrip(destinationName: String, destination: CLLocation) {
        endTrip()
        let trip = Trip(name: "Trip to \(destinationName)", destinationName: destinationName,
                        latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
        self.trip = trip
        UserDefaults.standard.set(try? JSONEncoder().encode(trip), forKey: Self.tripKey)
        startTracking()
    }

    /// Called on launch: picks a saved trip back up.
    func resume() {
        if trip != nil, locationTask == nil { startTracking() }
    }

    func endTrip() {
        stopTracking()
        sendTask?.cancel()
        sendTask = nil
        trip = nil
        members = [:]
        errorText = nil
        lastSend = nil
        arrivalDate = nil
        etaDate = nil
        UserDefaults.standard.removeObject(forKey: Self.tripKey)
    }

    private func startTracking() {
        locationTask?.cancel()
        locationTask = Task {
            do {
                try await LocationTracker.run(onUpdate: handle)
            } catch {
                if !Task.isCancelled { errorText = "Location stopped: \(error.localizedDescription)" }
            }
        }
    }

    private func stopTracking() {
        locationTask?.cancel()
        locationTask = nil
    }

    private func handle(_ update: CLLocationUpdate) {
        guard let trip else { return }
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            errorText = "Location access is off. Turn it on in Settings > Privacy & Security > Location Services."
            return
        }
        guard sendTask == nil, let location = update.location,
              LocationTracker.shouldSend(location, isStationary: update.stationary, destination: trip.destination,
                                         last: lastSend, now: .now)
        else { return }
        sendTask = Task { await send(location, isStationary: update.stationary, to: trip) }
    }

    private func send(_ location: CLLocation, isStationary: Bool, to trip: Trip) async {
        defer { if !Task.isCancelled { sendTask = nil } }
        await refreshETA(from: location, to: trip)
        guard !Task.isCancelled else { return }

        let arrived = location.distance(from: trip.destination) <= Tuning.arrivalRadius
        members[myID] = Member(id: myID, name: myName, location: location, speed: max(location.speed, 0),
                               heading: max(location.course, 0), arrival: arrived ? .now : arrivalDate,
                               updatedAt: .now, status: arrived ? .arrived : (isStationary ? .stopped : .moving))
        lastSend = SentFix(location: location, date: .now, wasStationary: isStationary)
        errorText = nil
        if arrived { stopTracking() }
    }

    /// MapKit does the whole calculation; we only ask again when the last answer is over 3 minutes old.
    private func refreshETA(from location: CLLocation, to trip: Trip) async {
        if let etaDate, Date.now.timeIntervalSince(etaDate) < Tuning.etaMaxAge { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: location, address: nil)
        request.destination = MKMapItem(location: trip.destination, address: nil)
        request.transportType = .automobile
        guard let response = try? await MKDirections(request: request).calculateETA() else { return }
        arrivalDate = response.expectedArrivalDate
        etaDate = .now
    }

    private var myName: String {
        let name = UserDefaults.standard.string(forKey: Self.nameKey)?.trimmingCharacters(in: .whitespaces)
        return name?.isEmpty == false ? name! : "Rider"
    }
}
