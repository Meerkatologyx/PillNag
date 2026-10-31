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
                        DoseCard(item: next, onAction: { feedbackTick += 1 })
                            .transition(.blurReplace)
                    }

                    ForEach(lowSupply) { med in
                        LowSupplyBanner(med: med) { refillMed = med }
                    }

                    if !scheduled.isEmpty {
                        SectionTitle("Schedule", trailing: "\(scheduled.count) dose\(scheduled.count == 1 ? "" : "s")")
                        VStack(spacing: 0) {
                            ForEach(scheduled) { item in
                                DoseRow(item: item, onAction: { feedbackTick += 1 })
                                if item.id != scheduled.last?.id {
                                    Divider().padding(.leading, 70)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .cardGlass(cornerRadius: 26)
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

// MARK: - Dose card (hero)

/// The big "up next" card with full-width actions.
struct DoseCard: View {
    @Environment(\.theme) private var theme
    let item: DoseItem
    var onAction: () -> Void = {}

    @Namespace private var glassNS

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                DoseBadge(item: item, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.state.needsAttention ? "Take now" : "Up next")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(theme.accent)
                    Text(item.medName)
                        .font(.title3.bold())
                        .lineLimit(1)
                    DoseSubtitle(item: item)
                }
                Spacer(minLength: 8)
                StateBadge(state: item.state)
                    .fixedSize()
            }

            actions
        }
        .padding(18)
        .cardGlass(cornerRadius: 30, tint: item.state.needsAttention ? theme.accent.opacity(0.5) : nil)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if item.state.isActionable, let med = item.medication {
                    GlassActionButton(title: "Taken", symbol: "checkmark", tint: theme.accent, prominent: true, fill: true) {
                        perform { DoseActions.markTaken(med, scheduledAt: item.scheduledAt) }
                    }
                    .glassEffectID("primary", in: glassNS)

                    if let at = item.scheduledAt {
                        if item.state != .upcoming {
                            GlassActionButton(title: "Snooze", symbol: "zzz", fill: true) {
                                perform { DoseActions.snooze(med, scheduledAt: at) }
                            }
                            .glassEffectID("snooze", in: glassNS)
                        }
                        GlassActionButton(title: "Skip", symbol: "forward.end", fill: true) {
                            perform { DoseActions.skip(med, scheduledAt: at) }
                        }
                        .glassEffectID("skip", in: glassNS)
                    }
                } else if let event = item.event {
                    GlassActionButton(title: "Undo", symbol: "arrow.uturn.backward", fill: true) {
                        perform { DoseActions.undo(event) }
                    }
                    .glassEffectID("primary", in: glassNS)
                }
            }
        }
    }

    private func perform(_ action: () -> Void) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { action() }
        onAction()
    }
}

// MARK: - Dose row (schedule list)

/// Compact one-line dose with a single quick action; Snooze/Skip live in the context menu.
struct DoseRow: View {
    @Environment(\.theme) private var theme
    let item: DoseItem
    var onAction: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            DoseBadge(item: item, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.medName)
                    .font(.headline)
                    .lineLimit(1)
                DoseSubtitle(item: item)
            }
            Spacer(minLength: 8)
            StateBadge(state: item.state)
                .fixedSize()
            trailingButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .contextMenu { menu }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if item.state.isActionable, let med = item.medication {
            Button {
                perform { DoseActions.markTaken(med, scheduledAt: item.scheduledAt) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.tint(theme.accent).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark taken")
        } else if let event = item.event {
            Button {
                perform { DoseActions.undo(event) }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.bold())
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo")
        }
    }

    @ViewBuilder
    private var menu: some View {
        if item.state.isActionable, let med = item.medication {
            Button("Taken", systemImage: "checkmark") {
                perform { DoseActions.markTaken(med, scheduledAt: item.scheduledAt) }
            }
            if let at = item.scheduledAt {
                Button("Snooze", systemImage: "zzz") {
                    perform { DoseActions.snooze(med, scheduledAt: at) }
                }
                Button("Skip", systemImage: "forward.end") {
                    perform { DoseActions.skip(med, scheduledAt: at) }
                }
            }
        } else if let event = item.event {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                perform { DoseActions.undo(event) }
            }
        }
    }

    private func perform(_ action: () -> Void) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { action() }
        onAction()
    }
}

private struct DoseBadge: View {
    let item: DoseItem
    let size: CGFloat

    var body: some View {
        if let med = item.medication {
            MedBadge(med: med, size: size)
        } else {
            Circle()
                .fill(Color(hex: item.colorHex).gradient)
                .frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
        }
    }
}

/// "6:30 PM · 10 mg" — the separator only appears when there's a dose.
private struct DoseSubtitle: View {
    let item: DoseItem

    var body: some View {
        Text(parts.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var parts: [String] {
        var parts: [String] = []
        if let at = item.scheduledAt { parts.append(at.shortTime) }
        if !item.medDose.isEmpty { parts.append(item.medDose) }
        return parts
    }
}

/// Capsule glass button that participates in glass morphing.
struct GlassActionButton: View {
    let title: String
    let symbol: String
    var tint: Color?
    var prominent = false
    /// Stretch to share the row equally with sibling buttons.
    var fill = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: fill ? .infinity : nil)
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
