import SwiftUI
import SwiftData

/// Editable copy of a medication, so Cancel really cancels.
struct MedDraft {
    var name = ""
    var dose = ""
    var shape: PillShape = .capsule
    var colorHex = "#FF5E78"
    var secondaryColorHex = "#FAFAFF"
    var symbol = "pills.fill"
    var useSymbol = false
    var notes = ""

    var tracksSupply = true
    var pillsRemaining = 30
    var pillsPerDose = 1
    var lowSupplyThreshold = 7

    var scheduleKind: ScheduleKind = .daily
    var times: [Int] = [8 * 60]
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var intervalHours = 8
    var intervalAnchor = 8 * 60

    var nagEnabled = true
    var customNag = false
    var nagInterval = NagConfig.global.intervalMinutes
    var maxNags = NagConfig.global.maxFollowUps
    var untilTaken = NagConfig.global.untilTaken
    var snooze = NagConfig.global.snoozeMinutes
    var soundOverride: String?

    init() {}

    init(med: Medication) {
        name = med.name
        dose = med.dose
        shape = med.shape
        colorHex = med.colorHex
        secondaryColorHex = med.secondaryColorHex
        symbol = med.symbol
        useSymbol = med.useSymbol
        notes = med.notes
        tracksSupply = med.tracksSupply
        pillsRemaining = med.pillsRemaining
        pillsPerDose = med.pillsPerDose
        lowSupplyThreshold = med.lowSupplyThreshold
        scheduleKind = med.scheduleKind
        times = med.timesOfDay.isEmpty ? [8 * 60] : med.timesOfDay.sorted()
        weekdays = Set(med.weekdays)
        intervalHours = med.intervalHours
        intervalAnchor = med.intervalAnchorMinutes
        nagEnabled = med.nagEnabled
        customNag = med.nagIntervalOverride != nil || med.maxNagsOverride != nil || med.nagUntilTakenOverride != nil
            || med.snoozeOverride != nil || med.soundOverride != nil
        let resolved = NagConfig.resolved(for: med)
        nagInterval = resolved.intervalMinutes
        maxNags = resolved.maxFollowUps
        untilTaken = resolved.untilTaken
        snooze = resolved.snoozeMinutes
        soundOverride = med.soundOverride
    }

    var isValid: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        switch scheduleKind {
        case .daily: return hasName && !times.isEmpty
        case .weekdays: return hasName && !times.isEmpty && !weekdays.isEmpty
        case .interval, .asNeeded: return hasName
        }
    }

    func apply(to med: Medication) {
        let scheduleChanged = med.scheduleKind != scheduleKind || med.timesOfDay.sorted() != times.sorted()
            || Set(med.weekdays) != weekdays || med.intervalHours != intervalHours || med.intervalAnchorMinutes != intervalAnchor
        med.name = name.trimmingCharacters(in: .whitespaces)
        med.dose = dose.trimmingCharacters(in: .whitespaces)
        med.shape = shape
        med.colorHex = colorHex
        med.secondaryColorHex = secondaryColorHex
        med.symbol = symbol
        med.useSymbol = useSymbol
        med.notes = notes
        med.tracksSupply = tracksSupply
        med.pillsRemaining = pillsRemaining
        med.pillsPerDose = pillsPerDose
        med.lowSupplyThreshold = lowSupplyThreshold
        med.scheduleKind = scheduleKind
        med.timesOfDay = Array(Set(times)).sorted()
        med.weekdays = weekdays.sorted()
        med.intervalHours = intervalHours
        med.intervalAnchorMinutes = intervalAnchor
        if scheduleChanged && med.scheduleKind == .interval {
            // Re-anchor interval schedules so the new cadence starts today.
            med.scheduleStart = max(med.scheduleStart, Calendar.current.startOfDay(for: .now))
        }
        med.nagEnabled = nagEnabled
        if customNag {
            med.nagIntervalOverride = nagInterval
            med.maxNagsOverride = maxNags
            med.nagUntilTakenOverride = untilTaken
            med.snoozeOverride = snooze
            med.soundOverride = soundOverride
        } else {
            med.nagIntervalOverride = nil
            med.maxNagsOverride = nil
            med.nagUntilTakenOverride = nil
            med.snoozeOverride = nil
            med.soundOverride = nil
        }
    }
}

struct MedEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme

    let med: Medication?
    var onDelete: (() -> Void)?

    @State private var draft: MedDraft
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(med: Medication?, onDelete: (() -> Void)? = nil) {
        self.med = med
        self.onDelete = onDelete
        _draft = State(initialValue: med.map(MedDraft.init(med:)) ?? MedDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                }
                .listRowBackground(Color.clear)

                Section("Medication") {
                    TextField("Name", text: $draft.name)
                        .font(.headline)
                        .focused($nameFocused)
                        .submitLabel(.next)
                    TextField("Dose (e.g. 10 mg, 2 puffs)", text: $draft.dose)
                }

                Section("Look") { lookEditor }
                Section {
                    ScheduleEditor(draft: $draft)
                } header: {
                    Text("Schedule")
                }
                Section {
                    supplyEditor
                } header: {
                    Text("Supply")
                } footer: {
                    if draft.tracksSupply {
                        Text("You'll get a warning when \(draft.lowSupplyThreshold) or fewer are left.")
                    }
                }
                Section {
                    nagEditor
                } header: {
                    Text("Nagging")
                } footer: {
                    if draft.nagEnabled && draft.scheduleKind != .asNeeded {
                        Text(nagFooter)
                    }
                }
                Section("Notes") {
                    TextField("Take with food, etc.", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let med {
                    Section {
                        Button(med.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                            med.isArchived.toggle()
                            saveAndClose()
                        }
                        Button("Delete Medication", systemImage: "trash", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle(med == nil ? "New Medication" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .disabled(!draft.isValid)
                }
            }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("History for this medication is kept, but its schedule and alarms are removed.")
            }
            .onAppear { if med == nil { nameFocused = true } }
        }
    }

    // MARK: Sections

    private var preview: some View {
        HStack {
            Spacer()
            PillView(shape: draft.shape, color: Color(hex: draft.colorHex), secondary: Color(hex: draft.secondaryColorHex),
                     symbol: draft.useSymbol ? draft.symbol : nil, size: 96)
                .frame(width: 128, height: 128)
                .glassEffect(.regular.tint(Color(hex: draft.colorHex).opacity(0.2)), in: .circle)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: draft.shape)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: draft.useSymbol)
                .animation(.easeInOut, value: draft.colorHex)
            Spacer()
        }
    }

    @ViewBuilder
    private var lookEditor: some View {
        Toggle("Use an icon instead of a pill", isOn: $draft.useSymbol.animation(.snappy))

        if draft.useSymbol {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(MedSymbols.all, id: \.self) { symbol in
                    Button {
                        withAnimation(.snappy) { draft.symbol = symbol }
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .foregroundStyle(draft.symbol == symbol ? Color(hex: draft.colorHex) : Color.secondary)
                            .glassEffect(draft.symbol == symbol ? .regular.tint(Color(hex: draft.colorHex).opacity(0.3)).interactive() : .regular.interactive(),
                                         in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PillShape.allCases) { shape in
                        Button {
                            withAnimation(.snappy) { draft.shape = shape }
                        } label: {
                            VStack(spacing: 4) {
                                PillView(shape: shape, color: Color(hex: draft.colorHex),
                                         secondary: Color(hex: draft.secondaryColorHex), size: 40)
                                Text(shape.title).font(.caption2)
                            }
                            .frame(width: 70, height: 72)
                            .glassEffect(draft.shape == shape ? .regular.tint(theme.accent.opacity(0.35)).interactive() : .regular.interactive(),
                                         in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }

        ColorRow(title: "Color", hex: $draft.colorHex)
        if draft.shape == .capsule && !draft.useSymbol {
            ColorRow(title: "Other half", hex: $draft.secondaryColorHex)
        }
    }

    @ViewBuilder
    private var supplyEditor: some View {
        Toggle("Track pill count", isOn: $draft.tracksSupply.animation(.snappy))
        if draft.tracksSupply {
            Stepper(value: $draft.pillsRemaining, in: 0...9999) {
                LabeledContent("Pills left", value: "\(draft.pillsRemaining)")
            }
            Stepper(value: $draft.pillsPerDose, in: 1...20) {
                LabeledContent("Per dose", value: "\(draft.pillsPerDose)")
            }
            Stepper(value: $draft.lowSupplyThreshold, in: 0...500) {
                LabeledContent("Warn at", value: "\(draft.lowSupplyThreshold)")
            }
        }
    }

    @ViewBuilder
    private var nagEditor: some View {
        Toggle("Alarms for this med", isOn: $draft.nagEnabled.animation(.snappy))
        if draft.nagEnabled {
            Toggle("Custom settings for this med", isOn: $draft.customNag.animation(.snappy))
            if draft.customNag {
                Stepper(value: $draft.nagInterval, in: 1...60) {
                    LabeledContent("Nag every", value: "\(draft.nagInterval) min")
                }
                Toggle(isOn: $draft.untilTaken.animation(.snappy)) {
                    Label("Nag until taken", systemImage: "infinity")
                }
                if !draft.untilTaken {
                    Stepper(value: $draft.maxNags, in: 0...20) {
                        LabeledContent("Follow-ups", value: "\(draft.maxNags)")
                    }
                }
                Stepper(value: $draft.snooze, in: 1...120) {
                    LabeledContent("Snooze", value: "\(draft.snooze) min")
                }
                Picker("Alarm sound", selection: $draft.soundOverride) {
                    Text("App default").tag(String?.none)
                    ForEach(AlarmSound.allCases) { sound in
                        Text(sound.title).tag(String?.some(sound.rawValue))
                    }
                }
            }
        }
    }

    private var nagFooter: String {
        let interval = draft.customNag ? draft.nagInterval : NagConfig.global.intervalMinutes
        let count = draft.customNag ? draft.maxNags : NagConfig.global.maxFollowUps
        let forever = draft.customNag ? draft.untilTaken : NagConfig.global.untilTaken
        if forever {
            return "Rings at dose time, then every \(interval) min until you mark it taken in the app, or until this med's next dose is due."
        }
        if count == 0 { return "Rings once at dose time." }
        return "Rings at dose time, then every \(interval) min up to \(count) more times (\(interval * count) min) until you mark it taken in the app."
    }

    // MARK: Actions

    private func save() {
        let target: Medication
        if let med {
            target = med
        } else {
            target = Medication()
            let count = (try? context.fetchCount(FetchDescriptor<Medication>())) ?? 0
            target.sortOrder = count
            context.insert(target)
        }
        draft.apply(to: target)
        saveAndClose()
    }

    private func saveAndClose() {
        try? context.save()
        NagScheduler.shared.requestReschedule()
        dismiss()
    }

    private func delete() {
        if let onDelete {
            dismiss()
            onDelete()
        } else if let med {
            context.delete(med)
            saveAndClose()
        }
    }
}

private struct ColorRow: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                ColorPicker(title, selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hexString }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(PillPalette.colors, id: \.self) { option in
                    Button {
                        withAnimation(.snappy) { hex = option }
                    } label: {
                        Circle()
                            .fill(Color(hex: option).gradient)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                            .padding(3)
                            .overlay {
                                if hex.uppercased() == option.uppercased() {
                                    Circle().strokeBorder(Color.primary, lineWidth: 2)
                                }
                            }
                            .scaleEffect(hex.uppercased() == option.uppercased() ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ScheduleEditor: View {
    @Binding var draft: MedDraft

    var body: some View {
        Picker("Type", selection: $draft.scheduleKind.animation(.snappy)) {
            ForEach(ScheduleKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .listRowSeparator(.hidden)

        switch draft.scheduleKind {
        case .daily:
            timesEditor
        case .weekdays:
            WeekdayPicker(selection: $draft.weekdays)
            timesEditor
        case .interval:
            Stepper(value: $draft.intervalHours, in: 1...24) {
                LabeledContent("Every", value: "\(draft.intervalHours) hour\(draft.intervalHours == 1 ? "" : "s")")
            }
            DatePicker("First dose", selection: minutesBinding(\.intervalAnchor), displayedComponents: .hourAndMinute)
        case .asNeeded:
            Label("No alarms. Log doses from the Today tab whenever you take one.", systemImage: "hand.raised")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var timesEditor: some View {
        ForEach(Array(draft.times.enumerated()), id: \.offset) { index, _ in
            HStack {
                DatePicker("Dose \(index + 1)", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                if draft.times.count > 1 {
                    Button {
                        withAnimation(.snappy) { if index < draft.times.count { _ = draft.times.remove(at: index) } }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Button {
            withAnimation(.snappy) {
                let last = draft.times.max() ?? 8 * 60
                draft.times.append(min(last + 4 * 60, 23 * 60 + 59))
            }
        } label: {
            Label("Add time", systemImage: "plus.circle.fill")
        }
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { Date.atMinutes(index < draft.times.count ? draft.times[index] : 480) },
            set: { if index < draft.times.count { draft.times[index] = $0.minutesOfDay } }
        )
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<MedDraft, Int>) -> Binding<Date> {
        Binding(
            get: { Date.atMinutes(draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = $0.minutesOfDay }
        )
    }
}

private struct WeekdayPicker: View {
    @Environment(\.theme) private var theme
    @Binding var selection: Set<Int>

    private var orderedDays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(orderedDays, id: \.self) { day in
                    let on = selection.contains(day)
                    Button {
                        withAnimation(.snappy) {
                            if on { selection.remove(day) } else { selection.insert(day) }
                        }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .font(.subheadline.bold())
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .frame(width: 38, height: 38)
                            .glassEffect(on ? .regular.tint(theme.accent).interactive() : .regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }
}
