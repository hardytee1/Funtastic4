//
//  StartView.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CloudKit
import MapKit
import SwiftUI

struct StartView: View {
    private let store = TripStore.shared
    @AppStorage(TripStore.nameKey) private var riderName = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searched = false
    @State private var chosen: MKMapItem?

    private var canStart: Bool {
        chosen != nil && !riderName.trimmingCharacters(in: .whitespaces).isEmpty && !store.isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("Name", text: $riderName)
                }
                Section("Destination") {
                    TextField("Search for a place", text: $query)
                        .submitLabel(.search)
                        .onSubmit(search)
                    ForEach(results, id: \.self) { item in
                        Button {
                            chosen = item
                        } label: {
                            HStack {
                                Text(item.name ?? "Place")
                                Spacer()
                                if item == chosen { Image(systemName: "checkmark") }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if searched && results.isEmpty {
                        Text("No places found").foregroundStyle(.secondary)
                    }
                }
                if let error = store.errorText {
                    Text(error).foregroundStyle(.red)
                }
                Button {
                    Task { await start() }
                } label: {
                    if store.isBusy { ProgressView() } else { Text("Start trip") }
                }
                .disabled(!canStart)
            }
            .navigationTitle("New trip")
        }
    }

    private func search() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        Task {
            results = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            searched = true
            chosen = nil
        }
    }

    private func start() async {
        guard let chosen else { return }
        await store.startTrip(destinationName: chosen.name ?? query, destination: chosen.location)
    }
}

/// Shown when a friend opens an invite link: a name, and a clear note that location will be shared.
struct JoinView: View {
    private let store = TripStore.shared
    @AppStorage(TripStore.nameKey) private var riderName = ""

    private var title: String {
        store.invite?.share[CKShare.SystemFieldKey.title] as? String ?? "Join trip"
    }

    private var canJoin: Bool {
        !riderName.trimmingCharacters(in: .whitespaces).isEmpty && !store.isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("Name", text: $riderName)
                }
                Text("Your location is shared with everyone in this trip until you leave it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error = store.errorText {
                    Text(error).foregroundStyle(.red)
                }
                Button {
                    Task { await store.join() }
                } label: {
                    if store.isBusy { ProgressView() } else { Text("Join trip") }
                }
                .disabled(!canJoin)
                Button("Not now", role: .cancel, action: store.declineInvite)
            }
            .navigationTitle(title)
        }
    }
}
