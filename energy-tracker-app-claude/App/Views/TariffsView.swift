import SwiftUI
import EnergyCore

struct TariffsView: View {
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { proxy in
            // iPad landscape: tariff and history left, Compare right (§9.2).
            if sizeClass == .regular, proxy.size.width > proxy.size.height, proxy.size.width >= 700 {
                HStack(alignment: .top, spacing: 0) {
                    List { overviewSections }
                        .frame(width: proxy.size.width * 0.45)
                    Divider()
                    List { CompareSection() }
                }
            } else {
                ScrollViewReader { reader in
                    List {
                        overviewSections
                        CompareSection().id("compare")
                    }
                    .onChange(of: model.showCompare, initial: true) { _, show in
                        if show {
                            withAnimation { reader.scrollTo("compare", anchor: .top) }
                            model.showCompare = false
                        }
                    }
                }
            }
        }
        .navigationTitle(AppSection.tariffs.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.present(.addTariff)
                } label: {
                    Label("Add tariff", systemImage: "plus")
                }
                .accessibilityIdentifier("addTariff")
            }
        }
    }

    @ViewBuilder
    private var overviewSections: some View {
        let data = store.data
        Section {
            TariffCheckLine()
        }
        Section("Current tariff") {
            if let tariff = data.currentTariff {
                NavigationLink {
                    TariffDetailView(tariffId: tariff.id)
                } label: {
                    TariffSummary(tariff: tariff, isCurrent: true)
                }
            } else {
                Text("Add your current tariff to compare.")
                    .foregroundStyle(.secondary)
                Button("Add tariff") { model.present(.addTariff) }
            }
        }
        let history = data.tariffs.sorted { ($0.contractStartDate, $0.createdAt) > ($1.contractStartDate, $1.createdAt) }
        if history.count > 1 || (history.count == 1 && data.currentTariff == nil) {
            Section("History") {
                ForEach(history.filter { $0.id != data.currentTariff?.id }) { tariff in
                    NavigationLink {
                        TariffDetailView(tariffId: tariff.id)
                    } label: {
                        TariffSummary(tariff: tariff, isCurrent: false)
                    }
                }
            }
        }
    }
}

struct TariffCheckLine: View {
    @Environment(EnergyStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        if let check = store.data.tariffCheck() {
            if check.isDue {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Time to check your tariff — your minimum term ends on \(Format.date(check.minimumTermEnd))"), systemImage: "calendar.badge.clock")
                    Button("Done") {
                        do { try store.markTariffCheckDone() } catch { model.showError(error) }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Label(String(localized: "Tariff check — nothing due until \(Format.date(check.dueDate))"), systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Tariff check — add your current tariff first.", systemImage: "calendar")
                .foregroundStyle(.secondary)
        }
    }
}

struct TariffSummary: View {
    var tariff: Tariff
    var isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Format.pricePerKwh(tariff.pricePerKwh, currency: tariff.currency)) / kWh")
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(Format.money(tariff.monthlyBaseFee, currency: tariff.currency)) / month")
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "From \(Format.date(tariff.contractStartDate)) · minimum term \(tariff.contractPeriodMonths) months"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TariffDetailView: View {
    var tariffId: UUID
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        if let tariff = store.data.tariffs.first(where: { $0.id == tariffId }) {
            let corrections = (store.data.correctionsByEntity[tariff.id] ?? []).filter { $0.entityType == AuditEntityType.tariff }.sorted { $0.correctedAt > $1.correctedAt }
            List {
                Section {
                    LabeledContent("Price per kWh", value: Format.pricePerKwh(tariff.pricePerKwh, currency: tariff.currency))
                    LabeledContent("Base fee per month", value: Format.money(tariff.monthlyBaseFee, currency: tariff.currency))
                    LabeledContent("Currency", value: tariff.currency)
                    LabeledContent("Contract start", value: Format.date(tariff.contractStartDate))
                    LabeledContent("Minimum term", value: String(localized: "\(tariff.contractPeriodMonths) months"))
                    LabeledContent("Minimum term ends", value: Format.date(tariff.contractStartDate.adding(months: tariff.contractPeriodMonths)))
                }
                if !corrections.isEmpty {
                    Section("Changes") {
                        ForEach(corrections) { c in
                            VStack(alignment: .leading) {
                                Text(correctionText(c, currency: tariff.currency))
                                Text(Format.dateTime(c.correctedAt)).font(.footnote).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section {
                    Button("Edit") { model.present(.editTariff(tariff.id)) }
                    Button("Delete tariff", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Tariff")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this tariff?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do {
                        try store.deleteTariff(id: tariff.id)
                        dismiss()
                    } catch { model.showError(error) }
                }
            } message: {
                Text("Its change history is kept.")
            }
        } else {
            ContentUnavailableView("Tariff not found", systemImage: "questionmark")
        }
    }

    private func correctionText(_ c: AuditCorrection, currency: String) -> String {
        func money(_ s: String, places: Int) -> String { DecimalMath.parse(s).map { Format.money($0, currency: currency, places: places) } ?? s }
        func date(_ s: String) -> String { CalendarDate(iso: s).map { Format.date($0) } ?? s }
        switch c.fieldName {
        case AuditField.monthlyBaseFee: return String(localized: "Base fee changed from \(money(c.oldValue, places: 2)) to \(money(c.newValue, places: 2))")
        case AuditField.pricePerKwh: return String(localized: "Price per kWh changed from \(money(c.oldValue, places: 4)) to \(money(c.newValue, places: 4))")
        case AuditField.contractStartDate: return String(localized: "Start date changed from \(date(c.oldValue)) to \(date(c.newValue))")
        case AuditField.contractPeriodMonths: return String(localized: "Minimum term changed from \(c.oldValue) to \(c.newValue) months")
        case AuditField.currency: return String(localized: "Currency changed from \(c.oldValue) to \(c.newValue)")
        default: return "\(c.fieldName): \(c.oldValue) → \(c.newValue)"
        }
    }
}

// MARK: - Add or edit a tariff (FR-12)

struct TariffEditorSheet: View {
    var tariffId: UUID?
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var fee = ""
    @State private var price = ""
    @State private var currency = ""
    @State private var start = Date()
    @State private var months = 12
    @State private var error: String?
    @State private var confirmStarted = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    UnitField(title: "Price per kWh", text: $price, unit: "\(Format.currencySymbol(currency))/kWh", identifier: "priceField")
                    UnitField(title: "Base fee", text: $fee, unit: "\(Format.currencySymbol(currency))/\(String(localized: "month"))", identifier: "feeField")
                    Picker("Currency", selection: $currency) {
                        ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    DatePicker("Contract start", selection: $start, displayedComponents: .date)
                    Stepper(value: $months, in: 1...1_200) {
                        LabeledContent("Minimum term", value: String(localized: "\(months) months"))
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(Theme.error) } else {
                        Text("The minimum term is not an end date. The tariff applies until the next tariff starts.")
                    }
                }
            }
            .navigationTitle(tariffId == nil ? String(localized: "Add tariff") : String(localized: "Edit tariff"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }.accessibilityIdentifier("saveTariff")
                }
            }
            .confirmationDialog("This contract already started. Change its prices anyway?", isPresented: $confirmStarted, titleVisibility: .visible) {
                Button("Change") { save() }
            }
            .onAppear(perform: load)
        }
    }

    private var currencyChoices: [String] {
        var codes = ["EUR", "CHF", "GBP", "USD", "DKK", "SEK", "NOK", "PLN", "CZK"]
        let household = store.data.currency
        if !codes.contains(household) { codes.insert(household, at: 0) }
        if !currency.isEmpty, !codes.contains(currency) { codes.insert(currency, at: 0) }
        return codes
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let tariffId, let t = store.data.tariffs.first(where: { $0.id == tariffId }) {
            fee = Format.editable(t.monthlyBaseFee)
            price = Format.editable(t.pricePerKwh)
            currency = t.currency
            start = t.contractStartDate.startDate() ?? Date()
            months = t.contractPeriodMonths
        } else {
            currency = store.data.currency
        }
    }

    private func draft() -> EnergyStore.TariffDraft? {
        guard let feeValue = Format.parseDecimal(fee), let priceValue = Format.parseDecimal(price) else {
            error = String(localized: "Enter the price per kWh and the base fee as numbers.")
            return nil
        }
        return EnergyStore.TariffDraft(monthlyBaseFee: feeValue, pricePerKwh: priceValue, currency: currency,
                                       contractStartDate: CalendarDate(date: start), contractPeriodMonths: months)
    }

    private func attemptSave() {
        guard let draft = draft() else { return }
        if let tariffId, let t = store.data.tariffs.first(where: { $0.id == tariffId }), t.contractStartDate <= CalendarDate.today(),
           t.monthlyBaseFee != draft.monthlyBaseFee || t.pricePerKwh != draft.pricePerKwh || t.contractStartDate != draft.contractStartDate {
            confirmStarted = true
            return
        }
        save()
    }

    private func save() {
        guard let draft = draft() else { return }
        do {
            if let tariffId { try store.updateTariff(id: tariffId, draft) } else { try store.addTariff(draft) }
            model.showToast(String(localized: "Tariff saved"), symbol: "checkmark")
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// "Two tariffs start on 1 Jan 2026 — keep one" (FR-12).
struct DuplicateTariffsSheet: View {
    var date: CalendarDate
    @Environment(AppModel.self) private var model
    @Environment(EnergyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var keep: UUID?

    var body: some View {
        NavigationStack {
            let tariffs = store.data.tariffs.filter { $0.contractStartDate == date }
            List {
                Section {
                    ForEach(tariffs) { t in
                        Button {
                            keep = t.id
                        } label: {
                            HStack {
                                TariffSummary(tariff: t, isCurrent: false)
                                Image(systemName: "checkmark").opacity(keep == t.id ? 1 : 0).foregroundStyle(Theme.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Two tariffs start on \(Format.date(date)) — keep one")
                }
            }
            .navigationTitle("Keep one tariff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            }
            .confirmationDialog("Delete the other tariff?", isPresented: Binding(get: { keep != nil }, set: { if !$0 { keep = nil } }), titleVisibility: .visible) {
                Button("Keep selected, delete the other", role: .destructive) {
                    do {
                        for t in tariffs where t.id != keep { try store.deleteTariff(id: t.id) }
                        dismiss()
                    } catch { model.showError(error) }
                }
            }
        }
    }
}

// MARK: - Compare a candidate tariff (FR-13)

struct CompareSection: View {
    @Environment(EnergyStore.self) private var store
    // The last candidate is remembered on this Apple device only, never synced.
    @AppStorage("candidateFee") private var fee = ""
    @AppStorage("candidatePrice") private var price = ""
    @AppStorage("candidateBonus") private var bonus = ""

    var body: some View {
        let data = store.data
        let currency = data.currentTariff?.currency ?? data.currency
        let symbol = Format.currencySymbol(currency)
        Section {
            UnitField(title: "Price per kWh", text: $price, unit: "\(symbol)/kWh", identifier: "candidatePrice")
            UnitField(title: "Base fee", text: $fee, unit: "\(symbol)/\(String(localized: "month"))", identifier: "candidateFee")
            UnitField(title: "Switching bonus (optional)", text: $bonus, unit: symbol, identifier: "candidateBonus")
        } header: {
            Text("Compare a candidate tariff")
        }
        Section {
            result(data: data, currency: currency)
        }
    }

    @ViewBuilder
    private func result(data: LoadedDataSet, currency: String) -> some View {
        if let current = data.currentTariff {
            if let pace = data.pace() {
                if let feeValue = Format.parseDecimal(fee), let priceValue = Format.parseDecimal(price) {
                    let bonusValue = bonus.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : (Format.parseDecimal(bonus) ?? 0)
                    let lowConfidence = Pace.isLowConfidence(latestReading: pace.windowEnd, now: Date(), gapDays: data.household?.lowConfidenceGapDays ?? 45)
                    let comparison = TariffComparator.compare(pace: pace, isLowConfidence: lowConfidence,
                                                              current: TariffPrice(monthlyBaseFee: current.monthlyBaseFee, pricePerKwh: current.pricePerKwh),
                                                              candidate: TariffPrice(monthlyBaseFee: feeValue, pricePerKwh: priceValue), bonus: bonusValue)
                    ComparisonResultView(comparison: comparison, currency: currency)
                    if lowConfidence {
                        Label("Based on an older reading — the result is less certain.", systemImage: "questionmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enter the candidate's price per kWh and base fee.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Log at least two readings to compare tariffs.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Add your current tariff to compare.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Both signals side by side, always together, never as a toggle.
struct ComparisonResultView: View {
    var comparison: TariffComparison
    var currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("At your pace of \(Format.kwhWhole(comparison.annualPaceKwh)) kWh a year, your current tariff costs \(Format.money(comparison.currentAnnualCost, currency: currency)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { signals }
                VStack(alignment: .leading, spacing: 12) { signals }
            }
        }
        .accessibilityIdentifier("comparisonResult")
    }

    @ViewBuilder
    private var signals: some View {
        SignalView(title: String(localized: "With bonus"), savings: comparison.includedSavingsRounded, worth: comparison.includedWorthSwitching, currency: currency)
        SignalView(title: String(localized: "Without bonus effect"), savings: comparison.normalizedSavingsRounded, worth: comparison.normalizedWorthSwitching, currency: currency)
    }
}

struct SignalView: View {
    var title: String
    var savings: Decimal
    var worth: Bool
    var currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(savingsText).font(.body)
            Label(worth ? String(localized: "Worth switching") : String(localized: "Not worth switching"),
                  systemImage: worth ? "checkmark.circle.fill" : "minus.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(worth ? Theme.labelColor(.belowBaseline) : Color.secondary)
        }
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background((worth ? Theme.color(.belowBaseline) : Color.gray).opacity(Theme.tintOpacity), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var savingsText: String {
        if savings > 0 { return String(localized: "saves \(Format.money(savings, currency: currency)) / year") }
        if savings < 0 { return String(localized: "costs \(Format.money(-savings, currency: currency)) more / year") }
        return String(localized: "saves nothing")
    }
}
