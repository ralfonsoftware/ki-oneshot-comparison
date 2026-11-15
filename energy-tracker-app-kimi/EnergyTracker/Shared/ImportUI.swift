import SwiftUI

struct ImportSummary {
    var counts: [String: Int]
    var duplicateReadings: Int
}

struct PendingImport: Identifiable {
    let id = UUID()
    let data: Data
    let summary: ImportSummary
}

struct ImportConfirmationView: View {
    let pending: PendingImport
    let isNonEmpty: Bool
    @Binding var isImporting: Bool
    var repository: DataRepository?
    let action: () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "File summary")) {
                    ForEach(pending.summary.counts.keys.sorted(), id: \.self) { key in
                        LabeledContent(displayName(key), value: "\(pending.summary.counts[key] ?? 0)")
                    }
                    if pending.summary.duplicateReadings > 0 {
                        Text(String(format: String(localized: "%lld exact duplicate readings will be merged."), pending.summary.duplicateReadings))
                    }
                }
                if isNonEmpty {
                    Section {
                        Text(String(localized: "This deletes all current data on all your devices signed in to this Apple Account and replaces it with the file"))
                            .fixedSize(horizontal: false, vertical: true)
                        if let repository, let counts = try? repository.currentEntityCounts() {
                            Text(String(localized: "Current data to be deleted:")).font(.headline)
                            ForEach(counts.keys.sorted(), id: \.self) { key in
                                LabeledContent(displayName(key), value: "\(counts[key] ?? 0)")
                            }
                        }
                        if let exportURL {
                            ShareLink(String(localized: "Share current export"), item: exportURL)
                        } else {
                            Button(String(localized: "Export current data first"), action: exportCurrent)
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
            }
            .navigationTitle(isNonEmpty ? String(localized: "Replace all data") : String(localized: "Confirm import"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() }.disabled(isImporting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNonEmpty ? String(localized: "Replace all data") : String(localized: "Import data")) {
                        Task {
                            do { try await action(); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(isImporting)
                    .accessibilityIdentifier("confirm-import")
                }
            }
            .overlay { if isImporting { ProgressView().controlSize(.large) } }
        }
    }

    private func exportCurrent() {
        guard let repository else { return }
        do { exportURL = try ExportService(repository: repository).writeExport() }
        catch { errorMessage = error.localizedDescription }
    }

    private func displayName(_ key: String) -> String {
        switch key {
        case "meterReadings": String(localized: "Meter readings")
        case "meterRegressionPrompts": String(localized: "Regression decisions")
        case "tariffs": String(localized: "Tariffs")
        case "events": String(localized: "Events")
        case "rooms": String(localized: "Rooms")
        case "powerPoints": String(localized: "Power Points")
        case "devices": String(localized: "Devices")
        case "smartPlugReadings": String(localized: "Smart Plug readings")
        case "statusSnapshots": String(localized: "Status Snapshots")
        case "auditCorrections": String(localized: "Audit Corrections")
        default: key
        }
    }
}

extension DataRepository {
    func currentEntityCounts() throws -> [String: Int] {
        [
            "meterReadings": try readings().count,
            "meterRegressionPrompts": try prompts().count,
            "tariffs": try tariffs().count,
            "events": try events().count,
            "rooms": try rooms().count,
            "powerPoints": try powerPoints().count,
            "devices": try devices().count,
            "statusSnapshots": try snapshots().count,
            "smartPlugReadings": try currentGeneration().map { generation in try fetch(SmartPlugReading.self).filter { $0.generation == generation }.count } ?? 0,
            "auditCorrections": try currentGeneration().map { generation in try fetch(AuditCorrection.self).filter { $0.generation == generation }.count } ?? 0,
        ]
    }
}
