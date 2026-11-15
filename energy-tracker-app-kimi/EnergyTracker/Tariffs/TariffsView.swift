import SwiftUI
import SwiftData

struct TariffsView: View {
    let repository: DataRepository
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var router: AppRouter
    @Query private var observedTariffs: [Tariff]
    @State private var editing: Tariff?
    @State private var showAdd = false
    @State private var deleting: Tariff?
    @State private var pendingDuplicateDelete: Tariff?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    tariffCheckLine
                    duplicateCards
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 18) { currentCard; historyCard }.frame(maxWidth: .infinity)
                            CompareTariffView(repository: repository).frame(maxWidth: .infinity)
                        }
                    } else {
                        currentCard
                        CompareTariffView(repository: repository)
                        historyCard
                    }
                }
                .padding()
                .frame(maxWidth: 1100)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "Tariffs"))
            .toolbar { Button(String(localized: "Add tariff"), systemImage: "plus") { showAdd = true } }
            .sheet(isPresented: $showAdd) {
                TariffFormView(repository: repository).environmentObject(router)
            }
            .sheet(item: $editing) { tariff in
                TariffFormView(repository: repository, tariff: tariff).environmentObject(router)
            }
            .confirmationDialog(String(localized: "Delete this tariff? Its correction notes will be kept."), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(String(localized: "Delete tariff"), role: .destructive) {
                    if let deleting { try? repository.deleteTariff(deleting) }
                    deleting = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { deleting = nil }
            }
            .confirmationDialog(String(localized: "Keep this tariff and delete the other entry with the same start date?"), isPresented: Binding(get: { pendingDuplicateDelete != nil }, set: { if !$0 { pendingDuplicateDelete = nil } })) {
                Button(String(localized: "Keep this tariff"), role: .destructive) {
                    if let pendingDuplicateDelete { try? repository.deleteTariff(pendingDuplicateDelete) }
                    pendingDuplicateDelete = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { pendingDuplicateDelete = nil }
            }
            .onAppear { _ = observedTariffs.count }
        }
    }

    @ViewBuilder
    private var tariffCheckLine: some View {
        if let check = try? EnergyEngine.tariffCheck(repository: repository) {
            HStack {
                Label(check.isDue ? String(localized: "Tariff check — due now") : check.nextDue.map { String(format: String(localized: "Tariff check — nothing due until %@"), $0.formatted(date: .abbreviated, time: .omitted)) } ?? String(localized: "Add your current tariff to enable tariff checks."), systemImage: "calendar")
                Spacer()
                if check.isDue { Button(String(localized: "Done")) { try? repository.markTariffCheckDone() } }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var duplicateCards: some View {
        if let groups = try? repository.duplicateTariffGroups() {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: String(localized: "Two tariffs start on %@ — keep one"), CalendarDay.date(from: group.first?.contractStartDate ?? "")?.formatted(date: .abbreviated, time: .omitted) ?? ""))
                        .font(.headline)
                    ForEach(group, id: \.id) { tariff in
                        HStack {
                            Text(tariffSummary(tariff)).font(.subheadline)
                            Spacer()
                            Button(String(localized: "Keep")) {
                                if let other = group.first(where: { $0.id != tariff.id }) { pendingDuplicateDelete = other }
                            }
                        }
                    }
                }
                .glassCard()
            }
        }
    }

    @ViewBuilder
    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Current tariff")).font(.title2.bold())
            if let tariff = try? repository.currentTariff() {
                Button { editing = tariff } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tariffSummary(tariff)).font(.headline).foregroundStyle(.primary)
                        Text(String(format: String(localized: "Started %@ · %lld-month minimum term"), CalendarDay.date(from: tariff.contractStartDate)?.formatted(date: .abbreviated, time: .omitted) ?? tariff.contractStartDate, tariff.contractPeriodMonths))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("current-tariff")
            } else {
                Text(String(localized: "No current tariff. Add the contract that applies today.")).foregroundStyle(.secondary)
                Button(String(localized: "Add current tariff")) { showAdd = true }.buttonStyle(.bordered)
            }
        }
        .glassCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Tariff history")).font(.title2.bold())
            if let tariffs = try? repository.tariffs(), !tariffs.isEmpty {
                ForEach(tariffs, id: \.id) { tariff in
                    HStack(alignment: .top) {
                        Button { editing = tariff } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CalendarDay.date(from: tariff.contractStartDate)?.formatted(date: .abbreviated, time: .omitted) ?? tariff.contractStartDate).foregroundStyle(.primary)
                                Text(tariffSummary(tariff)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button(String(localized: "Delete tariff"), systemImage: "trash") { deleting = tariff }
                            .labelStyle(.iconOnly).foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    if tariff.id != tariffs.last?.id { Divider() }
                }
            } else {
                Text(String(localized: "No tariffs yet.")).foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private func tariffSummary(_ tariff: Tariff) -> String {
        let base = DecimalText.decode(tariff.monthlyBaseFee) ?? 0
        let price = DecimalText.decode(tariff.pricePerKwh) ?? 0
        return String(format: String(localized: "%@/month · %@/kWh"), EnergyFormat.money(base, currency: tariff.currency), EnergyFormat.price(price, currency: tariff.currency))
    }
}

extension Tariff: Identifiable {}
