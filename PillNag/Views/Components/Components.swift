import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.6), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: value)
            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardGlass(cornerRadius: 22)
    }
}

struct StreakChip: View {
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange.gradient)
                .symbolEffect(.bounce, value: days)
            Text("\(days)")
                .contentTransition(.numericText(value: Double(days)))
                .fontWeight(.bold)
            Text(days == 1 ? "day" : "days")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .capsuleGlass(tint: days > 0 ? Color.orange.opacity(0.5) : nil)
        .animation(.snappy, value: days)
    }
}

struct StateBadge: View {
    let state: DoseState

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: .capsule)
            .contentTransition(.symbolEffect(.replace))
    }

    private var text: String {
        switch state {
        case .upcoming: "Upcoming"
        case .due: "Due now"
        case .overdue: "Overdue"
        case .snoozed(let until): "Snoozed · \(until.shortTime)"
        case .taken(let at): "Taken · \(at.shortTime)"
        case .skipped: "Skipped"
        case .missed: "Missed"
        }
    }

    private var symbol: String {
        switch state {
        case .upcoming: "clock"
        case .due: "bell.badge.fill"
        case .overdue: "exclamationmark.circle.fill"
        case .snoozed: "zzz"
        case .taken: "checkmark.circle.fill"
        case .skipped: "arrow.uturn.right.circle"
        case .missed: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .upcoming: .secondary
        case .due: .blue
        case .overdue: .red
        case .snoozed: .purple
        case .taken: .green
        case .skipped: .gray
        case .missed: .red
        }
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text).font(.title3.bold())
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

struct LowSupplyBanner: View {
    let med: Medication
    var onRefill: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(med.name) is running low").font(.subheadline.bold())
                Text(supplyText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refill", action: onRefill)
                .buttonStyle(.glassProminent)
                .tint(.orange)
        }
        .padding(14)
        .cardGlass(cornerRadius: 22, tint: Color.orange.opacity(0.4))
    }

    private var supplyText: String {
        var text = "\(med.pillsRemaining) left"
        if let days = med.daysOfSupplyLeft { text += " · about \(days) day\(days == 1 ? "" : "s")" }
        return text
    }
}
