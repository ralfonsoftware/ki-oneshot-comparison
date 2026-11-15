import SwiftUI

struct ReadingEntryView: View {
    let repository: DataRepository
    @EnvironmentObject private var router: AppRouter
    @State private var timestamp = Date()
    @State private var value = ""
    @State private var validationError: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(String(localized: "Read at"), selection: $timestamp)
                    LabeledContent(String(localized: "Meter reading")) {
                        HStack {
                            TextField(String(localized: "0.0"), text: $value)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focused)
                                .accessibilityIdentifier("reading-value")
                            Text(String(localized: "kWh")).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(String(localized: "Use the cumulative value shown on the Main Meter."))
                }
                if let validationError {
                    Section { Text(validationError).foregroundStyle(.red) }
                }
            }
            .navigationTitle(String(localized: "Log reading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { router.sheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save"), action: save)
                        .accessibilityIdentifier("save-reading")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let kwh = InputValidation.reading(value) else {
            validationError = RepositoryError.invalidReading.localizedDescription
            return
        }
        do {
            switch try repository.saveReading(kwh: kwh, timestamp: timestamp) {
            case .alreadySaved:
                router.confirmation = String(localized: "Already saved")
                router.sheet = nil
            case .saved:
                let status = try? EnergyEngine.status(repository: repository)
                router.confirmation = String(format: String(localized: "Saved · %@"), status?.status?.label ?? String(localized: "Not enough data yet"))
                if let prompt = try? repository.openPrompt() {
                    router.sheet = .regression(prompt.id)
                } else {
                    router.sheet = nil
                }
            }
            NotificationScheduler.rebuildIfEnabled(repository: repository)
        } catch { validationError = error.localizedDescription }
    }
}

struct RegressionDecisionView: View {
    let prompt: MeterRegressionPrompt
    let repository: DataRepository
    @EnvironmentObject private var router: AppRouter
    @State private var selection: RegressionKind?
    @State private var capacity = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(question)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: { selection = .reset }) {
                        Label(String(localized: "Meter was replaced or reset"), systemImage: selection == .reset ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("regression-reset")
                    Button(action: { selection = .rollover }) {
                        Label(String(localized: "Meter rolled over (digits wrapped)"), systemImage: selection == .rollover ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if selection == .rollover {
                    Section {
                        DecimalUnitField(title: String(localized: "Digit capacity"), text: $capacity, unit: "kWh")
                    } footer: {
                        Text(String(localized: "For 99 999 → 00 000, the capacity is 100 000 kWh."))
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(String(localized: "What happened?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Not now")) { router.sheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save"), action: save).disabled(selection == nil)
                        .accessibilityIdentifier("save-regression")
                }
            }
            .onAppear {
                capacity = (try? repository.meter()?.digitCapacityKwh) ?? ""
                if let existing = prompt.classification { selection = RegressionKind(rawValue: existing) }
                if let stored = prompt.digitCapacityKwh { capacity = stored }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var question: String {
        guard let readings = try? repository.readings(),
              let current = readings.first(where: { $0.id == prompt.meterReadingId }),
              let previous = readings.first(where: { $0.id == prompt.previousMeterReadingId }),
              let currentValue = try? repository.effectiveValue(for: current),
              let previousValue = try? repository.effectiveValue(for: previous) else {
            return String(localized: "This reading is lower than the one before. What happened?")
        }
        return String(format: String(localized: "This reading is lower than the one before (%@ → %@ kWh). What happened?"), EnergyFormat.kwh(previousValue), EnergyFormat.kwh(currentValue))
    }

    private func save() {
        guard let selection else { return }
        do {
            var value: Decimal?
            if selection == .rollover {
                guard let parsed = InputValidation.nonNegative(capacity), parsed > 0 else {
                    errorMessage = RepositoryError.invalidDigitCapacity.localizedDescription
                    return
                }
                value = parsed
            }
            try repository.resolve(prompt, kind: selection, digitCapacity: value)
            let status = try? EnergyEngine.status(repository: repository)
            router.confirmation = String(format: String(localized: "Saved · %@"), status?.status?.label ?? String(localized: "Not enough data yet"))
            if let next = try repository.openPrompt() { router.sheet = .regression(next.id) } else { router.sheet = nil }
        } catch { errorMessage = error.localizedDescription }
    }
}
