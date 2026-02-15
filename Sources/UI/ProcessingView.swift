import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var appState: AppState

    private var phaseLabel: String {
        let status = appState.processingStatus
        if status.contains("컨텍스트") { return "준비" }
        if status.contains("추출") { return "분석" }
        if status.contains("AI") || status.contains("분류") { return "분류" }
        if status.contains("처리 중") || status.contains("이동 중") { return "정리" }
        if status.contains("완료") { return "마무리" }
        return "시작"
    }

    private var originTitle: String {
        appState.processingOrigin == .reorganize ? "폴더 정리 중" : "인박스 처리 중"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text(originTitle)
                .font(.headline)

            if appState.processingTotalCount > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(appState.processingCompletedCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text("/")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("\(appState.processingTotalCount)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            } else {
                ProgressView()
                    .controlSize(.large)
            }

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
                        .background(Capsule().fill(Color.accentColor.opacity(0.1)))

                    Spacer()

                    Text("\(Int(appState.processingProgress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }

            if !appState.processingCurrentFile.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.processingCurrentFile)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 40)
                .transition(.opacity)
            }

            Spacer()

            Button("취소") { appState.cancelProcessing() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.bottom, 4)
        }
        .padding()
        .animation(.easeOut(duration: 0.2), value: appState.processingCurrentFile)
    }
}
