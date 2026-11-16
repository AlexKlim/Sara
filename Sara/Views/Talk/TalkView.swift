import SwiftData
import SwiftUI

/// Talking to Sara: the current conversation, the mic, and what Sara is doing right now.
struct TalkView: View {
    let sara: Sara
    let voice: Voice
    /// Sends a phrase to Sara. The flag says whether it was spoken (then the answer is spoken too).
    let onAsk: (String, Bool) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    // ponytail: filters the whole history in memory, query by chatID if it gets slow
    @Query(sort: \Turn.date) private var allTurns: [Turn]
    @State private var input = ""

    /// The current conversation only. Past ones are in History.
    private var turns: [Turn] { allTurns.filter { $0.chatID == sara.chatID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: voice.listening ? "waveform" : "mic")
                    .font(.system(size: 44)).foregroundStyle(Theme.teal)
                    .symbolEffect(.pulse, isActive: voice.listening || sara.busy)
                    .frame(width: 150, height: 150)
                    .background(Color(hex: 0x12302D), in: .circle)
                    .padding(24)
                    .overlay(Circle().stroke(Theme.teal, lineWidth: 2))
                if let status = sara.status {
                    Text(verbatim: status).foregroundStyle(Theme.teal)
                } else if voice.listening {
                    Text("Listening...").foregroundStyle(Theme.teal)
                }
                ScrollViewReader { proxy in
                    List(turns) { TurnRow(turn: $0).id($0.id).listRowBackground(Theme.card) }
                        .scrollContentBackground(.hidden)
                        .onAppear { proxy.scrollTo(turns.last?.id) }
                        .onChange(of: turns.last?.reply) { proxy.scrollTo(turns.last?.id) }
                }
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .background(Color(hex: 0x07080A))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink { ListsView() } label: { Label("Lists", systemImage: "checklist") }
                    NavigationLink { HistoryView() } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    Button("New conversation", systemImage: "square.and.pencil") { sara.startNewChat(in: context) }
                        .disabled(sara.busy)
                }
            }
            .safeAreaInset(edge: .bottom) {
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
                .background(.bar)
            }
        }
    }
}
