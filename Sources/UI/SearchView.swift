import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var hasSearched: Bool = false
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .search)

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
                        searchTask?.cancel()
                        searchTask = nil
                        query = ""
                        results = []
                        hasSearched = false
                        isSearching = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
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
                    VStack(spacing: 4) {
                        HStack(spacing: 10) {
                            paraLegend("Project", icon: PARACategory.project.icon, color: PARACategory.project.color)
                            paraLegend("Area", icon: PARACategory.area.icon, color: PARACategory.area.color)
                            paraLegend("Resource", icon: PARACategory.resource.icon, color: PARACategory.resource.color)
                            paraLegend("Archive", icon: PARACategory.archive.icon, color: PARACategory.archive.color)
                            Spacer()
                        }

                        HStack {
                            Text("\(results.count)개 결과")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
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
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    private func paraLegend(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        let pkmRoot = appState.pkmRootPath
        searchTask?.cancel()
        searchTask = Task.detached(priority: .userInitiated) {
            let searcher = VaultSearcher(pkmRoot: pkmRoot)
            let searchResults = searcher.search(query: trimmed)
            if Task.isCancelled { return }
            await MainActor.run {
                if query.trimmingCharacters(in: .whitespaces) != trimmed {
                    isSearching = false
                    searchTask = nil
                    return
                }
                results = searchResults
                hasSearched = true
                isSearching = false
                searchTask = nil
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
        para?.color ?? .secondary
    }
}
