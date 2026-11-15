import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    let repository: DataRepository
    let completed: () -> Void
    @State private var showSetup = false
    @State private var baseline = ""
    @State private var currency = Locale.current.currency?.identifier.uppercased() ?? "EUR"
    @State private var showImporter = false
    @State private var pendingImport: PendingImport?
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                        Text(String(localized: "Energy Tracker"))
                            .font(.largeTitle.bold())
                        Text(String(localized: "A calm view of your electricity use, built from your own meter readings."))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    if showSetup {
                        setup
                    } else {
                        VStack(spacing: 12) {
                            Button(String(localized: "Start fresh")) { showSetup = true }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                            Button(String(localized: "Import from export file")) { showImporter = true }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 600)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .sheet(item: $pendingImport) { pending in
                ImportConfirmationView(pending: pending, isNonEmpty: false, isImporting: $isImporting) {
                    try await performImport(pending)
                }
            }
            .alert(String(localized: "Import rejected"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "OK")) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .overlay { if isImporting { ProgressView(String(localized: "Importing your data…")).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "Your yearly target"))
                .font(.title2.bold())
            Text(String(localized: "This is a target, not an estimate from your readings. You can set it later."))
                .foregroundStyle(.secondary)
            DecimalUnitField(title: String(localized: "Yearly Baseline"), text: $baseline, unit: "kWh/year")
            ViewThatFits(in: .horizontal) {
                HStack { presetButtons }
                VStack { presetButtons }
            }
            DecimalUnitField(title: String(localized: "Currency"), text: $currency, unit: String(localized: "ISO code"), keyboard: .default)
                .textInputAutocapitalization(.characters)
            HStack {
                Button(String(localized: "Skip")) { finish(baselineValue: nil) }
                    .buttonStyle(.borderless)
                Spacer()
                Button(String(localized: "Start tracking")) {
                    let value = baseline.isEmpty ? nil : InputValidation.decimal(baseline, maximumFractionDigits: 2)
                    if !baseline.isEmpty && value == nil {
                        errorMessage = String(localized: "Enter a valid yearly target with at most 2 decimal places.")
                    } else {
                        finish(baselineValue: value)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var presetButtons: some View {
        ForEach([("1 person", "1500"), ("2 people", "2500"), ("3 people", "3500"), ("4 people", "4250")], id: \.0) { preset in
            Button(String(localized: String.LocalizationValue(preset.0))) { baseline = preset.1 }
                .buttonStyle(.bordered)
                .font(.caption)
        }
    }

    private func finish(baselineValue: Decimal?) {
        do {
            _ = try repository.startFresh(yearlyBaseline: baselineValue, currency: currency)
            completed()
        } catch { errorMessage = error.localizedDescription }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first!
            let data = try FileAccess.read(url: url)
            let document = try ImportService.inspect(data: data)
            pendingImport = PendingImport(data: data, summary: ImportSummary(document: document))
        } catch { errorMessage = error.localizedDescription }
    }

    private func performImport(_ pending: PendingImport) async throws {
        isImporting = true
        defer { isImporting = false }
        try await ImportService(repository: repository).performImport(pending.data)
        pendingImport = nil
        completed()
    }
}

struct DecimalUnitField: View {
    let title: String
    @Binding var text: String
    let unit: String
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        LabeledContent(title) {
            HStack {
                TextField(title, text: $text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
