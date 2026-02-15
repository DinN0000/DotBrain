import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseScale: CGFloat = 1.0

    private var originTitle: String {
        appState.processingOrigin == .paraManage ? "폴더 정리 중" : "인박스 처리 중"
    }

    private var phaseBadge: String {
        appState.processingPhase.rawValue
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text(originTitle)
                .font(.headline)

            centerContent

            VStack(spacing: 6) {
                ProgressView(value: appState.processingProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

                HStack {
                    Text(phaseBadge)
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

            statusDetail

            Spacer()

            Button("취소") { appState.cancelProcessing() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.bottom, 4)
        }
        .padding()
        .animation(.easeOut(duration: 0.2), value: appState.processingPhase)
        .animation(.easeOut(duration: 0.2), value: appState.processingCurrentFile)
    }

    @ViewBuilder
    private var centerContent: some View {
        switch appState.processingPhase {
        case .preparing, .extracting:
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.large)
                if appState.processingTotalCount > 0 {
                    Text("\(appState.processingTotalCount)개 파일 준비 완료")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

        case .classifying:
            VStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "brain")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    )
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            pulseScale = 1.15
                        }
                    }
                    .onDisappear { pulseScale = 1.0 }

                Text(appState.processingStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

        case .linking:
            VStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "link")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    )
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            pulseScale = 1.15
                        }
                    }
                    .onDisappear { pulseScale = 1.0 }

                Text("관련 노트 연결 중...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

        case .processing, .finishing:
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
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        if appState.processingPhase == .processing || appState.processingPhase == .finishing {
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
        }
    }
}
