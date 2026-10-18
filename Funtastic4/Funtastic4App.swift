//
//  Funtastic4App.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import SwiftUI

@main
struct Funtastic4App: App {
    private let store = TripStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if store.trip != nil {
                    TripMapView()
                } else {
                    StartView()
                }
            }
            .task { store.resume() }
        }
    }
}
