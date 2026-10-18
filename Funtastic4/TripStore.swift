//
//  TripStore.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CloudKit
import CoreLocation
import MapKit
import Observation

/// The active trip and the loop that runs on every GPS update: gate, ETA, publish, fetch.
@Observable
final class TripStore {
    static let shared = TripStore()
    static let nameKey = "riderName"
    private static let tripKey = "activeTrip"

    private(set) var trip: Trip?
    private(set) var members: [String: Member] = [:]
    private(set) var myID = ""
    private(set) var invite: CKShare.Metadata?
    private(set) var isBusy = false
    private(set) var locationError: String?
    private(set) var syncError: String?
    private(set) var route: MKPolyline?

    private let cloud = CloudSync()
    private var locationTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var lastSend: SentFix?
    private var retryNotBefore = Date.distantPast
    private var arrivalDate: Date?
    private var routeDate: Date?

    var errorText: String? { locationError ?? syncError }

    var sortedMembers: [Member] {
        members.values.sorted { ($0.arrival ?? .distantFuture, $0.name) < ($1.arrival ?? .distantFuture, $1.name) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.tripKey) {
            trip = try? JSONDecoder().decode(Trip.self, from: data)
        }
    }

    // MARK: Starting, joining and leaving

    func startTrip(destinationName: String, destination: CLLocation) async {
        isBusy = true
        defer { isBusy = false }
        do {
            begin(try await cloud.createTrip(name: "Trip to \(destinationName)", destinationName: destinationName,
                                             destination: destination))
        } catch {
            syncError = describe(error)
        }
    }

    func receiveInvite(_ metadata: CKShare.Metadata) {
        invite = metadata
    }

    func declineInvite() {
        invite = nil
    }

    func join() async {
        guard let invite else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let trip = try await cloud.accept(invite)
            self.invite = nil
            begin(trip)
        } catch {
            syncError = describe(error)
        }
    }

    /// Called on launch: picks a saved trip back up.
    func resume() {
        if trip != nil, locationTask == nil { startTracking() }
    }

    /// The host ends the trip for everyone; a member just leaves.
    func endTrip() async {
        guard let trip else { return }
        do {
            try await cloud.leave(trip, memberID: myID)
        } catch where !isTripGone(error) {
            syncError = describe(error)
            return
        } catch {}
        clearTrip()
    }

    private func begin(_ trip: Trip) {
        clearTrip()
        cloud.reset()
        self.trip = trip
        UserDefaults.standard.set(try? JSONEncoder().encode(trip), forKey: Self.tripKey)
        startTracking()
    }

    private func clearTrip() {
        stopTracking()
        sendTask?.cancel()
        sendTask = nil
        trip = nil
        members = [:]
        locationError = nil
        syncError = nil
        lastSend = nil
        retryNotBefore = .distantPast
        arrivalDate = nil
        route = nil
        routeDate = nil
        UserDefaults.standard.removeObject(forKey: Self.tripKey)
    }

    // MARK: Location loop

    private func startTracking() {
        locationTask?.cancel()
        locationTask = Task {
            do {
                try await LocationTracker.run(onUpdate: handle)
            } catch {
                if !Task.isCancelled { locationError = "Location stopped: \(error.localizedDescription)" }
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
            locationError = "Location access is off. Turn it on in Settings > Privacy & Security > Location Services."
            return
        }
        locationError = nil
        guard sendTask == nil, Date.now >= retryNotBefore, let location = update.location,
              LocationTracker.shouldSend(location, isStationary: update.stationary, destination: trip.destination,
                                         last: lastSend, now: .now)
        else { return }
        sendTask = Task { await send(location, isStationary: update.stationary, to: trip) }
    }

    private func send(_ location: CLLocation, isStationary: Bool, to trip: Trip) async {
        defer { if !Task.isCancelled { sendTask = nil } }
        await refreshRoute(from: location, to: trip)
        do {
            try await ensureMyID()
            let arrived = location.distance(from: trip.destination) <= Tuning.arrivalRadius
            let member = Member(id: myID, name: myName, location: location, speed: max(location.speed, 0),
                                heading: max(location.course, 0), arrival: arrived ? .now : arrivalDate,
                                updatedAt: .now, status: arrived ? .arrived : (isStationary ? .stopped : .moving))
            try await cloud.save(member, in: trip)
            guard self.trip == trip else { return }
            members[member.id] = member
            lastSend = SentFix(location: location, date: .now, wasStationary: isStationary)
            if arrived {
                stopTracking()
                route = nil
            }
        } catch {
            guard self.trip == trip else { return }
            retryNotBefore = .now.addingTimeInterval(Tuning.minInterval)
            fail(error)
            return
        }
        await refresh()
    }

    /// MapKit does the whole calculation: one request gives the route line and the ETA. We only ask again
    /// when the last answer is over 3 minutes old, which also redraws the line if the rider left it.
    private func refreshRoute(from location: CLLocation, to trip: Trip) async {
        if let routeDate, Date.now.timeIntervalSince(routeDate) < Tuning.routeMaxAge { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: location, address: nil)
        request.destination = MKMapItem(location: trip.destination, address: nil)
        request.transportType = .automobile
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return }
        arrivalDate = .now.addingTimeInterval(route.expectedTravelTime)
        self.route = route.polyline
        routeDate = .now
    }

    // MARK: Group state

    /// Pulls everyone's latest position from the trip zone.
    func refresh() async {
        guard let trip else { return }
        do {
            let changes = try await cloud.changes(in: trip)
            guard self.trip == trip else { return }
            for member in changes.members { members[member.id] = member }
            for id in changes.deleted { members[id] = nil }
            syncError = nil
        } catch {
            guard self.trip == trip else { return }
            fail(error)
        }
    }

    private func ensureMyID() async throws {
        if myID.isEmpty { myID = try await cloud.memberID() }
    }

    private var myName: String {
        let name = UserDefaults.standard.string(forKey: Self.nameKey)?.trimmingCharacters(in: .whitespaces)
        return name?.isEmpty == false ? name! : "Rider"
    }

    // MARK: Errors

    private func fail(_ error: Error) {
        if isTripGone(error) {
            clearTrip()
            syncError = "The trip has ended."
        } else {
            syncError = describe(error)
        }
    }

    private func isTripGone(_ error: Error) -> Bool {
        guard let code = (error as? CKError)?.code else { return false }
        return code == .zoneNotFound || code == .userDeletedZone
    }

    private func describe(_ error: Error) -> String {
        switch (error as? CKError)?.code {
        case .notAuthenticated: "Sign in to iCloud in Settings to share a trip."
        case .networkUnavailable, .networkFailure: "Can't reach iCloud. Will retry."
        default: "iCloud error: \(error.localizedDescription)"
        }
    }
}
