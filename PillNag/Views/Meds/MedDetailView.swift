import SwiftUI
import SwiftData

struct MedDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var med: Medication
    @Query(sort: \DoseEvent.actionAt, order: .reverse) private var allEvents: [DoseEvent]

    @State private var showEdit = false
    @State private var showRefill = false
    @State private var heroAppeared = false
    @State private var takeTick = 0

    private var events: [DoseEvent] { allEvents.filter { $0.medID == med.id } }
    private var shownEvents: [DoseEvent] { Array(events.filter { $0.status != .snoozed }.prefix(12)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                stats
                actionRow
                nagSummary
                if !med.notes.isEmpty { notesCard }
                recent
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background { AppBackground() }
        .navigationTitle(med.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { MedEditorView(med: med, onDelete: deleteMed) }
        .sheet(isPresented: $showRefill) { RefillSheet(med: med) }
        .sensoryFeedback(.success, trigger: takeTick)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { heroAppeared = true }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            PillView(med: med, size: 110)
                .frame(width: 150, height: 150)
                .glassEffect(.regular.tint(med.color.opacity(0.22)), in: .circle)
                .scaleEffect(heroAppeared ? 1 : 0.7)
                .rotationEffect(.degrees(heroAppeared ? 0 : -25))
            Text(med.name).font(.largeTitle.bold())
            if !med.dose.isEmpty {
                Text(med.dose).font(.title3).foregroundStyle(.secondary)
            }
            Label(med.scheduleSummary, systemImage: med.scheduleKind.symbol)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .capsuleGlass()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var stats: some View {
        let summaries = DoseBoard.summaries(days: 7, meds: [med], events: events)
        let scheduled = summaries.reduce(0) { $0 + $1.scheduled }
        let taken = summaries.reduce(0) { $0 + $1.taken }
        let adherence = scheduled == 0 ? "—" : "\(Int((Double(taken) / Double(scheduled) * 100).rounded()))%"
        let streak = DoseBoard.streaks(meds: [med], events: events).current

        return HStack(spacing: 12) {
            if med.tracksSupply {
                StatTile(title: med.daysOfSupplyLeft.map { "left · ~\($0)d" } ?? "left",
                         value: "\(med.pillsRemaining)", symbol: "shippingbox.fill",
                         tint: med.isLowSupply ? .orange : theme.accent)
            }
            StatTile(title: "7-day adherence", value: adherence, symbol: "chart.pie.fill", tint: theme.accent)
            StatTile(title: "streak", value: "\(streak)", symbol: "flame.fill", tint: .orange)
        }
    }

    private var actionRow: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.bouncy) { DoseActions.markTaken(med, scheduledAt: nil) }
                    takeTick += 1
                } label: {
                    Label("Log dose now", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                if med.tracksSupply {
                    Button { showRefill = true } label: {
                        Label("Refill", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
    }

    private var nagSummary: some View {
        let config = NagConfig.resolved(for: med)
        let custom = med.nagIntervalOverride != nil || med.maxNagsOverride != nil || med.nagUntilTakenOverride != nil
            || med.snoozeOverride != nil || med.soundOverride != nil
        return HStack(spacing: 14) {
            Image(systemName: med.nagEnabled ? "bell.badge.waveform.fill" : "bell.slash.fill")
                .font(.title2)
                .foregroundStyle(med.nagEnabled ? theme.accent : .secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(med.nagEnabled ? (custom ? "Custom nagging" : "Default nagging") : "Nagging off")
                    .font(.headline)
                if med.nagEnabled && med.scheduleKind != .asNeeded {
                    Text("\(config.summary) · \(config.snoozeMinutes) min snooze · \(config.sound.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardGlass(cornerRadius: 22)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notes", systemImage: "note.text").font(.headline)
            Text(med.notes).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardGlass(cornerRadius: 22)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Recent")
            if events.isEmpty {
                Text("Nothing logged yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .cardGlass(cornerRadius: 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(shownEvents) { event in
                        EventRow(event: event)
                        if event.id != shownEvents.last?.id { Divider().padding(.leading, 44) }
                    }
                }
                .padding(.vertical, 6)
                .cardGlass(cornerRadius: 22)
            }
        }
    }
}

struct EventRow: View {
    let event: DoseEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.status == .taken ? "checkmark.circle.fill" : "arrow.uturn.right.circle")
                .foregroundStyle(event.status == .taken ? Color.green : Color.gray)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.status == .taken ? "Taken" : "Skipped").font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.actionAt.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var detail: String {
        if let scheduled = event.scheduledAt {
            return "Scheduled \(scheduled.shortTime) · logged \(event.actionAt.shortTime)"
        }
        return "As needed · \(event.actionAt.shortTime)"
    }
}

extension MedDetailView {
    /// Pops this screen first, then deletes, so the view never renders a deleted model.
    func deleteMed() {
        let target = med
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            context.delete(target)
            try? context.save()
            NagScheduler.shared.requestReschedule()
        }
    }
}
