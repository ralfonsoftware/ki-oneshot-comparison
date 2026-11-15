import SwiftUI

struct TariffFormView: View {
    let repository: DataRepository
    var tariff: Tariff?
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var baseFee = ""
    @State private var price = ""
    @State private var currency = "EUR"
    @State private var startDate = Date()
    @State private var periodMonths = 12
    @State private var errorMessage: String?
    @State private var confirmStartedContract = false

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Flat-rate tariff")) {
                    DecimalUnitField(title: String(localized: "Monthly base fee"), text: $baseFee, unit: String(localized: "per month"))
                    DecimalUnitField(title: String(localized: "Price per kWh"), text: $price, unit: String(localized: "per kWh"))
                    DecimalUnitField(title: String(localized: "Currency"), text: $currency, unit: String(localized: "ISO code"), keyboard: .default)
                        .textInputAutocapitalization(.characters)
                    DatePicker(String(localized: "Contract start"), selection: $startDate, displayedComponents: .date)
                    Stepper(value: $periodMonths, in: 1...1200) {
                        LabeledContent(String(localized: "Contract Period"), value: String(format: String(localized: "%lld months"), periodMonths))
                    }
                }
                if let tariff, let corrections = try? repository.corrections(entityType: "Tariff", entityId: tariff.id), !corrections.isEmpty {
                    Section(String(localized: "Correction notes")) {
                        ForEach(corrections.reversed(), id: \.id) { correction in
                            VStack(alignment: .leading) {
                                Text("\(localizedField(correction.fieldName)): \(correction.oldValue) → \(correction.newValue)")
                                Text(correction.correctedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(tariff == nil ? String(localized: "Add tariff") : String(localized: "Edit tariff"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Save"), action: requestSave).accessibilityIdentifier("save-tariff") }
            }
            .onAppear {
                currency = (try? repository.activeHouseholdRecord()?.currency) ?? currency
                if let tariff {
                    baseFee = tariff.monthlyBaseFee; price = tariff.pricePerKwh; currency = tariff.currency
                    startDate = CalendarDay.date(from: tariff.contractStartDate) ?? Date()
                    periodMonths = tariff.contractPeriodMonths
                }
            }
            .confirmationDialog(String(localized: "This contract already started. Change its prices anyway?"), isPresented: $confirmStartedContract) {
                Button(String(localized: "Change tariff"), role: .destructive, action: save)
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
        }
    }

    private func localizedField(_ field: String) -> String {
        switch field {
        case "MonthlyBaseFee": String(localized: "Monthly base fee")
        case "PricePerKwh": String(localized: "Price per kWh")
        case "Currency": String(localized: "Currency")
        case "ContractStartDate": String(localized: "Contract start")
        case "ContractPeriodMonths": String(localized: "Contract Period")
        default: field
        }
    }

    private func requestSave() {
        guard valuesAreValid else { errorMessage = RepositoryError.invalidTariff.localizedDescription; return }
        if let tariff, tariff.contractStartDate < CalendarDay.string(from: Date()) {
            let changedPrices = tariff.monthlyBaseFee != DecimalText.encode(DecimalText.decode(baseFee) ?? -1)
                || tariff.pricePerKwh != DecimalText.encode(DecimalText.decode(price) ?? -1)
                || tariff.contractStartDate != CalendarDay.string(from: startDate)
            if changedPrices { confirmStartedContract = true; return }
        }
        save()
    }

    private var valuesAreValid: Bool {
        InputValidation.tariffBaseFee(baseFee) != nil && InputValidation.tariffPrice(price) != nil
            && InputValidation.currency(currency) != nil && CalendarDay.date(from: CalendarDay.string(from: startDate)) != nil
    }

    private func save() {
        do {
            guard let base = InputValidation.tariffBaseFee(baseFee), let priceValue = InputValidation.tariffPrice(price),
                  let currencyValue = InputValidation.currency(currency) else { throw RepositoryError.invalidTariff }
            if let tariff {
                try repository.updateTariff(tariff, baseFee: base, price: priceValue, currency: currencyValue, startDate: CalendarDay.string(from: startDate), periodMonths: periodMonths)
            } else {
                _ = try repository.addTariff(baseFee: base, price: priceValue, currency: currencyValue, startDate: CalendarDay.string(from: startDate), periodMonths: periodMonths)
            }
            NotificationScheduler.rebuildIfEnabled(repository: repository)
            router.confirmation = String(localized: "Tariff saved")
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
