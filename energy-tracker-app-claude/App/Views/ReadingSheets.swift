import SwiftUI
import EnergyCore

/// A number field with its unit inside the field ("kWh", "€/kWh", "€/month") (§9.3).
struct UnitField: View {
    var title: LocalizedStringKey
    @Binding var text: String
    var unit: String
    var keyboard: UIKeyboardType = .decimalPad
    var identifier: String?

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier(identifier ?? "")
            Text(unit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Log reading (FR-4)

struct LogReadingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Meter reading", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                            .focused($focused)
                            .accessibilityIdentifier("kwhField")
                            .onSubmit(save)
                        Text("kWh").foregroundStyle(.secondary).font(.title3)
                    }
                    .frame(minHeight: 44)
                    if let latest = store.data.latestReading {
                        Text("Last: \(Format.kwhWithUnit(store.data.effectiveValues[latest.id] ?? latest.originalKwhValue)) · \(Format.dateTime(latest.readingTimestamp))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Theme.error)
                    }
                }
                Section {
                    DatePicker("Read at", selection: $date, in: ...Date().addingTimeInterval(60))
                }
            }
            .navigationTitle("Log reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("saveReading")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let value = Format.parseDecimal(text) else {
            error = String(localized: "Enter a number, for example 12345.6.")
            return
        }
        do {
            switch try store.logReading(kwh: value, at: date) {
            case .alreadySaved:
                model.showToast(String(localized: "Already saved"), symbol: "checkmark")
                dismiss()
            case .saved(_, let status, let openPromptId, _):
                if let openPromptId {
                    model.showToast(String(localized: "Saved"), symbol: "checkmark")
                    // The regression prompt replaces this sheet (sheets never stack).
                    model.present(.regression(openPromptId))
                } else {
                    model.showToast(savedText(status), symbol: "checkmark")
                    dismiss()
                }
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// "Saved · Within range".
func savedText(_ status: StatusOutcome) -> String {
    if let r = status.result { return String(localized: "Saved · \(r.status.label)") }
    return String(localized: "Saved")
}

// MARK: - Regression decision (FR-11)

struct RegressionPromptSheet: View {
    var promptId: UUID
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var choosingRollover = false
    @State private var capacityText = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let prompt = store.data.prompts.first(where: { $0.id == promptId }) {
                    content(prompt)
                } else {
                    ContentUnavailableView("Nothing to decide", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle(choosingRollover ? String(localized: "Meter capacity") : String(localized: "Lower reading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func content(_ prompt: MeterRegressionPrompt) -> some View {
        let current = prompt.meterReadingId.flatMap { store.data.effectiveValues[$0] }
        let previous = prompt.previousMeterReadingId.flatMap { store.data.effectiveValues[$0] }
        Form {
            Section {
                if let current, let previous {
                    Text("This reading is lower than the one before (\(Format.kwh(previous)) → \(Format.kwh(current)) kWh). What happened?")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if prompt.isResolved, let classification = prompt.classification {
                    Text("Currently classified as: \(classification.title).")
                        .foregroundStyle(.secondary)
                }
            }
            if choosingRollover {
                Section {
                    UnitField(title: "Digit capacity", text: $capacityText, unit: "kWh", identifier: "capacityField")
                } header: {
                    Text("At what value do the digits wrap?")
                } footer: {
                    if let error { Text(error).foregroundStyle(Theme.error) } else {
                        Text("For example 100000 kWh for a meter with five digits before the decimal point.")
                    }
                }
                Section {
                    Button("Save rollover") { resolve(prompt, .rollover) }
                        .accessibilityIdentifier("saveRollover")
                }
            } else {
                Section {
                    Button {
                        resolve(prompt, .reset)
                    } label: {
                        Label("Meter was replaced or reset", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("chooseReset")
                    Button {
                        capacityText = (store.data.meter?.digitCapacityKwh ?? prompt.digitCapacityKwh).map { Format.editable($0) } ?? ""
                        choosingRollover = true
                    } label: {
                        Label("Meter rolled over (digits wrapped)", systemImage: "arrow.trianglehead.2.clockwise")
                    }
                    .accessibilityIdentifier("chooseRollover")
                }
            }
        }
    }

    private func resolve(_ prompt: MeterRegressionPrompt, _ classification: RegressionClassification) {
        var capacity: Decimal?
        if classification == .rollover {
            guard let value = Format.parseDecimal(capacityText), value > 0 else {
                error = String(localized: "Enter the capacity in kWh, for example 100000.")
                return
            }
            if let previous = prompt.previousMeterReadingId.flatMap({ store.data.effectiveValues[$0] }), value <= previous {
                error = String(localized: "The capacity must be larger than the previous reading.")
                return
            }
            capacity = value
        }
        do {
            if prompt.isResolved, let readingId = prompt.meterReadingId {
                try store.changeClassification(readingId: readingId, classification: classification, digitCapacityKwh: capacity)
            } else {
                try store.resolvePrompt(id: prompt.id, classification: classification, digitCapacityKwh: capacity)
            }
            // Queued prompts open in order.
            if let next = Readings.activeOpenPrompt(readings: Readings.ordered(store.data.readingInputs), prompts: store.data.promptInputs) {
                model.present(.regression(next.id))
            } else {
                model.showToast(savedText(store.data.status()), symbol: "checkmark")
                dismiss()
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Correction (FR-10)

struct CorrectReadingSheet: View {
    var readingId: UUID
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let reading = store.data.readings.first(where: { $0.id == readingId }) {
                    let effective = store.data.effectiveValues[reading.id] ?? reading.originalKwhValue
                    Section {
                        LabeledContent("Current value", value: Format.kwhWithUnit(effective))
                        LabeledContent("Read at", value: Format.dateTime(reading.readingTimestamp))
                    }
                    Section {
                        HStack {
                            TextField("Correct value", text: $text)
                                .keyboardType(.decimalPad)
                                .focused($focused)
                                .accessibilityIdentifier("correctionField")
                            Text("kWh").foregroundStyle(.secondary)
                        }
                    } footer: {
                        if let error { Text(error).foregroundStyle(Theme.error) } else {
                            Text("The original value stays visible in the reading's history.")
                        }
                    }
                }
            }
            .navigationTitle("Correct reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).accessibilityIdentifier("saveCorrection")
                }
            }
            .onAppear {
                if let reading = store.data.readings.first(where: { $0.id == readingId }) {
                    text = Format.editable(store.data.effectiveValues[reading.id] ?? reading.originalKwhValue)
                }
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let value = Format.parseDecimal(text) else {
            error = String(localized: "Enter a number, for example 12345.6.")
            return
        }
        do {
            switch try store.correctReading(id: readingId, newValue: value) {
            case .unchanged:
                dismiss()
            case .corrected(let openPromptId):
                if let openPromptId {
                    model.present(.regression(openPromptId))
                } else {
                    model.showToast(String(localized: "Corrected · \(store.data.status().result?.status.label ?? String(localized: "saved"))"), symbol: "checkmark")
                    dismiss()
                }
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
