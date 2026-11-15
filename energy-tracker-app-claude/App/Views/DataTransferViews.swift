import SwiftUI
import UniformTypeIdentifiers
import EnergyCore

// MARK: - Export (FR-19)

enum Exporter {
    /// Writes the export file to a temporary folder and returns its URL.
    @MainActor
    static func makeFile(store: EnergyStore) async throws -> URL {
        guard let records = store.exportRecords() else { throw StoreError.notFound }
        let data = await Task.detached(priority: .userInitiated) { ExportFormat.encode(records) }.value
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: ExportFormat.fileName(for: Date()))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    /// Opens the share sheet, which includes Save to Files.
    @MainActor
    static func share(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

struct ExportButton: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @State private var working = false

    var body: some View {
        Button {
            Task {
                working = true
                defer { working = false }
                do { Exporter.share(try await Exporter.makeFile(store: store)) } catch { model.showError(error) }
            }
        } label: {
            HStack {
                Label("Export all data", systemImage: "square.and.arrow.up")
                if working { Spacer(); ProgressView() }
            }
        }
        .disabled(working || store.data.isEmpty)
        .accessibilityIdentifier("exportButton")
    }
}

// MARK: - Import (FR-20)

struct ImportView: View {
    var isOnboarding: Bool
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Phase {
        case choose
        case reading
        case rejected([String])
        case ready(DataSetRecords)
        case importing(Double)
        case done(merged: Int)
    }

    nonisolated static let maxFileBytes = 250 * 1024 * 1024

    @State private var phase: Phase = .choose
    @State private var pickFile = false
    @State private var confirmReplace = false
    @State private var exportingFirst = false

    var body: some View {
        Form {
            switch phase {
            case .choose:
                Section {
                    Button {
                        if let testFile = Self.uiTestFile() { read(testFile) } else { pickFile = true }
                    } label: {
                        Label("Choose export file", systemImage: "doc.badge.arrow.up")
                    }
                    .accessibilityIdentifier("chooseFile")
                } footer: {
                    Text("Choose a JSON export file from Energy Tracker or from the old web app. Nothing changes until you confirm.")
                }
            case .reading:
                Section { HStack { ProgressView(); Text("Checking the file…") } }
            case .rejected(let failures):
                Section {
                    Label("This file can't be imported. Nothing was changed.", systemImage: "xmark.octagon")
                        .foregroundStyle(Theme.error)
                    Button("Choose another file") { pickFile = true }
                }
                Section("Problems") {
                    ForEach(Array(ImportValidationError(failures: failures).displayLines().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote.monospaced())
                    }
                }
            case .ready(let records):
                summary(records.counts, title: String(localized: "The file contains"))
                if store.data.isEmpty {
                    Section {
                        Button("Import") { runImport(records) }
                            .accessibilityIdentifier("confirmImport")
                    }
                } else {
                    Section {
                        Text("This deletes all current data on all your devices signed in to this Apple Account and replaces it with the file.")
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text("Replace all data")
                    }
                    summary(store.currentCounts, title: String(localized: "To be deleted"))
                    Section {
                        Button {
                            Task {
                                exportingFirst = true
                                defer { exportingFirst = false }
                                do { Exporter.share(try await Exporter.makeFile(store: store)) } catch { model.showError(error) }
                            }
                        } label: {
                            Label("Export current data first", systemImage: "square.and.arrow.up")
                        }
                        .disabled(exportingFirst)
                        Button("Replace all data", role: .destructive) { confirmReplace = true }
                            .accessibilityIdentifier("replaceAll")
                    }
                    .confirmationDialog("Replace all data?", isPresented: $confirmReplace, titleVisibility: .visible) {
                        Button("Replace all data", role: .destructive) { runImport(records) }
                    } message: {
                        Text("This deletes all current data on all your devices signed in to this Apple Account and replaces it with the file.")
                    }
                }
            case .importing(let fraction):
                Section {
                    ProgressView(value: fraction) { Text("Importing…") }
                }
            case .done(let merged):
                Section {
                    Label("Import finished.", systemImage: "checkmark.circle")
                    if merged > 0 {
                        Text(merged == 1 ? String(localized: "1 exact duplicate reading was merged.") : String(localized: "\(merged) exact duplicate readings were merged."))
                    }
                    if !isOnboarding {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .navigationTitle("Import")
        .fileImporter(isPresented: $pickFile, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let error): phase = .rejected([error.localizedDescription])
            }
        }
        .interactiveDismissDisabled(isImporting)
        .navigationBarBackButtonHidden(isImporting)
    }

    /// UI tests cannot drive the system file picker; they pass the file as base64 JSON in `ETUITestImportJSON`.
    private static func uiTestFile() -> URL? {
        guard AppConfig.isUITesting, let raw = ProcessInfo.processInfo.environment["ETUITestImportJSON"],
              let data = Data(base64Encoded: raw) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "uitest-import.json")
        try? data.write(to: url)
        return url
    }

    private var isImporting: Bool {
        if case .importing = phase { return true }
        return false
    }

    private func summary(_ c: DataSetRecords.Counts, title: String) -> some View {
        Section(title) {
            countRow("Readings", c.readings)
            countRow("Corrections", c.corrections)
            countRow("Regression decisions", c.prompts)
            countRow("Tariffs", c.tariffs)
            countRow("Events", c.events)
            countRow("Rooms", c.rooms)
            countRow("Power points", c.powerPoints)
            countRow("Devices", c.devices)
            countRow("Status snapshots", c.snapshots)
            if c.smartPlugReadings > 0 { countRow("Smart plug readings (kept, not shown)", c.smartPlugReadings) }
        }
    }

    private func countRow(_ label: LocalizedStringKey, _ count: Int) -> some View {
        LabeledContent(label, value: count.formatted())
    }

    private func read(_ url: URL) {
        phase = .reading
        Task {
            let result: Result<DataSetRecords, ImportValidationError> = await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > ImportView.maxFileBytes {
                    return .failure(ImportValidationError(failures: [String(localized: "The file is larger than 250 MB.")]))
                }
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                    return .failure(ImportValidationError(failures: [String(localized: "The file could not be read.")]))
                }
                do {
                    return .success(try ExportFormat.decode(data))
                } catch let error as ImportValidationError {
                    return .failure(error)
                } catch {
                    return .failure(ImportValidationError(failures: [error.localizedDescription]))
                }
            }.value
            switch result {
            case .success(let records): phase = .ready(records)
            case .failure(let error): phase = .rejected(error.failures)
            }
        }
    }

    private func runImport(_ records: DataSetRecords) {
        phase = .importing(0)
        Task {
            do {
                let result = try await store.replaceAll(with: records) { fraction in
                    phase = .importing(fraction)
                }
                phase = .done(merged: result.mergedDuplicateReadings)
            } catch {
                phase = .rejected([(error as? LocalizedError)?.errorDescription ?? error.localizedDescription])
            }
        }
    }
}

// MARK: - Onboarding (FR-3)

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store

    enum Step: Hashable { case baseline, currency, importFile }

    @State private var path: [Step] = []
    @State private var baseline = ""
    @State private var currency = Locale.current.currency?.identifier ?? "EUR"

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "bolt.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Energy Tracker")
                    .font(.largeTitle.weight(.semibold))
                Text("Read your meter every day or two. Energy Tracker tells you whether this year's use is on track.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        path.append(.baseline)
                    } label: {
                        Text("Start fresh").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("startFresh")
                    Button {
                        path.append(.importFile)
                    } label: {
                        Text("Import from export file").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("onboardingImport")
                }
                .controlSize(.large)
                .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: 520)
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .baseline: baselineStep
                case .currency: currencyStep
                case .importFile: ImportView(isOnboarding: true)
                }
            }
        }
    }

    private static let presets: [(people: Int, kwh: Int)] = [(1, 1_500), (2, 2_500), (3, 3_500), (4, 4_250)]

    private var baselineStep: some View {
        Form {
            Section {
                UnitField(title: "Yearly target", text: $baseline, unit: String(localized: "kWh/year"), identifier: "onboardingBaseline")
            } header: {
                Text("How much electricity do you expect to use in a year?")
            } footer: {
                Text("Your last annual bill is the best guide. You can change this at any time.")
            }
            Section("Typical values") {
                ForEach(Self.presets, id: \.people) { preset in
                    Button {
                        baseline = Format.editable(Decimal(preset.kwh))
                    } label: {
                        LabeledContent(preset.people == 1 ? String(localized: "1 person") : String(localized: "\(preset.people) people"),
                                       value: String(localized: "≈ \(Format.kwhWhole(Decimal(preset.kwh))) kWh"))
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Yearly target")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { baseline = ""; path.append(.currency) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { path.append(.currency) }
                    .accessibilityIdentifier("onboardingNext")
            }
        }
    }

    private var currencyStep: some View {
        Form {
            Section {
                Picker("Currency", selection: $currency) {
                    ForEach(CurrencyPicker.common.contains(currency) ? CurrencyPicker.common : [currency] + CurrencyPicker.common, id: \.self) { code in
                        Text("\(code) – \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Which currency do your tariffs use?")
            }
        }
        .navigationTitle("Currency")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { finish(currency: nil) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { finish(currency: currency) }
                    .accessibilityIdentifier("onboardingDone")
            }
        }
    }

    private func finish(currency: String?) {
        let value = Format.parseDecimal(baseline).flatMap { $0 > 0 ? $0 : nil }
        do { try store.startFresh(yearlyBaselineKwh: value, currency: currency) } catch { model.showError(error) }
    }
}
