import SwiftUI

/// Düzenleyici altında: geçerliyse kuralın cümlesi, değilse eksikler.
struct SummaryOrProblems: View {
    let draft: RuleDraft

    var body: some View {
        if draft.isValid {
            Label(RuleSentence.make(draft), systemImage: "text.alignleft")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(draft.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
