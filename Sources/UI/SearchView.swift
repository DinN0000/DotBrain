import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var hasSearched: Bool = false
    @State private var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("검색")
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("태그, 키워드, 제목으로 검색", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }

                if !query.isEmpty {
                    Button(action: {
                        query = ""
                        results = []
                        hasSearched = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)

            // Search in progress
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("검색 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Results
            if !isSearching && hasSearched {
                if results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("결과 없음")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack {
                        Text("\(results.count)개 결과")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(results) { result in
                                SearchResultRow(result: result)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            }

            if !isSearching && !hasSearched {
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("태그, 키워드, 제목으로\nPKM 전체를 검색합니다")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        let pkmRoot = appState.pkmRootPath
        Task.detached(priority: .userInitiated) {
            let searcher = VaultSearcher(pkmRoot: pkmRoot)
            let searchResults = searcher.search(query: trimmed)
            await MainActor.run {
                results = searchResults
                hasSearched = true
                isSearching = false
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        Button(action: {
            NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "")
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: paraIcon(result.para))
                        .font(.caption)
                        .foregroundColor(paraColor(result.para))
                        .frame(width: 14)

                    Text(result.noteName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if result.isArchived {
                        Text("(아카이브)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(result.matchType.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)
                }

                if !result.summary.isEmpty {
                    Text(result.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !result.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(result.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func paraIcon(_ para: PARACategory?) -> String {
        switch para {
        case .project: return "folder.fill"
        case .area: return "tray.fill"
        case .resource: return "book.fill"
        case .archive: return "archivebox.fill"
        case nil: return "doc.fill"
        }
    }

    private func paraColor(_ para: PARACategory?) -> Color {
        switch para {
        case .project: return .blue
        case .area: return .green
        case .resource: return .orange
        case .archive: return .gray
        case nil: return .secondary
        }
    }
}
