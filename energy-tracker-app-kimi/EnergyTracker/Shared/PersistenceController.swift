import Foundation
import SwiftData
import CloudKit
import Combine

@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    @Published private(set) var container: ModelContainer
    @Published private(set) var storeRevision: String
    private(set) var isCloudKitConfigured: Bool

    private let schema = Schema(versionedSchema: EnergySchemaV1.self)
    private let directory: URL
    private let inMemory: Bool
    private let defaults: UserDefaults?
    private let accountKey = "currentCloudKitAccountRecordName"
    private let storeKey = "currentCloudKitStoreID"
    private let accountStoresKey = "cloudKitAccountStoreIDs"

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupIdentifier)
        directory = appGroupURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        defaults = inMemory ? nil : UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)

        let storeID = inMemory ? UUID().uuidString : defaults?.string(forKey: storeKey) ?? "primary"
        if AppConfiguration.isUITesting && ProcessInfo.processInfo.arguments.contains("-ResetStore") {
            let storeURL = directory.appendingPathComponent(storeID == "primary" ? "EnergyTracker.store" : "EnergyTracker-\(storeID).store")
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }
        storeRevision = storeID
        let result = Self.makeContainer(schema: schema, directory: directory, storeID: storeID, inMemory: inMemory)
        container = result.container
        isCloudKitConfigured = result.cloudConfigured
    }

    /// Selects a separate physical store when the signed-in Apple Account changes.
    /// Signing out keeps the current store usable locally. Signing back into the same
    /// account resumes it; another account starts with its own records only.
    func refreshAccount() async {
        guard !inMemory, !AppConfiguration.isLocalStoreOnly else { return }
        let cloud = CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier)
        guard let status = try? await cloud.accountStatus(), status == .available,
              let record = try? await userRecordID(container: cloud) else { return }
        let account = record.recordName
        let previousAccount = defaults?.string(forKey: accountKey)
        guard previousAccount != account else { return }

        var accountStores = defaults?.dictionary(forKey: accountStoresKey) as? [String: String] ?? [:]
        let currentStore = defaults?.string(forKey: storeKey) ?? storeRevision
        let nextStore: String
        if let existing = accountStores[account] {
            nextStore = existing
        } else if previousAccount == nil {
            // Unassigned local data is allowed to upload when iCloud first becomes available.
            nextStore = currentStore
        } else {
            nextStore = UUID().uuidString
        }
        accountStores[account] = nextStore

        let result = Self.makeContainer(schema: schema, directory: directory, storeID: nextStore, inMemory: false)
        container = result.container
        isCloudKitConfigured = result.cloudConfigured
        storeRevision = nextStore
        defaults?.set(account, forKey: accountKey)
        defaults?.set(nextStore, forKey: storeKey)
        defaults?.set(accountStores, forKey: accountStoresKey)
    }

    private func userRecordID(container: CKContainer) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { record, error in
                if let record { continuation.resume(returning: record) }
                else { continuation.resume(throwing: error ?? CKError(.unknownItem)) }
            }
        }
    }

    private static func makeContainer(schema: Schema, directory: URL, storeID: String, inMemory: Bool) -> (container: ModelContainer, cloudConfigured: Bool) {
        let localOnly = inMemory || AppConfiguration.isLocalStoreOnly
        let storeURL = directory.appendingPathComponent(storeID == "primary" ? "EnergyTracker.store" : "EnergyTracker-\(storeID).store")
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("EnergyTrackerTests-\(storeID)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: localOnly ? .none : .private(AppConfiguration.cloudKitContainerIdentifier)
            )
        }

        do {
            return (try ModelContainer(for: schema, migrationPlan: EnergyMigrationPlan.self, configurations: [configuration]), !localOnly)
        } catch {
            // A CloudKit failure must never prevent access to local data.
            let fallbackURL = directory.appendingPathComponent(inMemory ? "EnergyTracker-testing-fallback.store" : "EnergyTracker-local-\(storeID).store")
            let fallback = inMemory
                ? ModelConfiguration("EnergyTrackerTestsFallback", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                : ModelConfiguration(schema: schema, url: fallbackURL, cloudKitDatabase: .none)
            do {
                return (try ModelContainer(for: schema, migrationPlan: EnergyMigrationPlan.self, configurations: [fallback]), false)
            } catch {
                fatalError("Unable to create the Energy Tracker store: \(error)")
            }
        }
    }
}
