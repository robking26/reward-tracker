import SwiftUI

/// The coach conversation (N3): short messages, quick replies, and a visible record of what actually changed.
struct CoachView: View {
    @Environment(CoachModel.self) private var coach
    @Binding var showingSettings: Bool
    @State private var draft = ""
    @State private var dictation = Dictation()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(coach.messages, id: \.id) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if let last = coach.messages.last, last.role == .coach, !last.quickReplies.isEmpty {
                            QuickReplies(replies: last.quickReplies) { reply in
                                send(reply)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.page)
                    .padding(.vertical, Spacing.m)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: coach.messages.count) { scrollToEnd(proxy, animated: true) }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .pageBackground()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(isPresented: $showingSettings)
                }
            }
            .onChange(of: dictation.transcript) { _, text in
                if dictation.isRecording || !text.isEmpty { draft = text }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: Spacing.xxs) {
            if let error = dictation.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if dictation.isRecording {
                Text(dictation.isOnDevice ? "Listening on this iPhone…" : "Listening… (this device sends audio to Apple to transcribe)")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Spacing.xs) {
                TextField("Message your coach", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 10)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button {
                    Task {
                        if dictation.isRecording { dictation.stop() } else { await dictation.start() }
                    }
                } label: {
                    Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(dictation.isRecording ? Palette.warning : Palette.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Dictate")
                Button {
                    send(draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Palette.textTertiary : Palette.accent)
                        .frame(width: 44, height: 44)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
    }

    private func send(_ text: String) {
        if dictation.isRecording { dictation.stop() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.send(trimmed)
        draft = ""
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = coach.messages.last?.id else { return }
        if animated {
            withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

struct MessageBubble: View {
    let message: CoachMessage

    var body: some View {
        let isUser = message.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xxs) {
            Text(message.text)
                .font(.body)
                .foregroundStyle(isUser ? Palette.onAccent : Palette.textPrimary)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, 10)
                .background(isUser ? Palette.accent : Palette.surface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .textSelection(.enabled)
            if let summary = message.toolSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((isUser ? "You: " : "Coach: ") + message.text + (message.toolSummary.map { ". \($0)" } ?? ""))
    }
}

struct QuickReplies: View {
    let replies: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(replies, id: \.self) { reply in
                    Button(reply) { onTap(reply) }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, Spacing.s)
                        .frame(minHeight: 36)
                        .background(Palette.elevated, in: Capsule())
                }
            }
        }
    }
}
