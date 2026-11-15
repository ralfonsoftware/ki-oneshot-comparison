import SwiftUI
import CloudKit
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    let repository: DataRepository
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("tariffRemindersEnabled", store: UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)) private var reminders = false
    @State private var baseline = ""
    @State private var threshold = "100"
    @State private var gapDays = 45
    @State private var cadence = 3
    @State private var currency = "EUR"
    @State private var cloudStatus = ""
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var pendingImport: PendingImport?
    @State private var isImporting = false
    @State private var exportURL: URL?
    @State private var showShare = false

    var body: some View {
        Form {
            Section(String(localized: "Pattern")) {
                DecimalUnitField(title: String(localized: "Yearly Baseline"), text: $baseline, unit: "kWh/year")
                Button(String(localized: "Save yearly target")) { savePattern() }
                if !baseline.isEmpty {
                    Button(String(localized: "Clear yearly target")) { baseline = ""; savePattern() }
                }
                DecimalUnitField(title: String(localized: "Trending threshold"), text: $threshold, unit: "kWh/year")
                Button(String(localized: "Save threshold")) { savePattern() }
                Stepper(value: $gapDays, in: 1...365) { LabeledContent(String(localized: "Low-confidence gap"), value: String(format: String(localized: "%lld days"), gapDays)) }
                    .onChange(of: gapDays) { _, _ in savePattern() }
                Text(String(localized: "Changes apply going forward. Stored status history is not recomputed.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Currency and tariff checks")) {
                DecimalUnitField(title: String(localized: "Household currency"), text: $currency, unit: String(localized: "ISO code"), keyboard: .default)
                    .textInputAutocapitalization(.characters)
                Button(String(localized: "Save currency")) { savePattern() }
                Stepper(value: $cadence, in: 1...24) { LabeledContent(String(localized: "Tariff check cadence"), value: String(format: String(localized: "%lld months"), cadence)) }
                    .onChange(of: cadence) { _, _ in savePattern() }
            }
            Section {
                NavigationLink(String(localized: "Rooms & Devices")) { StructureView(repository: repository).environmentObject(router) }
            }
            Section {
                Toggle(String(localized: "Tariff reminders on this device"), isOn: $reminders)
                    .onChange(of: reminders) { _, enabled in Task { await updateReminders(enabled) } }
            } footer: {
                Text(String(localized: "Reminders are off by default and set per device, so your iPhone and iPad do not both notify you. They arrive at 10:00 local time."))
            }
            Section(String(localized: "Sync")) {
                Text(cloudStatus).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(String(localized: "Your data")) {
                Button(String(localized: "Export"), systemImage: "square.and.arrow.up", action: export)
                    .accessibilityIdentifier("export-data")
                Button(String(localized: "Import"), systemImage: "square.and.arrow.down") { showImporter = true }
                    .accessibilityIdentifier("import-data")
                Text(String(localized: "Import replaces the whole data set after confirmation. Export includes corrections, archived items and stored Smart Plug readings.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Appearance"), selection: $appearance) {
                    Text(String(localized: "System")).tag("system")
                    Text(String(localized: "Light")).tag("light")
                    Text(String(localized: "Dark")).tag("dark")
                }
            }
            Section(String(localized: "About")) {
                LabeledContent(String(localized: "Version"), value: version)
                Text(String(localized: "Your data stays on your Apple devices and in your private iCloud database. Energy Tracker has no account, analytics, tracking or server."))
                if let url = infoURL("SupportURL") { Link(String(localized: "Support"), destination: url) }
                if let url = infoURL("PrivacyPolicyURL") { Link(String(localized: "Privacy policy"), destination: url) }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
        }
        .navigationTitle(String(localized: "Settings"))
        .toolbar { if router.sheet != nil { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } } } }
        .onAppear {
            if let household = try? repository.activeHouseholdRecord() {
                baseline = household.yearlyBaselineKwh ?? ""; threshold = household.trendingThresholdKwh
                gapDays = household.lowConfidenceGapDays; cadence = household.tariffCheckCadenceMonths; currency = household.currency
            }
            Task { await updateCloudStatus() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let data = try FileAccess.read(url: url)
                let document = try ImportService.inspect(data: data)
                pendingImport = PendingImport(data: data, summary: ImportSummary(document: document))
            } catch { errorMessage = error.localizedDescription }
        }
        .sheet(item: $pendingImport) { pending in
            ImportConfirmationView(pending: pending, isNonEmpty: true, isImporting: $isImporting, repository: repository) {
                isImporting = true
                defer { isImporting = false }
                try await ImportService(repository: repository).performImport(pending.data)
                pendingImport = nil
                router.confirmation = String(localized: "Import complete")
            }
        }
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .overlay { if isImporting { ProgressView(String(localized: "Importing your data…")).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
    }

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(marketing) (\(build))"
    }

    private func infoURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return URL(string: value)
    }

    private func savePattern() {
        do {
            if baseline.isEmpty { try repository.setYearlyBaseline(nil) }
            else {
                guard let value = InputValidation.decimal(baseline, maximumFractionDigits: 2), value >= 0 else { throw RepositoryError.invalidReading }
                try repository.setYearlyBaseline(value)
            }
            guard let thresholdValue = InputValidation.nonNegative(threshold) else { throw RepositoryError.invalidTariff }
            try repository.setTrendingThreshold(thresholdValue)
            try repository.setLowConfidenceGap(gapDays)
            try repository.setTariffCadence(cadence)
            try repository.setCurrency(currency)
            errorMessage = nil
            NotificationScheduler.rebuildIfEnabled(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    private func updateCloudStatus() async {
        let device = UIDevice.current.localizedModel
        guard PersistenceController.shared.isCloudKitConfigured else {
            cloudStatus = String(format: String(localized: "iCloud sync off — data stays on this %@. Reason: local store fallback."), device)
            return
        }
        let status = try? await CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier).accountStatus()
        switch status {
        case .available: cloudStatus = String(localized: "iCloud sync on — your private database keeps these devices up to date.")
        case .noAccount: cloudStatus = String(format: String(localized: "iCloud sync off — data stays on this %@. Reason: not signed in to iCloud."), device)
        case .restricted: cloudStatus = String(format: String(localized: "iCloud sync off — data stays on this %@. Reason: iCloud is restricted."), device)
        case .couldNotDetermine, .temporarilyUnavailable, .none: cloudStatus = String(format: String(localized: "iCloud sync off — data stays on this %@. Reason: iCloud is unavailable."), device)
        @unknown default: cloudStatus = String(localized: "iCloud status is unavailable.")
        }
    }

    private func updateReminders(_ enabled: Bool) async {
        if enabled {
            let granted = await NotificationScheduler.requestPermission()
            if !granted { reminders = false; errorMessage = String(localized: "Notification permission was not granted. You can enable it in system Settings."); return }
        }
        NotificationScheduler.rebuildIfEnabled(repository: repository)
    }

    private func export() {
        do {
            exportURL = try ExportService(repository: repository).writeExport()
            showShare = true
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
