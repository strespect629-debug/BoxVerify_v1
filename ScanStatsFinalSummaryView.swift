import SwiftUI

@MainActor
struct ScanStatsFinalSummaryView: View {

    let summary: ScanStatsFinalSummary
    let onClose: @MainActor () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("最終集計")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Types \(summary.types) / Total \(summary.total)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))

                VStack(alignment: .leading, spacing: 10) {
                    if summary.top.isEmpty {
                        Text("カウントがありません")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    } else {
                        ForEach(Array(summary.top.enumerated()), id: \.offset) { _, pair in
                            HStack {
                                Text(pair.0)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Text("\(pair.1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                )

                Button {
                    onClose()
                } label: {
                    Text("閉じる")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 6)
            }
            .padding(18)
        }
    }
}
