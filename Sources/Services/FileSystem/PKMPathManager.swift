import Foundation

/// Manages PARA folder paths for the PKM vault
struct PKMPathManager {
    let root: String

    var inboxPath: String { (root as NSString).appendingPathComponent("_Inbox") }
    var assetsPath: String { (root as NSString).appendingPathComponent("_Assets") }
    var projectsPath: String { (root as NSString).appendingPathComponent("1_Project") }
    var areaPath: String { (root as NSString).appendingPathComponent("2_Area") }
    var resourcePath: String { (root as NSString).appendingPathComponent("3_Resource") }
    var archivePath: String { (root as NSString).appendingPathComponent("4_Archive") }

    /// Get the base path for a PARA category
    func paraPath(for category: PARACategory) -> String {
        switch category {
        case .project: return projectsPath
        case .area: return areaPath
        case .resource: return resourcePath
        case .archive: return archivePath
        }
    }

    /// Sanitize a folder name to prevent path traversal attacks
    private func sanitizeFolderName(_ name: String) -> String {
        // Remove path traversal components and absolute path prefixes
        let components = name.components(separatedBy: "/")
        let safe = components.filter { $0 != ".." && $0 != "." && !$0.isEmpty }
        return safe.joined(separator: "/")
    }

    /// Get the target directory for a classification result
    func targetDirectory(for result: ClassifyResult) -> String {
        if result.para == .project, let project = result.project {
            let safeProject = sanitizeFolderName(project)
            let targetPath = (projectsPath as NSString).appendingPathComponent(safeProject)
            // Verify the resolved path is within projectsPath
            guard targetPath.hasPrefix(projectsPath) else { return projectsPath }
            return targetPath
        }

        let base = paraPath(for: result.para)
        if result.targetFolder.isEmpty {
            return base
        }
        let safeFolder = sanitizeFolderName(result.targetFolder)
        let targetPath = (base as NSString).appendingPathComponent(safeFolder)
        // Verify the resolved path is within the PARA base directory
        guard targetPath.hasPrefix(base) else { return base }
        return targetPath
    }

    /// Get the assets directory for a target directory
    func assetsDirectory(for targetDir: String) -> String {
        return (targetDir as NSString).appendingPathComponent("_Assets")
    }

    /// Check if PKM folder structure exists
    func isInitialized() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: root)
            && fm.fileExists(atPath: inboxPath)
            && fm.fileExists(atPath: projectsPath)
    }

    /// Create the full PARA folder structure
    func initializeStructure() throws {
        let fm = FileManager.default
        let folders = [inboxPath, projectsPath, areaPath, resourcePath, archivePath]
        for folder in folders {
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        
        // Create AI companion files for Claude Code / Cursor / OpenClaw compatibility
        try createAICompanionFiles()
    }
    
    /// Create AI companion files (CLAUDE.md, AGENTS.md, .cursorrules)
    private func createAICompanionFiles() throws {
        let fm = FileManager.default
        
        // CLAUDE.md - Main instructions for Claude Code
        let claudeMdPath = (root as NSString).appendingPathComponent("CLAUDE.md")
        if !fm.fileExists(atPath: claudeMdPath) {
            let claudeContent = """
            # PKM Knowledge Base
            
            이 폴더는 PARA 방법론으로 정리된 개인 지식 관리(PKM) 시스템입니다.
            DotBrain이 자동으로 정리하며, Obsidian과 호환됩니다.
            
            ## 폴더 구조
            
            ```
            _Inbox/       → 새 파일 대기 (DotBrain이 자동 처리)
            1_Project/    → 진행 중인 프로젝트 (목표 + 기한 있음)
            2_Area/       → 지속 관리 영역 (기한 없는 책임)
            3_Resource/   → 참고 자료 (관심사, 학습 자료)
            4_Archive/    → 완료/비활성 항목
            ```
            
            ## 탐색 방법
            
            1. **프로젝트 찾기**: `1_Project/` 내 폴더명 = 프로젝트명
            2. **주제별 탐색**: 각 폴더의 인덱스 노트 (`폴더명.md`) 먼저 읽기
            3. **관련 노트**: 프론트매터의 `tags`, `related` 필드 활용
            4. **검색**: 프론트매터 `para`, `tags` 필드로 필터링
            
            ## 프론트매터 구조
            
            ```yaml
            ---
            para: project | area | resource | archive
            tags: [태그1, 태그2]
            created: 2026-01-01
            modified: 2026-01-15
            summary: 문서 요약
            related:
              - "[[관련 노트]]"
            ---
            ```
            
            ## 규칙
            
            - `_Inbox/`는 건드리지 마세요 (DotBrain이 처리)
            - 새 노트 생성 시 프론트매터 포함 권장
            - `[[위키링크]]` 형식 사용 (Obsidian 호환)
            - 파일명에 특수문자 피하기
            
            ## ⚠️ 중요: 코드 파일 금지
            
            **이 폴더 안에서 코드를 작성하지 마세요!**
            
            - DotBrain이 코드 파일 (.swift, .ts, .py, .js 등)을 자동 삭제합니다
            - 개발 프로젝트는 이 PKM 폴더 **밖에서** 작업하세요
            - 이 폴더는 지식/문서 관리 전용입니다
            
            코드 작성이 필요하면:
            1. PKM 폴더 밖의 별도 디렉토리에서 작업
            2. 코드 관련 **문서/노트**만 이 PKM에 저장
            
            ## AI 작업 권장사항
            
            - 읽기: 자유롭게 탐색
            - 쓰기: 기존 노트 수정 시 프론트매터 유지
            - 생성: 마크다운 노트만, 적절한 PARA 폴더에
            - 코드: **절대 이 폴더 안에서 작성 금지**
            """
            try claudeContent.write(toFile: claudeMdPath, atomically: true, encoding: .utf8)
        }
        
        // AGENTS.md - For OpenClaw/Codex compatibility
        let agentsMdPath = (root as NSString).appendingPathComponent("AGENTS.md")
        if !fm.fileExists(atPath: agentsMdPath) {
            let agentsContent = """
            # AGENTS.md - PKM Workspace
            
            이 PKM은 DotBrain으로 관리되는 지식 베이스입니다.
            
            ## 구조
            
            - `_Inbox/`: 처리 대기 (자동 분류됨, 수정 금지)
            - `1_Project/`: 활성 프로젝트
            - `2_Area/`: 지속 관리 영역
            - `3_Resource/`: 참고 자료
            - `4_Archive/`: 보관함
            
            ## 작업 시 참고
            
            - 노트 검색: 프론트매터 `tags`, `para` 필드 활용
            - 관련 노트: `related` 필드의 위키링크 따라가기
            - 프로젝트 현황: `1_Project/프로젝트명/프로젝트명.md` 인덱스 확인
            
            ## 수정 규칙
            
            - 프론트매터 형식 유지
            - 위키링크 `[[노트명]]` 사용
            - 새 노트는 적절한 PARA 폴더에 생성
            
            ## ⚠️ 코드 작성 금지
            
            **이 폴더 안에서 코드 파일을 생성하지 마세요.**
            DotBrain이 코드 파일을 자동 삭제합니다.
            개발 작업은 이 PKM 폴더 밖에서 하세요.
            """
            try agentsContent.write(toFile: agentsMdPath, atomically: true, encoding: .utf8)
        }
        
        // .cursorrules - For Cursor IDE
        let cursorRulesPath = (root as NSString).appendingPathComponent(".cursorrules")
        if !fm.fileExists(atPath: cursorRulesPath) {
            let cursorContent = """
            # PKM Knowledge Base Rules
            
            This is a PARA-organized PKM vault managed by DotBrain.
            
            ## Structure
            - _Inbox/: Auto-processed by DotBrain (do not modify)
            - 1_Project/: Active projects with goals and deadlines
            - 2_Area/: Ongoing responsibilities without deadlines
            - 3_Resource/: Reference materials and interests
            - 4_Archive/: Completed or inactive items
            
            ## Navigation
            - Start with index notes (FolderName.md) in each directory
            - Use frontmatter tags and para fields for filtering
            - Follow [[wikilinks]] for related notes
            
            ## Writing Rules
            - Preserve existing frontmatter when editing
            - Use [[wikilinks]] for internal links
            - Include frontmatter with para, tags, summary for new notes
            
            ## ⚠️ NO CODE FILES
            
            DO NOT create code files (.swift, .ts, .py, .js, etc.) in this folder!
            DotBrain automatically deletes code files during cleanup.
            Do all development work OUTSIDE this PKM folder.
            This folder is for knowledge/documentation only.
            """
            try cursorContent.write(toFile: cursorRulesPath, atomically: true, encoding: .utf8)
        }
    }

    /// Get existing subfolders for Area/Resource/Archive
    func existingSubfolders() -> [String: [String]] {
        var result: [String: [String]] = [
            "area": [],
            "resource": [],
            "archive": [],
        ]

        let fm = FileManager.default
        let mappings: [(String, String)] = [
            ("area", areaPath),
            ("resource", resourcePath),
            ("archive", archivePath),
        ]

        for (key, dirPath) in mappings {
            guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            var isDir: ObjCBool = false
            result[key] = entries.filter { name in
                !name.hasPrefix(".") && !name.hasPrefix("_")
                    && fm.fileExists(atPath: (dirPath as NSString).appendingPathComponent(name), isDirectory: &isDir)
                    && isDir.boolValue
            }
        }

        return result
    }
}
