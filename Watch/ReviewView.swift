import SwiftUI

/// Flashcard reviews of the words due today. Results go back to the iPhone.
struct ReviewView: View {
    @Environment(WatchModel.self) private var model
    @State private var revealed = false

    var body: some View {
        Group {
            if let w = model.reviews.first {
                card(w)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Ink.good)
                    Text(model.hasPhoneData ? "No reviews left today" : "Reviews appear here once your iPhone has sent your words.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review")
    }

    private func card(_ w: WidgetWord) -> some View {
        VStack(spacing: 4) {
            Text("\(model.reviews.count) left")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            toneText(w.hanzi, pinyin: w.pinyin, colored: revealed && (model.feed?.toneHanzi ?? true), base: .white)
                .font(Ink.hanzi(w.hanzi.count <= 2 ? 54 : 36, relativeTo: .largeTitle))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if revealed {
                PinyinText(pinyin: w.pinyin, colored: model.feed?.toneColors ?? true, font: .system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(w.meaning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text("Tap to show")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if !revealed {
                revealed = true
                model.speak(w.hanzi)
            }
        }
        .toolbar {
            if revealed {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        answer(w, remembered: false)
                    } label: {
                        BarIcon(systemName: "xmark")
                    }
                    .barTint(.red)
                    .accessibilityLabel("Forgot")
                    Spacer()
                    Button {
                        answer(w, remembered: true)
                    } label: {
                        BarIcon(systemName: "checkmark")
                    }
                    .barTint(.barGreen)
                    .accessibilityLabel("Remembered")
                }
            }
        }
    }

    private func answer(_ w: WidgetWord, remembered: Bool) {
        model.review(w, remembered: remembered)
        revealed = false
    }
}
