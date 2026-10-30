import SwiftUI
import SwiftData

extension DoseState {
    var isTaken: Bool {
        if case .taken = self { return true }
        return false
    }

    var needsAttention: Bool {
        switch self {
        case .due, .overdue: return true
        case .snoozed(let until): return until <= .now
        default: return false
        }
    }
}

struct TodayView: View {
    @Environment(\.theme) private var theme
    @Query(sort: \Medication.sortOrder) private var allMeds: [Medication]
    @Query(sort: \DoseEvent.actionAt, order: .reverse) private var events: [DoseEvent]

    @State private var showAdd = false
    @State private var refillMed: Medication?
    @State private var feedbackTick = 0

    private var meds: [Medication] { allMeds.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
            .background { AppBackground() }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add medication")
                }
            }
            .sheet(isPresented: $showAdd) { MedEditorView(med: nil) }
            .sheet(item: $refillMed) { RefillSheet(med: $0) }
            .sensoryFeedback(.success, trigger: feedbackTick)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let items = DoseBoard.items(on: now, meds: meds, events: events, now: now)
        let scheduled = items.filter { $0.scheduledAt != nil }
        let streak = DoseBoard.streaks(meds: meds, events: events, now: now).current
        let lowSupply = meds.filter(\.isLowSupply)
        let asNeeded = meds.filter { $0.scheduleKind == .asNeeded }

        ScrollView {
            LazyVStack(spacing: 16) {
                if meds.isEmpty {
                    EmptyMedsCard { showAdd = true }
                } else {
                    TodayHeader(now: now, done: scheduled.filter { $0.state.isTaken }.count,
                                total: scheduled.count, streak: streak)

                    if let next = nextUp(scheduled) {
                        DoseCard(item: next, now: now, prominent: true, onAction: { feedbackTick += 1 })
                            .transition(.blurReplace)
                    }

                    ForEach(lowSupply) { med in
                        LowSupplyBanner(med: med) { refillMed = med }
                    }

                    if !scheduled.isEmpty {
                        SectionTitle("Schedule", trailing: "\(scheduled.count) dose\(scheduled.count == 1 ? "" : "s")")
                        ForEach(scheduled) { item in
                            DoseCard(item: item, now: now, prominent: false, onAction: { feedbackTick += 1 })
                        }
                    }

                    if !asNeeded.isEmpty {
                        SectionTitle("As needed")
                        ForEach(asNeeded) { med in
                            AsNeededCard(med: med, takenToday: items.filter { $0.medID == med.id && $0.scheduledAt == nil })
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: items.map { "\($0.id)\($0.state)" })
        }
    }

    private func nextUp(_ items: [DoseItem]) -> DoseItem? {
        items.first { $0.state.needsAttention } ?? items.first { $0.state.isActionable }
    }
}

// MARK: - Header

private struct TodayHeader: View {
    @Environment(\.theme) private var theme
    let now: Date
    let done: Int
    let total: Int
    let streak: Int

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: total == 0 ? 1 : Double(done) / Double(total), lineWidth: 11, tint: theme.accent)
                VStack(spacing: 0) {
                    Text("\(done)/\(total)")
                        .font(.title3.bold())
                        .contentTransition(.numericText(value: Double(done)))
                    Text("taken").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                Text(greeting).font(.title2.bold())
                Text(now.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StreakChip(days: streak)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .cardGlass(cornerRadius: 30)
        .animation(.snappy, value: done)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello, night owl"
        }
    }
}

// MARK: - Dose card

struct DoseCard: View {
    @Environment(\.theme) private var theme
    let item: DoseItem
    let now: Date
    var prominent: Bool
    var onAction: () -> Void = {}

    @Namespace private var glassNS

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let med = item.medication {
                    MedBadge(med: med, size: prominent ? 64 : 48)
                } else {
                    Circle().fill(Color(hex: item.colorHex).gradient).frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if prominent {
                        Text(item.state.needsAttention ? "Take now" : "Up next")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.accent)
                    }
                    Text(item.medName).font(prominent ? .title3.bold() : .headline)
                    HStack(spacing: 6) {
                        if !item.medDose.isEmpty { Text(item.medDose) }
                        if let at = item.scheduledAt { Text("·"); Text(at.shortTime) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if item.state.needsAttention {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .foregroundStyle(item.state == .overdue ? .red : theme.accent)
                        .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.5)))
                }
            }

            actions
        }
        .padding(prominent ? 18 : 14)
        .cardGlass(cornerRadius: prominent ? 30 : 24,
                   tint: prominent && item.state.needsAttention ? theme.accent.opacity(0.5) : nil)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if item.state.isActionable {
                    GlassActionButton(title: "Taken", symbol: "checkmark", tint: theme.accent, prominent: true) {
                        perform { if let med = item.medication { DoseActions.markTaken(med, scheduledAt: item.scheduledAt) } }
                    }
                    .glassEffectID("primary", in: glassNS)

                    if let at = item.scheduledAt, item.state != .upcoming {
                        GlassActionButton(title: "Snooze", symbol: "zzz") {
                            perform { if let med = item.medication { DoseActions.snooze(med, scheduledAt: at) } }
                        }
                        .glassEffectID("snooze", in: glassNS)
                    }

                    if let at = item.scheduledAt {
                        GlassActionButton(title: "Skip", symbol: "forward.end") {
                            perform { if let med = item.medication { DoseActions.skip(med, scheduledAt: at) } }
                        }
                        .glassEffectID("skip", in: glassNS)
                    }
                    Spacer(minLength: 0)
                    StateBadge(state: item.state)
                } else {
                    StateBadge(state: item.state)
                        .glassEffectID("primary", in: glassNS)
                    Spacer(minLength: 0)
                    if let event = item.event {
                        GlassActionButton(title: "Undo", symbol: "arrow.uturn.backward") {
                            perform { DoseActions.undo(event) }
                        }
                        .glassEffectID("undo", in: glassNS)
                    }
                }
            }
        }
    }

    private func perform(_ action: () -> Void) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { action() }
        onAction()
    }
}

/// Capsule glass button that participates in glass morphing.
struct GlassActionButton: View {
    let title: String
    let symbol: String
    var tint: Color?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(prominent ? .regular.tint(tint).interactive() : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - As needed

private struct AsNeededCard: View {
    @Environment(\.theme) private var theme
    let med: Medication
    let takenToday: [DoseItem]
    @State private var tick = 0

    var body: some View {
        HStack(spacing: 14) {
            MedBadge(med: med, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(med.name).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.bouncy) { DoseActions.markTaken(med, scheduledAt: nil) }
                tick += 1
            } label: {
                Label("Take", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .sensoryFeedback(.success, trigger: tick)
        }
        .padding(14)
        .cardGlass(cornerRadius: 24)
    }

    private var subtitle: String {
        let count = takenToday.count
        if let last = takenToday.map(\.displayTime).max() {
            return "\(count)× today · last \(last.shortTime)"
        }
        return med.dose.isEmpty ? "Not taken today" : "\(med.dose) · not taken today"
    }
}

// MARK: - Empty state

struct EmptyMedsCard: View {
    @Environment(\.theme) private var theme
    var onAdd: () -> Void
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pills.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.accent.gradient)
                .symbolEffect(.bounce, value: bounce)
            Text("No medications yet").font(.title3.bold())
            Text("Add your first medication and PillNag will make sure you never forget it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label("Add medication", systemImage: "plus").padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardGlass(cornerRadius: 32)
        .padding(.top, 40)
        .onAppear { bounce.toggle() }
    }
}
