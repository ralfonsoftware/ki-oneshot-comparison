import Foundation

extension DataRepository {
    @discardableResult
    func startFresh(yearlyBaseline: Decimal?, currency: String) throws -> Household {
        guard let currency = InputValidation.currency(currency) else { throw RepositoryError.invalidTariff }
        let household = Household(currency: currency, yearlyBaselineKwh: yearlyBaseline)
        household.generationChangedAt = Date()
        context.insert(household)
        try save()
        return household
    }

    func setYearlyBaseline(_ value: Decimal?) throws {
        let household = try ensureHousehold()
        household.yearlyBaselineKwh = value.map(DecimalText.encode)
        household.yearlyBaselineUpdatedAt = Date()
        household.updatedAt = Date()
        try save()
    }

    func setTrendingThreshold(_ value: Decimal) throws {
        guard value >= 0 else { throw RepositoryError.invalidTariff }
        let household = try ensureHousehold()
        household.trendingThresholdKwh = DecimalText.encode(value)
        household.thresholdUpdatedAt = Date()
        household.updatedAt = Date()
        try save()
    }

    func setLowConfidenceGap(_ days: Int) throws {
        guard (1...365).contains(days) else { throw RepositoryError.invalidTariff }
        let household = try ensureHousehold()
        household.lowConfidenceGapDays = days
        household.gapUpdatedAt = Date()
        household.updatedAt = Date()
        try save()
    }

    func setCurrency(_ value: String) throws {
        guard let currency = InputValidation.currency(value) else { throw RepositoryError.invalidTariff }
        let household = try ensureHousehold()
        household.currency = currency
        household.currencyUpdatedAt = Date()
        household.updatedAt = Date()
        try save()
    }

    func setTariffCadence(_ months: Int) throws {
        guard (1...24).contains(months) else { throw RepositoryError.invalidTariff }
        let household = try ensureHousehold()
        household.tariffCheckCadenceMonths = months
        household.cadenceUpdatedAt = Date()
        household.updatedAt = Date()
        try save()
    }

    func markTariffCheckDone(at date: Date = Date()) throws {
        let household = try ensureHousehold()
        household.tariffCheckDoneAt = date
        household.tariffDoneUpdatedAt = Date()
        household.updatedAt = Date()
        try save()
    }

    // MARK: - Tariffs

    func tariffs() throws -> [Tariff] {
        guard let generation = try currentGeneration() else { return [] }
        return try fetch(Tariff.self)
            .filter { $0.generation == generation }
            .sorted { lhs, rhs in
                if lhs.contractStartDate != rhs.contractStartDate { return lhs.contractStartDate > rhs.contractStartDate }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    func currentTariff(today: Date = Date()) throws -> Tariff? {
        let todayString = CalendarDay.string(from: today)
        return try tariffs().first { $0.contractStartDate <= todayString }
    }

    func duplicateTariffGroups() throws -> [[Tariff]] {
        let groups = Dictionary(grouping: try tariffs(), by: \.contractStartDate)
        return groups.values.filter { $0.count > 1 }.sorted { ($0.first?.contractStartDate ?? "") < ($1.first?.contractStartDate ?? "") }
    }

    @discardableResult
    func addTariff(baseFee: Decimal, price: Decimal, currency: String, startDate: String, periodMonths: Int) throws -> Tariff {
        let household = try ensureHousehold()
        try validateTariff(baseFee: baseFee, price: price, currency: currency, startDate: startDate, periodMonths: periodMonths)
        guard try !tariffs().contains(where: { $0.contractStartDate == startDate }) else { throw RepositoryError.duplicateTariffStart }
        let tariff = Tariff(generation: household.generation, monthlyBaseFee: baseFee, pricePerKwh: price, currency: currency, contractStartDate: startDate, contractPeriodMonths: periodMonths)
        context.insert(tariff)
        try save()
        return tariff
    }

    func updateTariff(_ tariff: Tariff, baseFee: Decimal, price: Decimal, currency: String, startDate: String, periodMonths: Int) throws {
        try validateTariff(baseFee: baseFee, price: price, currency: currency, startDate: startDate, periodMonths: periodMonths)
        guard try !tariffs().contains(where: { $0.id != tariff.id && $0.contractStartDate == startDate }) else { throw RepositoryError.duplicateTariffStart }
        let changes: [(String, String, String)] = [
            ("MonthlyBaseFee", tariff.monthlyBaseFee, DecimalText.encode(baseFee)),
            ("PricePerKwh", tariff.pricePerKwh, DecimalText.encode(price)),
            ("Currency", tariff.currency, currency),
            ("ContractStartDate", tariff.contractStartDate, startDate),
            ("ContractPeriodMonths", String(tariff.contractPeriodMonths), String(periodMonths)),
        ].filter { $0.1 != $0.2 }
        for (field, old, new) in changes {
            context.insert(AuditCorrection(generation: tariff.generation, entityType: "Tariff", entityId: tariff.id, fieldName: field, oldValue: old, newValue: new))
        }
        tariff.monthlyBaseFee = DecimalText.encode(baseFee)
        tariff.pricePerKwh = DecimalText.encode(price)
        tariff.currency = currency
        tariff.contractStartDate = startDate
        tariff.contractPeriodMonths = periodMonths
        tariff.updatedAt = Date()
        try save()
    }

    func deleteTariff(_ tariff: Tariff) throws {
        context.delete(tariff)
        try save()
    }

    private func validateTariff(baseFee: Decimal, price: Decimal, currency: String, startDate: String, periodMonths: Int) throws {
        guard baseFee >= 0, baseFee < Decimal(sign: .plus, exponent: 15, significand: 1),
              price > 0, price < Decimal(sign: .plus, exponent: 13, significand: 1),
              InputValidation.currency(currency) != nil,
              (1...1200).contains(periodMonths),
              let date = CalendarDay.date(from: startDate),
              let lower = CalendarDay.date(from: "1900-01-01"), let upper = CalendarDay.date(from: "2200-01-01"),
              date >= lower, date <= upper else { throw RepositoryError.invalidTariff }
    }
}
