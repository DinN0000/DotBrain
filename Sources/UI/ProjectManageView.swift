import SwiftUI

struct ProjectManageView: View {
    @EnvironmentObject var appState: AppState
    @State private var projects: [(name: String, status: NoteStatus, summary: String)] = []
    @State private var newProjectName: String = ""
    @State private var newProjectSummary: String = ""
    @State private var showNewProject: Bool = false
    @State private var statusMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(
                current: .projectManage,
                trailing: AnyView(
                    Button(action: { showNewProject.toggle() }) {
                        Image(systemName: showNewProject ? "minus.circle" : "plus.circle")
                    }
                    .buttonStyle(.plain)
                )
            )

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // New project form
                    if showNewProject {
                        VStack(spacing: 8) {
                            TextField("프로젝트 이름", text: $newProjectName)
                                .textFieldStyle(.roundedBorder)
                            TextField("설명 (선택)", text: $newProjectSummary)
                                .textFieldStyle(.roundedBorder)
                            Button(action: createProject) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("프로젝트 생성")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding()
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                    }

                    // Status message
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                    }

                    // Active projects
                    let active = projects.filter { $0.status != .completed }
                    if !active.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("활성 프로젝트")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            ForEach(active, id: \.name) { project in
                                ProjectRow(
                                    project: project,
                                    onComplete: { completeProject(project.name) },
                                    onOpen: { openProjectFolder(project.name) }
                                )
                            }
                        }
                    }

                    // Archived projects
                    let archived = projects.filter { $0.status == .completed }
                    if !archived.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("아카이브")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            ForEach(archived, id: \.name) { project in
                                ProjectRow(
                                    project: project,
                                    onReactivate: { reactivateProject(project.name) },
                                    onOpen: nil
                                )
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear { loadProjects() }
    }

    private func loadProjects() {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        projects = manager.listProjects()
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            _ = try manager.createProject(name: name, summary: newProjectSummary)
            statusMessage = "'\(name)' 프로젝트 생성됨"
            newProjectName = ""
            newProjectSummary = ""
            showNewProject = false
            loadProjects()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func completeProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.completeProject(name: name)
            statusMessage = "'\(name)' 완료 -> 아카이브 (\(count)개 노트 갱신)"
            loadProjects()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func reactivateProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.reactivateProject(name: name)
            statusMessage = "'\(name)' 재활성화됨 (\(count)개 노트 갱신)"
            loadProjects()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func openProjectFolder(_ name: String) {
        let path = (PKMPathManager(root: appState.pkmRootPath).projectsPath as NSString)
            .appendingPathComponent(name)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func clearStatusAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { statusMessage = "" }
        }
    }
}

struct ProjectRow: View {
    let project: (name: String, status: NoteStatus, summary: String)
    var onComplete: (() -> Void)? = nil
    var onReactivate: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.status == .completed ? "archivebox.fill" : "folder.fill")
                .font(.caption)
                .foregroundColor(project.status == .completed ? .gray : .blue)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.caption)
                    .fontWeight(.medium)
                if !project.summary.isEmpty {
                    Text(project.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let onComplete = onComplete {
                Button(action: onComplete) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("프로젝트 완료")
            }

            if let onReactivate = onReactivate {
                Button(action: onReactivate) {
                    Image(systemName: "arrow.uturn.left.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("재활성화")
            }

            if let onOpen = onOpen {
                Button(action: onOpen) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Finder에서 열기")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(6)
    }
}
