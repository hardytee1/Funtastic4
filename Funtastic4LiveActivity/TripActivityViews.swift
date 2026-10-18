//
//  TripActivityViews.swift
//  Funtastic4LiveActivity
//
//  Created by Hardy Tee on 18/10/26.
//

import SwiftUI

/// The Lock Screen card: where I am heading and when I arrive, then everyone else's arrival.
struct TripLockScreenView: View {
    var attributes: TripActivityAttributes
    var state: TripActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(attributes.destinationName, systemImage: "flag.checkered")
                    .font(.headline)
                Spacer()
                MyArrival(state: state, isStale: isStale)
            }
            if isStale {
                Label("Sharing stopped. Open Funtastic4 to resume.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            FriendRows(friends: state.friends, limit: 4, muted: isStale)
        }
        .padding()
    }
}

/// My arrival time. The countdown under it keeps running by itself between updates.
struct MyArrival: View {
    var state: TripActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        VStack(alignment: .trailing) {
            if state.arrived {
                Text("Arrived")
                    .font(.title2.bold())
            } else if let arrival = state.myArrival {
                Text(arrival, style: .time)
                    .font(.title2.bold())
                Text(arrival, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Finding route…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isStale ? 0.5 : 1)
    }
}

/// One line per friend: their color, name and arrival summary.
struct FriendRows: View {
    var friends: [TripActivityAttributes.Friend]
    var limit: Int
    var muted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(friends.prefix(limit), id: \.id) { friend in
                HStack(spacing: 8) {
                    Circle()
                        .fill(PersonColor.color(for: friend.id))
                        .frame(width: 10, height: 10)
                    Text(friend.name)
                        .font(.subheadline)
                    Spacer()
                    Text(friend.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if friends.count > limit {
                Text("+\(friends.count - limit) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(muted ? 0.5 : 1)
    }
}
