import SwiftUI
import SwiftData

struct MedsView: View {
    @Environment(\.theme) private var theme
    @Query(sort: \Medication.sortOrder) private var allMeds: [Medication]
    @State private var showAdd = false
    @State private var showArchived = false

    private var active: [Medication] { allMeds.filter { !$0.isArchived } }
    private var archived: [Medication] { allMeds.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if active.isEmpty {
                        EmptyMedsCard { showAdd = true }
                    }
                    ForEach(active) { med in
                        NavigationLink(value: med) { MedRow(med: med) }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    if !archived.isEmpty {
                        Button {
                            withAnimation(.snappy) { showArchived.toggle() }
                        } label: {
                            Label(showArchived ? "Hide archived" : "Show archived (\(archived.count))",
                                  systemImage: showArchived ? "chevron.up" : "archivebox")
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 8)
                        if showArchived {
                            ForEach(archived) { med in
                                NavigationLink(value: med) { MedRow(med: med).opacity(0.6) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: allMeds.map(\.id))
            }
            .background { AppBackground() }
            .navigationTitle("Medications")
            .navigationDestination(for: Medication.self) { MedDetailView(med: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add medication")
                }
            }
            .sheet(isPresented: $showAdd) { MedEditorView(med: nil) }
        }
    }
}

struct MedRow: View {
    let med: Medication

    var body: some View {
        HStack(spacing: 14) {
            MedBadge(med: med, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(med.name).font(.headline)
                    if !med.dose.isEmpty {
                        Text(med.dose).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Label(med.scheduleSummary, systemImage: med.scheduleKind.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if med.tracksSupply {
                    Label("\(med.pillsRemaining) left", systemImage: med.isLowSupply ? "exclamationmark.triangle.fill" : "shippingbox")
                        .font(.caption.weight(med.isLowSupply ? .semibold : .regular))
                        .foregroundStyle(med.isLowSupply ? Color.orange : Color.secondary)
                }
            }
            Spacer(minLength: 0)
            if !med.nagEnabled {
                Image(systemName: "bell.slash").foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(.rect)
        .cardGlass(cornerRadius: 24, interactive: true)
    }
}

struct RefillSheet: View {
    @Environment(\.dismiss) private var dismiss
    let med: Medication
    @State private var amount = 30

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                MedBadge(med: med, size: 88)
                Text("Refill \(med.name)").font(.title2.bold())
                Text("Currently \(med.pillsRemaining) left")
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())

                HStack(spacing: 16) {
                    ForEach([-10, -1], id: \.self) { step in
                        Button("\(step)") { amount = max(0, amount + step) }.buttonStyle(.glass)
                    }
                    Text("+\(amount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(amount)))
                        .frame(minWidth: 110)
                    ForEach([1, 10], id: \.self) { step in
                        Button("+\(step)") { amount += step }.buttonStyle(.glass)
                    }
                }
                .animation(.snappy, value: amount)

                Button {
                    DoseActions.refill(med, adding: amount)
                    dismiss()
                } label: {
                    Text("Add \(amount) pills").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.medium])
        .sensoryFeedback(.increase, trigger: amount)
    }
}
