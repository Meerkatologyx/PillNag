import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.theme) private var theme
    @Query(sort: \Medication.sortOrder) private var allMeds: [Medication]
    @Query(sort: \DoseEvent.actionAt, order: .reverse) private var events: [DoseEvent]
    @State private var range = 14

    private var meds: [Medication] { allMeds.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            ScrollView {
                let now = Date.now
                let summaries = DoseBoard.summaries(days: range, meds: meds, events: events, now: now)
                let streaks = DoseBoard.streaks(meds: meds, events: events, now: now)
                let scheduled = summaries.reduce(0) { $0 + $1.scheduled }
                let taken = summaries.reduce(0) { $0 + $1.taken }

                VStack(spacing: 16) {
                    Picker("Range", selection: $range.animation(.snappy)) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        StatTile(title: "current streak", value: "\(streaks.current)", symbol: "flame.fill", tint: .orange)
                        StatTile(title: "best streak", value: "\(streaks.best)", symbol: "trophy.fill", tint: .yellow)
                        StatTile(title: "adherence",
                                 value: scheduled == 0 ? "—" : "\(Int((Double(taken) / Double(scheduled) * 100).rounded()))%",
                                 symbol: "chart.pie.fill", tint: theme.accent)
                    }

                    chart(summaries)

                    ForEach(Array(summaries.reversed())) { summary in
                        let items = DoseBoard.items(on: summary.day, meds: meds, events: events, now: now)
                            .filter { $0.state != .upcoming }
                        if !items.isEmpty {
                            DayCard(day: summary.day, items: items, summary: summary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background { AppBackground() }
            .navigationTitle("History")
        }
    }

    private func chart(_ summaries: [DoseBoard.DaySummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily adherence").font(.headline)
            Chart(summaries) { s in
                BarMark(
                    x: .value("Day", s.day, unit: .day),
                    y: .value("Taken", (s.adherence ?? 0) * 100)
                )
                .foregroundStyle(s.isComplete ? theme.accent.gradient : Color.orange.gradient)
                .cornerRadius(5)
                .opacity(s.scheduled == 0 ? 0.2 : 1)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))%") } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range > 14 ? 5 : (range > 7 ? 2 : 1))) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .frame(height: 160)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: range)
        }
        .padding(16)
        .cardGlass(cornerRadius: 26)
    }
}

private struct DayCard: View {
    let day: Date
    let items: [DoseItem]
    let summary: DoseBoard.DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if summary.isComplete {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                } else if summary.scheduled > 0 {
                    Text("\(summary.taken)/\(summary.scheduled)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(items) { item in
                HStack(spacing: 10) {
                    if let med = item.medication {
                        PillView(med: med, size: 26)
                    } else {
                        Circle().fill(Color(hex: item.colorHex)).frame(width: 14, height: 14).frame(width: 26)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.medName).font(.subheadline.weight(.medium))
                        Text(item.scheduledAt.map { $0.shortTime } ?? "As needed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StateBadge(state: item.state)
                }
            }
        }
        .padding(14)
        .cardGlass(cornerRadius: 24)
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}
