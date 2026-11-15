import SwiftUI

struct ReadingHistoryView: View {
    let repository: DataRepository
    let search: String
    let embedded: Bool
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            Section(String(localized: "Readings")) {
                if readings.isEmpty {
                    Text(String(localized: "No readings found.")).foregroundStyle(.secondary)
                }
                ForEach(readings, id: \.id) { reading in
                    NavigationLink {
                        ReadingDetailView(reading: reading, repository: repository)
                    } label: {
                        row(reading)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(embedded ? .hidden : .automatic)
        .frame(minHeight: embedded ? 300 : nil)
    }

    private var readings: [MeterReading] {
        let all = ((try? repository.readings()) ?? []).reversed()
        guard !search.isEmpty else { return Array(all) }
        return all.filter {
            let value = (try? repository.effectiveValue(for: $0)).map { EnergyFormat.kwh($0) } ?? ""
            return value.localizedCaseInsensitiveContains(search) || $0.readingTimestamp.formatted().localizedCaseInsensitiveContains(search)
        }
    }

    private func row(_ reading: MeterReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(EnergyFormat.kwh((try? repository.effectiveValue(for: reading)) ?? 0)) kWh").font(.headline)
                Spacer()
                Text(reading.readingTimestamp.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
            }
            if let correction = try? repository.corrections(for: reading).last {
                Text(String(format: String(localized: "Corrected from %@ kWh on %@"), EnergyFormat.kwh(DecimalText.decode(correction.oldValue) ?? 0), correction.correctedAt.formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let prompt = try? repository.openPrompt(), prompt.meterReadingId == reading.id {
                Label(String(localized: "Needs a decision"), systemImage: "arrow.triangle.branch")
                    .font(.caption).foregroundStyle(DisplayStatus.trending.labelColor)
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("reading-row-\(reading.id.uuidString)")
    }
}

struct ReadingDetailView: View {
    let reading: MeterReading
    let repository: DataRepository
    @EnvironmentObject private var router: AppRouter
    @State private var showCorrection = false
    @State private var correctedValue = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section(String(localized: "Reading")) {
                LabeledContent(String(localized: "Effective value"), value: "\(EnergyFormat.kwh((try? repository.effectiveValue(for: reading)) ?? 0)) kWh")
                LabeledContent(String(localized: "Original value"), value: "\(EnergyFormat.kwh(DecimalText.decode(reading.kwhValue) ?? 0)) kWh")
                LabeledContent(String(localized: "Read at"), value: reading.readingTimestamp.formatted(date: .long, time: .shortened))
                Button(String(localized: "Correct reading")) {
                    correctedValue = (try? repository.effectiveValue(for: reading)).map(DecimalText.encode) ?? ""
                    showCorrection = true
                }
                .accessibilityIdentifier("correct-reading")
            }
            if let prompt = try? repository.prompts().first(where: { $0.meterReadingId == reading.id }) {
                Section(String(localized: "Regression")) {
                    if prompt.resolvedAt == nil {
                        Label(String(localized: "Needs a decision"), systemImage: "arrow.triangle.branch")
                    } else {
                        LabeledContent(String(localized: "Classification"), value: prompt.classification == "rollover" ? String(localized: "Rollover") : String(localized: "Reset"))
                    }
                    Button(String(localized: "Change classification")) { router.show(.regression(prompt.id)) }
                }
            }
            if let corrections = try? repository.corrections(for: reading), !corrections.isEmpty {
                Section(String(localized: "Corrections")) {
                    ForEach(corrections.reversed(), id: \.id) { correction in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(EnergyFormat.kwh(DecimalText.decode(correction.oldValue) ?? 0)) → \(EnergyFormat.kwh(DecimalText.decode(correction.newValue) ?? 0)) kWh")
                            Text(correction.correctedAt.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(String(localized: "Reading details"))
        .sheet(isPresented: $showCorrection) {
            NavigationStack {
                Form {
                    DecimalUnitField(title: String(localized: "Corrected reading"), text: $correctedValue, unit: "kWh")
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
                .navigationTitle(String(localized: "Correct reading"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { showCorrection = false } }
                    ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Save"), action: correct).accessibilityIdentifier("save-correction") }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func correct() {
        do {
            guard let value = InputValidation.reading(correctedValue) else { throw RepositoryError.invalidReading }
            _ = try repository.correct(reading, to: value)
            showCorrection = false
            router.confirmation = String(localized: "Correction saved")
        } catch { errorMessage = error.localizedDescription }
    }
}
