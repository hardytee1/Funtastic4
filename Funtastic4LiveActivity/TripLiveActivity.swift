//
//  TripLiveActivity.swift
//  Funtastic4LiveActivity
//
//  Created by Hardy Tee on 18/10/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.destinationName, systemImage: "flag.checkered")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MyArrival(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FriendRows(friends: context.state.friends, limit: 3, muted: context.isStale)
                }
            } compactLeading: {
                Image(systemName: "flag.checkered")
            } compactTrailing: {
                if context.state.arrived {
                    Image(systemName: "checkmark")
                } else if let arrival = context.state.myArrival {
                    Text(arrival, style: .time)
                }
            } minimal: {
                Image(systemName: "flag.checkered")
            }
        }
    }
}
