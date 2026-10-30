import SwiftUI

struct WelcomeView: View {
    var onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var appeared = false
    @State private var working = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 28) {
                Spacer()
                PillView(shape: .capsule, color: Color(hex: "#FF5E78"), secondary: Color(hex: "#FAFAFF"), size: 120)
                    .frame(width: 160, height: 160)
                    .glassEffect(.regular.tint(theme.accent.opacity(0.2)), in: .circle)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .rotationEffect(.degrees(appeared ? 0 : -30))
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text("PillNag").font(.largeTitle.bold())
                    Text("The medication reminder that doesn't take \"later\" for an answer.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        feature("alarm.waves.left.and.right.fill", "Real alarms", "Rings like a clock alarm at dose time — even on silent.")
                        feature("repeat", "Escalating nags", "Keeps ringing every few minutes until you tap Taken.")
                        feature("flame.fill", "Streaks & history", "See what you took, missed, and how long you've kept it up.")
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 30)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task { await enable() }
                    } label: {
                        Label(working ? "Asking…" : "Enable Alarms", systemImage: "alarm.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(working)

                    Button("Not now") { finish() }
                        .buttonStyle(.glass)
                }
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) { appeared = true }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(theme.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardGlass(cornerRadius: 20)
    }

    private func enable() async {
        working = true
        let alarms = await AlarmBackend.requestAuthorization()
        if !alarms {
            await NotificationBackend.requestAuthorization()
        }
        working = false
        finish()
    }

    private func finish() {
        onFinish()
        NagScheduler.shared.requestReschedule()
        dismiss()
    }
}
