import Foundation

enum UndefinedStatusReason: Sendable {
    case needsReadings
    case needsBaseline
}

struct LiveStatus: Sendable {
    var status: DisplayStatus?
    var paceToDate: Decimal?
    var baselineToDate: Decimal?
    var thresholdToDate: Decimal?
    var annualThreshold: Decimal?
    var difference: Decimal?
    var elapsedDays: Decimal?
    var periodStart: Date?
    var periodEnd: Date?
    var isLowConfidence = false
    var daysSinceLastReading: Int?
    var lowConfidenceGapDays = 45
    var undefinedReason: UndefinedStatusReason?

    var isDefined: Bool { status != nil }

    var sentence: String {
        guard let status, let difference else {
            switch undefinedReason {
            case .needsBaseline: return String(localized: "Set your yearly target to see your status")
            default: return String(localized: "Log your first reading to get started")
            }
        }
        let amount = EnergyFormat.kwh(EnergyFormat.absolute(difference))
        switch status {
        case .withinrange:
            if difference >= 0 {
                return String(format: String(localized: "%@ kWh above baseline pace, still within your range"), amount)
            }
            return String(format: String(localized: "%@ kWh under baseline pace so far"), amount)
        case .belowbaseline:
            return String(format: String(localized: "%@ kWh under baseline pace so far"), amount)
        case .trending:
            return String(format: String(localized: "%@ kWh above baseline pace so far"), amount)
        }
    }

    var shortSentence: String {
        guard let status, let difference else { return String(localized: "Log a reading") }
        let amount = EnergyFormat.kwh(EnergyFormat.absolute(difference))
        switch status {
        case .withinrange where difference < 0, .belowbaseline:
            return String(format: String(localized: "%@ kWh under pace"), amount)
        case .withinrange:
            return String(format: String(localized: "%@ kWh over pace, in range"), amount)
        case .trending:
            return String(format: String(localized: "%@ kWh over pace"), amount)
        }
    }
}

enum DisplayDeviation {
    case bump
    case dip

    var sentence: String {
        switch self {
        case .bump: String(localized: "Usage was above baseline pace in the two weeks around this event.")
        case .dip: String(localized: "Usage was below baseline pace in the two weeks around this event.")
        }
    }
}

struct TariffComparisonDisplay {
    let annualPace: Decimal
    let currentAnnualCost: Decimal
    let candidateAnnualCost: Decimal
    let normalizedSavings: Decimal
    let includedSavings: Decimal
    let normalizedWorth: Bool
    let includedWorth: Bool
    let isLowConfidence: Bool
}

struct TariffCheckDisplay {
    let isDue: Bool
    let minimumTermEnd: Date?
    let nextDue: Date?
}

struct AttentionMessage: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}
