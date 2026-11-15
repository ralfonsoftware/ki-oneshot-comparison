import SwiftUI

struct CompareTariffView: View {
    let repository: DataRepository
    @AppStorage("candidateBaseFee", store: UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)) private var baseFee = ""
    @AppStorage("candidatePrice", store: UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)) private var price = ""
    @AppStorage("candidateBonus", store: UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)) private var bonus = ""

    private var hasCandidateInput: Bool { !baseFee.isEmpty || !price.isEmpty || !bonus.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Compare a candidate")).font(.title2.bold())
            if let current = try? repository.currentTariff(), let status = try? EnergyEngine.status(repository: repository), status.paceToDate != nil {
                DecimalUnitField(title: String(localized: "Candidate base fee"), text: $baseFee, unit: String(localized: "per month"))
                    .accessibilityIdentifier("candidate-base")
                DecimalUnitField(title: String(localized: "Candidate price"), text: $price, unit: String(localized: "per kWh"))
                    .accessibilityIdentifier("candidate-price")
                DecimalUnitField(title: String(localized: "Switching bonus (optional)"), text: $bonus, unit: current.currency)
                if let comparison = comparison(current: current) {
                    Text(String(format: String(localized: "Based on an annual pace of %@ kWh."), EnergyFormat.kwh(comparison.annualPace)))
                        .font(.subheadline).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { signals(comparison, currency: current.currency) }
                        VStack(spacing: 12) { signals(comparison, currency: current.currency) }
                    }
                    if comparison.isLowConfidence {
                        Label(String(localized: "Your latest reading is old, so this comparison is less certain."), systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(DisplayStatus.trending.labelColor)
                    }
                } else if hasCandidateInput {
                    Text(String(localized: "Enter valid candidate values. The bonus is optional.")).font(.footnote).foregroundStyle(.secondary)
                }
            } else if (try? repository.currentTariff()) == nil {
                Text(String(localized: "Add your current tariff to compare.")).foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Log at least two readings to compare tariffs.")).foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func signals(_ comparison: TariffComparisonDisplay, currency: String) -> some View {
        ComparisonSignal(title: String(localized: "With bonus"), savings: comparison.includedSavings, worth: comparison.includedWorth, currency: currency)
        ComparisonSignal(title: String(localized: "Without bonus effect"), savings: comparison.normalizedSavings, worth: comparison.normalizedWorth, currency: currency)
    }

    private func comparison(current: Tariff) -> TariffComparisonDisplay? {
        guard hasCandidateInput else { return nil }
        guard let base = InputValidation.tariffBaseFee(baseFee), let priceValue = InputValidation.tariffPrice(price),
              let bonusValue = bonus.isEmpty ? 0 : InputValidation.nonNegative(bonus) else { return nil }
        return try? EnergyEngine.compare(repository: repository, current: current, candidateBaseFee: base, candidatePrice: priceValue, bonus: bonusValue)
    }
}

private struct ComparisonSignal: View {
    let title: String
    let savings: Decimal
    let worth: Bool
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: worth ? "checkmark.circle.fill" : "minus.circle")
                .font(.headline)
                .foregroundStyle(worth ? DisplayStatus.belowbaseline.labelColor : .secondary)
            Text(resultText).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text(worth ? String(localized: "Worth switching") : String(localized: "Not worth switching"))
                .font(.caption.weight(.semibold)).foregroundStyle(worth ? DisplayStatus.belowbaseline.labelColor : .secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier(title == "With bonus" ? "with-bonus-result" : "without-bonus-result")
    }

    private var resultText: String {
        if savings >= 0 {
            return String(format: String(localized: "Saves %@ / year"), EnergyFormat.money(savings, currency: currency))
        }
        return String(format: String(localized: "Costs %@ more / year"), EnergyFormat.money(-savings, currency: currency))
    }
}
