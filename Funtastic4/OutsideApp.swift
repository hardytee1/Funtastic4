//
//  OutsideApp.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import ActivityKit
import Foundation
import UserNotifications

/// What the rider sees outside the app: the Live Activity, and a reminder when sharing stops.
///
/// While the rider is moving, the reminder is scheduled a few minutes ahead and pushed back every time we hear
/// from the phone, so it only goes off if updates stop (for instance after the app is swiped away). The Live
/// Activity gets the same "stale" time. While parked nothing is expected, so both are cleared.
final class OutsideApp {
    private static let reminderID = "sharing-stopped"
    private static let startedKey = "activityStartedAt"

    private var activity: Activity<TripActivityAttributes>?
    private var isActive = false
    private var lastState: TripActivityAttributes.ContentState?
    private var lastMoving = false
    private var lastPush = Date.distantPast

    /// Makes sure a Live Activity is running for this trip: starts one, picks up the one an earlier run left behind
    /// (it may have turned stale), or starts over before iOS's 8 hour limit. Only an app on screen may start one.
    func ensureRunning(for trip: Trip, myArrival: Date?, friends: [Member]) {
        isActive = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = TripActivityAttributes(tripName: trip.name, destinationName: trip.destinationName)
        for other in Activity<TripActivityAttributes>.activities where other.attributes != attributes {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        activity = activity ?? Activity<TripActivityAttributes>.activities.first { $0.attributes == attributes }

        let startedAt = UserDefaults.standard.object(forKey: Self.startedKey) as? Date ?? .distantPast
        let state = Self.state(myArrival: myArrival, friends: friends)
        if let activity, Date.now.timeIntervalSince(startedAt) < Tuning.activityRestartAfter {
            switch activity.activityState {
            case .dismissed:
                return  // the rider swiped it away; leave it
            case .active, .stale, .pending:
                push(state, moving: lastMoving, force: true)
                return
            default:
                break  // ended: start over below
            }
        }
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        UserDefaults.standard.set(Date.now, forKey: Self.startedKey)
    }

    /// New numbers to show.
    func update(myArrival: Date?, friends: [Member], moving: Bool) {
        push(Self.state(myArrival: myArrival, friends: friends), moving: moving, force: false)
    }

    /// Called on every GPS fix: all it does is keep the reminder and the stale time pushed back.
    func heartbeat(moving: Bool) {
        guard let lastState, moving != lastMoving || Date.now.timeIntervalSince(lastPush) >= Tuning.heartbeat else { return }
        push(lastState, moving: moving, force: true)
    }

    /// Ends the Live Activity and the reminder. On arrival the card stays a few minutes saying so.
    func end(arrived: Bool = false, myArrival: Date? = nil, friends: [Member] = []) {
        isActive = false
        lastState = nil
        cancelReminder()
        UserDefaults.standard.removeObject(forKey: Self.startedKey)
        guard let activity else { return }
        self.activity = nil
        Task {
            if arrived {
                var state = Self.state(myArrival: myArrival, friends: friends)
                state.arrived = true
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(300)))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func push(_ state: TripActivityAttributes.ContentState, moving: Bool, force: Bool) {
        let now = Date.now
        guard isActive, force || state != lastState || moving != lastMoving || now.timeIntervalSince(lastPush) >= Tuning.heartbeat else { return }
        lastState = state
        lastMoving = moving
        lastPush = now
        if moving { scheduleReminder() } else { cancelReminder() }
        guard let activity else { return }
        let staleDate = moving ? now.addingTimeInterval(Tuning.stoppedReminderAfter) : nil
        Task { await activity.update(ActivityContent(state: state, staleDate: staleDate)) }
    }

    private func scheduleReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Location sharing stopped"
        content.body = "Open Funtastic4 so your friends can see you again."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Tuning.stoppedReminderAfter, repeats: false)
        // The same id every time, so each call replaces the pending reminder instead of adding another.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
    }

    private func cancelReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.reminderID])
    }

    private static func state(myArrival: Date?, friends: [Member]) -> TripActivityAttributes.ContentState {
        let now = Date.now
        return TripActivityAttributes.ContentState(
            myArrival: myArrival,
            friends: friends.prefix(6).map {
                TripActivityAttributes.Friend(id: $0.id, name: $0.name, summary: $0.etaSummary(comparedTo: myArrival, now: now))
            })
    }
}
