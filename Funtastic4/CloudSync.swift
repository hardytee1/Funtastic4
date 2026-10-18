//
//  CloudSync.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CloudKit
import CoreLocation

/// All CloudKit access. The host's private database owns the trip zone; everyone else reaches the same
/// zone through their shared database. Each person only ever overwrites their own `Member` record.
final class CloudSync {
    private enum SyncError: Error {
        case noShareLink, badTrip
    }

    private lazy var container = CKContainer(identifier: "iCloud.com.hardy.Funtastic4")
    private var changeToken: CKServerChangeToken?

    func memberID() async throws -> String {
        "member-" + (try await container.userRecordID().recordName)
    }

    /// Creates the zone and the `Trip` record, and a zone-wide share anyone with the link can join.
    func createTrip(name: String, destinationName: String, destination: CLLocation) async throws -> Trip {
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "trip-\(UUID().uuidString)")
        let (zoneResults, _) = try await database.modifyRecordZones(saving: [zone], deleting: [])
        try zoneResults.values.forEach { _ = try $0.get() }

        let record = CKRecord(recordType: "Trip", recordID: CKRecord.ID(recordName: "trip", zoneID: zone.zoneID))
        record["name"] = name
        record["destinationName"] = destinationName
        record.encryptedValues["destination"] = destination
        try await save([record], in: database)

        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = name
        share.publicPermission = .readWrite
        guard let url = (try await save([share], in: database).first as? CKShare)?.url else { throw SyncError.noShareLink }

        return Trip(zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, isOwner: true, shareURL: url,
                    name: name, destinationName: destinationName,
                    latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
    }

    func accept(_ metadata: CKShare.Metadata) async throws -> Trip {
        _ = try await container.accept(metadata)
        let tripID = CKRecord.ID(recordName: "trip", zoneID: metadata.share.recordID.zoneID)
        let record = try await container.sharedCloudDatabase.record(for: tripID)
        guard let trip = Trip(record: record, shareURL: metadata.share.url) else { throw SyncError.badTrip }
        return trip
    }

    func save(_ member: Member, in trip: Trip) async throws {
        let record = CKRecord(recordType: "Member", recordID: CKRecord.ID(recordName: member.id, zoneID: zoneID(trip)))
        record["name"] = member.name
        record.encryptedValues["location"] = member.location
        record["speed"] = member.speed
        record["heading"] = member.heading
        record["arrival"] = member.arrival
        record["updatedAt"] = member.updatedAt
        record["status"] = member.status.rawValue
        try await save([record], in: database(trip))
    }

    /// Everything that changed in the zone since the last call (the first call returns everything).
    func changes(in trip: Trip) async throws -> (members: [Member], deleted: [String]) {
        var members: [Member] = []
        var deleted: [String] = []
        var more = true
        while more {
            let result = try await database(trip).recordZoneChanges(inZoneWith: zoneID(trip), since: changeToken)
            for case .success(let change) in result.modificationResultsByID.values {
                if let member = Member(record: change.record) { members.append(member) }
            }
            deleted += result.deletions.filter { $0.recordType == "Member" }.map(\.recordID.recordName)
            changeToken = result.changeToken
            more = result.moreComing
        }
        return (members, deleted)
    }

    /// The host deletes the whole zone, which ends the trip for everyone; a member deletes only their own record.
    func leave(_ trip: Trip, memberID: String) async throws {
        if trip.isOwner {
            _ = try await database(trip).modifyRecordZones(saving: [], deleting: [zoneID(trip)])
        } else {
            let record = CKRecord.ID(recordName: memberID, zoneID: zoneID(trip))
            _ = try await database(trip).modifyRecords(saving: [], deleting: [record])
        }
    }

    func reset() {
        changeToken = nil
    }

    private func database(_ trip: Trip) -> CKDatabase {
        trip.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func zoneID(_ trip: Trip) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: trip.zoneName, ownerName: trip.ownerName)
    }

    /// Overwrites without a conflict check (we only ever write our own records) and returns what the server saved.
    @discardableResult
    private func save(_ records: [CKRecord], in database: CKDatabase) async throws -> [CKRecord] {
        let (results, _) = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
        return try results.values.map { try $0.get() }
    }
}

private extension Trip {
    init?(record: CKRecord, shareURL: URL?) {
        guard let name = record["name"] as? String,
              let destinationName = record["destinationName"] as? String,
              let destination = record.encryptedValues["destination"] as? CLLocation
        else { return nil }
        self.init(zoneName: record.recordID.zoneID.zoneName, ownerName: record.recordID.zoneID.ownerName,
                  isOwner: false, shareURL: shareURL, name: name, destinationName: destinationName,
                  latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
    }
}

private extension Member {
    init?(record: CKRecord) {
        guard record.recordType == "Member",
              let name = record["name"] as? String,
              let location = record.encryptedValues["location"] as? CLLocation,
              let updatedAt = record["updatedAt"] as? Date,
              let status = Status(rawValue: record["status"] as? String ?? "")
        else { return nil }
        self.init(id: record.recordID.recordName, name: name, location: location,
                  speed: record["speed"] as? Double ?? 0, heading: record["heading"] as? Double ?? 0,
                  arrival: record["arrival"] as? Date, updatedAt: updatedAt, status: status)
    }
}
