//
//  StartView.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

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
        chosen != nil && !riderName.trimmingCharacters(in: .whitespaces).isEmpty
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
                Button("Start trip", action: start)
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

    private func start() {
        guard let chosen else { return }
        store.startTrip(destinationName: chosen.name ?? query, destination: chosen.location)
    }
}
