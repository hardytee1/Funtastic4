//
//  TripMapView.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import MapKit
import SwiftUI

struct TripMapView: View {
    private let store = TripStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmEnd = false
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        if let trip = store.trip {
            NavigationStack {
                VStack(spacing: 0) {
                    map(for: trip)
                    memberList
                        .frame(height: 240)
                }
                .navigationTitle(trip.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Link(destination: trip.navigationURL) {
                            Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond")
                        }
                        if let url = trip.shareURL {
                            ShareLink(item: url, message: Text("Join my trip to \(trip.destinationName)"))
                        }
                        Button(trip.isOwner ? "End" : "Leave", role: .destructive) { confirmEnd = true }
                    }
                }
                .confirmationDialog(trip.isOwner ? "End this trip for everyone?" : "Leave this trip?",
                                    isPresented: $confirmEnd, titleVisibility: .visible) {
                    Button(trip.isOwner ? "End trip" : "Leave trip", role: .destructive) {
                        Task { await store.endTrip() }
                    }
                }
                // While the app is on screen, also check for friends' updates every 15 s.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await store.refresh()
                        try? await Task.sleep(for: Tuning.refreshInterval)
                    }
                }
            }
        }
    }

    private func map(for trip: Trip) -> some View {
        Map(position: $position) {
            if let route = store.route {
                MapPolyline(route).stroke(.blue, lineWidth: 5)
            }
            UserAnnotation()
            Marker(trip.destinationName, systemImage: "flag.checkered", coordinate: trip.destination.coordinate)
            ForEach(store.sortedMembers.filter { $0.id != store.myID }) { member in
                Annotation(member.name, coordinate: member.location.coordinate) {
                    Circle()
                        .fill(.tint)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    private var memberList: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            List {
                if let error = store.errorText {
                    Text(error).foregroundStyle(.red)
                }
                if store.members.isEmpty {
                    Text("Waiting for your first location…").foregroundStyle(.secondary)
                }
                ForEach(store.sortedMembers) { member in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(member.id == store.myID ? "\(member.name) (you)" : member.name)
                            Text(member.statusText(now: context.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let arrival = member.arrival {
                            VStack(alignment: .trailing) {
                                Text(arrival, style: .time)
                                Text(arrival, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
