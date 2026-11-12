import SwiftUI

/// Ofis kartındaki "İzin isteği" / "Soru" bölümü (OFFICE-CTRL-01). Karar içeriği yalnızca bu görünümde ve `PendingDecisionStore`
/// belleğinde yaşar. Geri sayım yalnızca kart görünürken (TimelineView) çalışır; zamanlayıcı yoktur.
struct OfficeDecisionView: View {
    let decision: PendingDecision
    /// Bu karttan sonra sırada bekleyen başka istek sayısı.
    var queued = 0
    let onDecide: (UUID, DecisionVerdict) -> Void
    @State private var mode: DecisionPermissionMode?
    @State private var selections: [Int: Set<Int>] = [:]

    private var request: DecisionRequest { decision.request }
    private var isPlan: Bool { request.toolName == "ExitPlanMode" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if request.kind == .question { questionBody } else { permissionBody }
            if queued > 0 {
                Text("+\(queued) bekleyen istek daha").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Başlık + geri sayım

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(title, systemImage: request.kind == .question ? "questionmark.bubble.fill" : "hand.raised.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(2)
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.remaining(until: decision.deadline, now: context.date))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .help("Süre dolunca istek terminalde sorulur")
            }
        }
    }

    private var title: String {
        if request.kind == .question { return "Soru" }
        if isPlan { return "Plan onayı" }
        return "İzin isteği · \(request.toolName)"
    }

    static func remaining(until deadline: Date, now: Date) -> String {
        "kalan " + OfficeDetailCard.duration(deadline.timeIntervalSince(now))
    }

    // MARK: İzin

    private var permissionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = request.preview {
                ScrollView {
                    Text(preview)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
            }
            HStack(spacing: 8) {
                Button { onDecide(decision.id, .allow(suggestion: nil, scope: .session, mode: mode)) } label: {
                    Text(isPlan ? "Planı onayla" : "İzin ver").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) { onDecide(decision.id, .deny) } label: {
                    Text("Reddet").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.small)
            if !request.suggestions.isEmpty {
                Menu {
                    ForEach(request.suggestions) { suggestion in
                        Menu(suggestion.label) {
                            Button("Tüm oturumlarda (kalıcı)") { onDecide(decision.id, .allow(suggestion: suggestion.index, scope: .user, mode: mode)) }
                            Button("Yalnız bu oturumda") { onDecide(decision.id, .allow(suggestion: suggestion.index, scope: .session, mode: mode)) }
                        }
                    }
                } label: {
                    Label("Hep izin ver…", systemImage: "checkmark.shield")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Kalıcı seçenek kuralı Claude Code'un kendi kullanıcı ayarlarına yazdırır (~/.claude/settings.json); Adalmon o dosyaya yazmaz")
            }
            Picker(selection: $mode) {
                Text("Mod değişmesin").tag(DecisionPermissionMode?.none)
                ForEach(DecisionPermissionMode.allCases) { Text($0.title).tag(DecisionPermissionMode?.some($0)) }
            } label: {
                Text("İzin verirken mod").font(.caption2)
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .help("Yalnızca \"İzin ver\" ile birlikte uygulanır. Tüm izinleri atlayan mod sunulmaz.")
            releaseButton
        }
    }

    private var releaseButton: some View {
        Button("Terminalde karar ver") { onDecide(decision.id, .release) }
            .buttonStyle(.link)
            .controlSize(.small)
            .help("Kartı kapatır; istek terminaldeki diyalogda beklemeye devam eder")
    }

    // MARK: Soru

    private var questionBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(request.questions.enumerated()), id: \.offset) { qi, question in
                VStack(alignment: .leading, spacing: 4) {
                    if let header = question.header { Text(header).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                    Text(question.question).font(.caption).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(question.options.enumerated()), id: \.offset) { oi, option in
                        optionRow(question: question, qi: qi, oi: oi, option: option)
                    }
                }
            }
            Button { submitAnswers() } label: { Text("Cevapla").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isComplete)
            releaseButton
        }
    }

    private func optionRow(question: DecisionQuestion, qi: Int, oi: Int, option: DecisionQuestion.Option) -> some View {
        let selected = selections[qi]?.contains(oi) == true
        let symbol = question.multiSelect ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle")
        return Button {
            var set = selections[qi] ?? []
            if question.multiSelect {
                if selected { set.remove(oi) } else { set.insert(oi) }
            } else {
                set = [oi]
            }
            selections[qi] = set
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol).foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.caption)
                    if let description = option.description { Text(description).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var isComplete: Bool {
        request.questions.indices.allSatisfy { !(selections[$0] ?? []).isEmpty }
    }

    private func submitAnswers() {
        guard isComplete else { return }
        var answers: [String: [String]] = [:]
        for (qi, question) in request.questions.enumerated() {
            answers[question.question] = (selections[qi] ?? []).sorted().map { question.options[$0].label }
        }
        onDecide(decision.id, .answer(answers))
    }
}
