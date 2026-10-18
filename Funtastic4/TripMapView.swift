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

    private var navigator: Navigator { store.navigator }

    var body: some View {
        if let trip = store.trip {
            NavigationStack {
                VStack(spacing: 0) {
                    map(for: trip)
                        .safeAreaInset(edge: .top) { turnBanner }
                    if navigator.isActive {
                        navigationBar
                    } else {
                        memberList
                            .frame(height: 240)
                    }
                }
                .navigationTitle(trip.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarVisibility(navigator.isActive ? .hidden : .visible, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button("Start navigation", systemImage: "location.north.line", action: store.startNavigation)
                                .disabled(store.route == nil)
                            Link(destination: trip.navigationURL) {
                                Label("Open in Google Maps", systemImage: "arrow.up.forward.app")
                            }
                        } label: {
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
                // Navigating follows the rider and turns the map to their heading; otherwise show the whole trip.
                .onChange(of: navigator.isActive) { _, active in
                    position = active ? .userLocation(followsHeading: true, fallback: .automatic) : .automatic
                }
            }
        }
    }

    private func map(for trip: Trip) -> some View {
        Map(position: $position) {
            if let route = store.route {
                MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
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

    /// The next turn: how far and what to do.
    @ViewBuilder private var turnBanner: some View {
        if navigator.isActive {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let guidance = navigator.guidance {
                    Text(roadDistance(guidance.distanceToTurn))
                        .font(.title.bold())
                    Text(guidance.instruction)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Finding your route…")
                        .font(.headline)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    /// Arrival time and distance left, with mute and stop.
    private var navigationBar: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading) {
                if let arrival = store.arrivalDate {
                    Text(arrival, style: .time)
                        .font(.title2.bold())
                    Text(arrival, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let guidance = navigator.guidance {
                    Text(roadDistance(guidance.remaining))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                navigator.isMuted.toggle()
            } label: {
                Image(systemName: navigator.isMuted ? "speaker.slash" : "speaker.wave.2")
            }
            .accessibilityLabel(navigator.isMuted ? "Unmute voice" : "Mute voice")
            Button("Stop", role: .destructive, action: navigator.stop)
        }
        .padding()
        .background(.bar)
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
