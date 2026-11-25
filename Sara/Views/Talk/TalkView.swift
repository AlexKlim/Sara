import SwiftData
import SwiftUI

/// Talking to Sara: what she is doing right now, the last phrase and her answer.
struct TalkView: View {
    let sara: Sara
    let voice: Voice
    /// Sends a phrase to Sara. The flag says whether it was spoken (then the answer is spoken too).
    let onAsk: (String, Bool) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(Turn.latest) private var latestTurns: [Turn]
    @State private var input = ""

    private var lastTurn: Turn? { latestTurns.first { $0.chatID == sara.chatID } }
    private var compact: Bool { sizeClass == .compact }

    private var stage: SaraOrb.Stage {
        if voice.listening { return .listening }
        if sara.busy && (lastTurn?.reply ?? "").isEmpty { return .thinking }
        if sara.busy || voice.speaking { return .answering }
        return .idle
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: compact ? 24 : 48) {
                topBar
                ScrollView {
                    VStack(spacing: compact ? 24 : 48) {
                        SaraOrb(stage: stage, size: compact ? 160 : 240)
                        if let status = sara.status { Text(verbatim: status).foregroundStyle(Theme.teal) }
                        exchange.frame(maxWidth: 980)
                    }
                    .padding(.top, compact ? 0 : 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, compact ? 16 : 56)
            .padding(.top, compact ? 16 : 40)
            .background(Theme.deepBackground)
            .foregroundStyle(Theme.text)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if ProcessInfo.processInfo.isiOSAppOnMac { MicrophoneBar(listening: voice.listening).padding(.top, 8) }
                    inputBar
                }
                .background(Theme.deepBackground)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Close") { dismiss() }.pill()
            Spacer()
            Group {
                NavigationLink { HistoryView() } label: { Label("History", systemImage: "clock.arrow.circlepath").pill() }
                Button { sara.startNewChat(in: context) } label: { Label("New conversation", systemImage: "square.and.pencil").pill() }
                    .disabled(sara.busy)
            }
            .labelStyle(.iconOnly)
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondary)
                    .padding(.leading, 12)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var exchange: some View {
        let userSize: CGFloat = compact ? 28 : 44
        VStack(spacing: 20) {
            if voice.listening && !voice.text.isEmpty {
                Text("You").blockTitle()
                Text("“\(voice.text)…”").font(.system(size: userSize, weight: .medium))
            } else if let turn = lastTurn {
                Text("You").blockTitle()
                Text("“\(turn.user)”").font(.system(size: userSize, weight: .medium)).foregroundStyle(Theme.soft)
                if let reply = turn.reply, !reply.isEmpty {
                    Text("Sara").blockTitle(Theme.teal).padding(.top, 24)
                    Text(reply).font(.system(size: compact ? 22 : 34)).lineSpacing(compact ? 4 : 8)
                    CenteredFlow { ForEach(turn.actions.indices, id: \.self) { actionChip(turn.actions[$0]) } }.padding(.top, 12)
                }
            } else if voice.listening {
                Text("Listening...").font(.system(size: userSize, weight: .medium)).foregroundStyle(Theme.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func actionChip(_ action: String) -> some View {
        Label {
            Text(verbatim: action)
        } icon: {
            Image(systemName: "checkmark").foregroundStyle(Theme.teal)
        }
        .font(.system(size: 16))
        .foregroundStyle(Theme.soft)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().stroke(Theme.border))
    }

    private var inputBar: some View {
        HStack {
            TextField("Say or type", text: voice.listening ? .constant(voice.text) : $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit { let text = input; input = ""; onAsk(text, false) }
            Button(voice.listening ? "Stop" : "Speak",
                   systemImage: voice.listening ? "stop.circle.fill" : "mic.circle.fill") {
                if voice.listening { onAsk(voice.stop(), true) } else { Task { await voice.start() } }
            }
            .labelStyle(.iconOnly)
            .font(.largeTitle)
            .tint(Theme.teal)
        }
        .disabled(sara.busy)
        .padding()
        .background(Theme.deepBackground)
    }
}
