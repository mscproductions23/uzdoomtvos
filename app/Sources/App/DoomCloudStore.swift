//
//  DoomCloudStore.swift
//  Shared between iOS (uploader) and tvOS (consumer) targets.
//
//  CloudKit-backed storage for WADs and save games.
//  Source of truth: the user's private CloudKit database.
//  Local mirror: Caches directory (tvOS-safe; may be purged by the OS).
//
//  Data lives in the private database of the iCloud account signed in on the device
//  (tvOS apps can't sign in to iCloud themselves). The container ID is set in
//  UZDoomTV.entitlements and below; builds under another team must use their own.
//

import CloudKit
import CryptoKit
import Foundation

// MARK: - Record schema

enum CloudSchema {
    static let zoneName = "DoomContent"

    enum WadFile {
        static let recordType = "WadFile"
        static let fileName   = "fileName"    // String, e.g. "DOOM2.WAD" (uppercased key)
        static let kind       = "kind"        // String: "iwad" | "pwad" | "mod"
        static let sha256     = "sha256"      // String hex digest — integrity + change detection
        static let size       = "size"        // Int64
        static let asset      = "asset"       // CKAsset (the file itself)
    }

    enum SaveGame {
        static let recordType = "SaveGame"
        static let fileName   = "fileName"    // String, e.g. "save0001.zds"
        static let iwadName   = "iwadName"    // String — which game this save belongs to
        static let modifiedAt = "modifiedAt"  // Date — engine-side mtime, used for conflict resolution
        static let asset      = "asset"       // CKAsset
    }
}

// MARK: - Errors

enum DoomCloudError: LocalizedError {
    case notSignedIntoiCloud
    case iCloudDisabled
    case recordMissingAsset(String)
    case wadNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIntoiCloud:
            return "This Apple TV is not signed into iCloud."
        case .iCloudDisabled:
            return "iCloud sync is turned off."
        case .recordMissingAsset(let name):
            return "Cloud record for \(name) has no file attached."
        case .wadNotFound(let name):
            return "\(name) was not found in iCloud. Upload it from the iPhone/iPad app first."
        }
    }
}

// MARK: - Store

actor DoomCloudStore {

    static let shared = DoomCloudStore()

    // CloudKit needs a paid Apple Developer Program team. Creating a CKContainer
    // without the iCloud entitlement crashes, so it only exists in builds with
    // the UZ_ICLOUD compilation condition (plus UZDoomTV.entitlements).
    #if UZ_ICLOUD
    private let container: CKContainer? = CKContainer(identifier: "iCloud.com.mscproductions.uzdoomtv")
    #else
    private let container: CKContainer? = nil
    #endif
    private var db: CKDatabase { container!.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: CloudSchema.zoneName,
                                         ownerName: CKCurrentUserDefaultName)
    private var zoneReady = false

    // Local mirror. tvOS: only Caches/tmp are writable, and Caches can be purged —
    // which is fine, because CloudKit is the source of truth and we re-download.
    nonisolated static var localWadDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("wads", isDirectory: true)
    }

    nonisolated static var localSaveDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("saves", isDirectory: true)
    }

    // MARK: Setup

    /// The launcher's iCloud Sync switch. Off: WADs and saves stay on this Apple TV only.
    nonisolated static var syncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: syncEnabledKey) as? Bool ?? false }   // off until the player turns it on
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }
    nonisolated static let syncEnabledKey = "iCloudSyncEnabled"

    /// What the launcher shows about iCloud.
    enum AccountState: Equatable, Sendable {
        case notInThisBuild, switchedOff, available, noAccount, restricted, temporarilyUnavailable, unknown
    }

    /// The iCloud account signed in on this Apple TV (Settings → Users and Accounts).
    func accountState() async -> AccountState {
        guard let container else { return .notInThisBuild }
        guard Self.syncEnabled else { return .switchedOff }
        do {
            switch try await container.accountStatus() {
            case .available:              return .available
            case .noAccount:              return .noAccount
            case .restricted:             return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            default:                      return .unknown
            }
        } catch {
            return .unknown
        }
    }

    /// Call when the device's iCloud account changes (.CKAccountChanged): another user's
    /// private database needs its own zone check.
    func accountChanged() {
        zoneReady = false
    }

    private func ensureZone() async throws {
        guard Self.syncEnabled else { throw DoomCloudError.iCloudDisabled }
        guard !zoneReady else { return }
        guard let container else { throw DoomCloudError.iCloudDisabled }
        // Verify iCloud account before doing anything else.
        let status = try await container.accountStatus()
        guard status == .available else { throw DoomCloudError.notSignedIntoiCloud }

        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])
        zoneReady = true
    }

    // MARK: - WADs: upload (call from the iOS target, which has Files access)

    /// Upload or replace a WAD in the private database. Record ID is derived from the
    /// uppercased filename, so re-uploading the same WAD updates in place.
    func uploadWad(from fileURL: URL, kind: String = "iwad") async throws {
        try await ensureZone()

        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let name = fileURL.lastPathComponent.uppercased()

        let recordID = CKRecord.ID(recordName: "wad-\(name)", zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await db.record(for: recordID) {
            // Unchanged file? Skip the (potentially large) re-upload.
            if existing[CloudSchema.WadFile.sha256] as? String == digest { return }
            record = existing
        } else {
            record = CKRecord(recordType: CloudSchema.WadFile.recordType, recordID: recordID)
        }

        record[CloudSchema.WadFile.fileName] = name
        record[CloudSchema.WadFile.kind]     = kind
        record[CloudSchema.WadFile.sha256]   = digest
        record[CloudSchema.WadFile.size]     = Int64(data.count)
        record[CloudSchema.WadFile.asset]    = CKAsset(fileURL: fileURL)

        _ = try await db.modifyRecords(saving: [record], deleting: [],
                                       savePolicy: .changedKeys)
    }

    /// List WADs available in the cloud: (fileName, sha256, size).
    func listWads() async throws -> [(name: String, sha256: String, size: Int64)] {
        try await ensureZone()
        let query = CKQuery(recordType: CloudSchema.WadFile.recordType,
                            predicate: NSPredicate(value: true))
        let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)
        return results.compactMap { _, result in
            guard let record = try? result.get(),
                  let name = record[CloudSchema.WadFile.fileName] as? String,
                  let sha  = record[CloudSchema.WadFile.sha256] as? String,
                  let size = record[CloudSchema.WadFile.size] as? Int64
            else { return nil }
            return (name, sha, size)
        }
    }

    // MARK: - WADs: bootstrap (call from tvOS before engine init)

    /// Ensure every required WAD exists locally, downloading from CloudKit as needed.
    /// Returns local file URLs in the same order, ready to pass to the engine as -iwad/-file args.
    /// `onProgress` reports (fileName, fractionCompleted-ish step count).
    func ensureWadsPresent(_ required: [String],
                           onProgress: @Sendable (String) -> Void = { _ in }) async throws -> [URL] {
        let dir = Self.localWadDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var resolved: [URL] = []
        var missing: [String] = []

        for name in required.map({ $0.uppercased() }) {
            let local = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: local.path) {
                resolved.append(local)
            } else if let bundled = Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                                                    withExtension: (name as NSString).pathExtension) {
                // Embedded-WAD fallback: bundle copy wins if present (your testing path).
                resolved.append(bundled)
            } else {
                missing.append(name)
            }
        }

        guard !missing.isEmpty else { return resolved }

        try await ensureZone()
        for name in missing {
            onProgress(name)
            let recordID = CKRecord.ID(recordName: "wad-\(name)", zoneID: zoneID)
            guard let record = try? await db.record(for: recordID) else {
                throw DoomCloudError.wadNotFound(name)
            }
            guard let asset = record[CloudSchema.WadFile.asset] as? CKAsset,
                  let assetURL = asset.fileURL else {
                throw DoomCloudError.recordMissingAsset(name)
            }
            let dest = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: assetURL, to: dest)
            resolved.append(dest)
        }
        return resolved
    }

    // MARK: - Saves

    /// Push a save file to the cloud. Call after the engine finishes writing a save
    /// (or diff the save directory on app background/quit).
    func uploadSave(from fileURL: URL, iwadName: String) async throws {
        try await ensureZone()
        let name = fileURL.lastPathComponent
        let mtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? Date()

        let recordID = CKRecord.ID(recordName: "save-\(iwadName.uppercased())-\(name)", zoneID: zoneID)
        let record = (try? await db.record(for: recordID))
            ?? CKRecord(recordType: CloudSchema.SaveGame.recordType, recordID: recordID)

        // Last-writer-wins by engine mtime: don't clobber a newer cloud save with an older local one.
        if let cloudDate = record[CloudSchema.SaveGame.modifiedAt] as? Date, cloudDate >= mtime {
            return
        }

        record[CloudSchema.SaveGame.fileName]   = name
        record[CloudSchema.SaveGame.iwadName]   = iwadName.uppercased()
        record[CloudSchema.SaveGame.modifiedAt] = mtime
        record[CloudSchema.SaveGame.asset]      = CKAsset(fileURL: fileURL)

        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    /// Pull down any cloud saves newer than (or absent from) the local save directory.
    /// Call on launch before the engine reads its save path.
    func syncSavesDown(iwadName: String) async throws {
        try await ensureZone()
        let dir = Self.localSaveDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let predicate = NSPredicate(format: "%K == %@",
                                    CloudSchema.SaveGame.iwadName, iwadName.uppercased())
        let query = CKQuery(recordType: CloudSchema.SaveGame.recordType, predicate: predicate)
        let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)

        for (_, result) in results {
            guard let record = try? result.get(),
                  let name = record[CloudSchema.SaveGame.fileName] as? String,
                  let cloudDate = record[CloudSchema.SaveGame.modifiedAt] as? Date,
                  let asset = record[CloudSchema.SaveGame.asset] as? CKAsset,
                  let assetURL = asset.fileURL
            else { continue }

            let local = dir.appendingPathComponent(name)
            let localDate = (try? FileManager.default
                .attributesOfItem(atPath: local.path)[.modificationDate] as? Date) ?? .distantPast

            if cloudDate > localDate {
                try? FileManager.default.removeItem(at: local)
                try FileManager.default.copyItem(at: assetURL, to: local)
                try? FileManager.default.setAttributes([.modificationDate: cloudDate],
                                                       ofItemAtPath: local.path)
            }
        }
    }

    /// Push every local save that's newer than its cloud counterpart.
    /// Call on scenePhase -> .background / .inactive.
    func syncSavesUp(iwadName: String) async throws {
        let dir = Self.localSaveDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.pathExtension.lowercased() == "zds" {
            try await uploadSave(from: file, iwadName: iwadName)
        }
    }
}
