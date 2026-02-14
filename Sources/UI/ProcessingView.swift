import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var appState: AppState

    private var phaseLabel: String {
        let status = appState.processingStatus
        if status.contains("컨텍스트") { return "준비" }
        if status.contains("추출") { return "분석" }
        if status.contains("AI") || status.contains("분류") { return "분류" }
        if status.contains("처리 중") { return "정리" }
        if status.contains("완료") { return "마무리" }
        return "시작"
    }

    private var originTitle: String {
        appState.processingOrigin == .reorganize ? "폴더 정리 중" : "인박스 처리 중"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Title
            Text(originTitle)
                .font(.headline)

            // Spinner
            ProgressView()
                .controlSize(.large)

            // Progress bar + percentage
            VStack(spacing: 6) {
                ProgressView(value: appState.processingProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

                HStack {
                    Text(phaseLabel)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.1))
                        )

                    Spacer()

                    Text("\(Int(appState.processingProgress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }

            // Status text
            Text(appState.processingStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .animation(.easeOut(duration: 0.2), value: appState.processingStatus)

            Spacer()

            // Cancel button
            Button(action: {
                appState.cancelProcessing()
            }) {
                Text("취소")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.bottom, 4)
        }
        .padding()
    }
}
