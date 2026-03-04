import Foundation

/// Generates and updates AI companion files for the PKM vault.
/// - CLAUDE.md (Claude Code), AGENTS.md (OpenClaw/Codex), .cursorrules (Cursor)
/// - .claude/agents/ (agent workflows), .claude/skills/ (skill definitions)
enum AICompanionService {

    /// Bump this when companion file content changes — triggers overwrite on existing vaults
    static let version = 13

    /// Generate all AI companion files in the PKM root (first-time only)
    static func generateAll(pkmRoot: String) throws {
        try generateClaudeMd(pkmRoot: pkmRoot)
        try generateAgentsMd(pkmRoot: pkmRoot)
        try generateCursorRules(pkmRoot: pkmRoot)
        try generateClaudeAgents(pkmRoot: pkmRoot)
        try generateClaudeSkills(pkmRoot: pkmRoot)
        try writeVersion(pkmRoot: pkmRoot)
    }

    /// Check version and regenerate if outdated — call on every app launch.
    /// Heavy file I/O is offloaded to a background thread via Task.detached.
    static func updateIfNeeded(pkmRoot: String) {
        // Skip if PKM root doesn't exist yet
        guard FileManager.default.fileExists(atPath: pkmRoot) else { return }

        let versionFile = (pkmRoot as NSString).appendingPathComponent(".dotbrain-companion-version")

        // Read current version
        let currentVersion = (try? String(contentsOfFile: versionFile, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0

        guard currentVersion < version else { return }

        // Offload heavy file I/O to background thread
        Task.detached(priority: .utility) {
            // Force-regenerate all companion files; each step is individually
            // wrapped in do/catch inside forceGenerateAll so partial failures
            // do not prevent remaining steps or version write.
            forceGenerateAll(pkmRoot: pkmRoot)

            // Always write version even if some generation steps failed,
            // to prevent infinite regeneration loop on every app launch.
            do {
                try writeVersion(pkmRoot: pkmRoot)
            } catch {
                NSLog("[AICompanionService] 버전 파일 쓰기 실패: %@", error.localizedDescription)
            }
        }
    }

    private static let markerStart = "<!-- DotBrain:start -->"
    private static let markerEnd = "<!-- DotBrain:end -->"

    /// Update all AI guide files, preserving user content outside markers.
    /// Each step is individually wrapped in do/catch so partial failures
    /// do not prevent the remaining steps from executing.
    private static func forceGenerateAll(pkmRoot: String) {
        let fm = FileManager.default

        // Root-level files: marker-based safe update
        let files: [(String, String)] = [
            ("CLAUDE.md", claudeMdContent),
            ("AGENTS.md", agentsMdContent),
            (".cursorrules", cursorRulesContent),
        ]

        for (fileName, content) in files {
            do {
                let path = (pkmRoot as NSString).appendingPathComponent(fileName)
                let wrapped = "\(markerStart)\n\(content)\n\(markerEnd)"

                if fm.fileExists(atPath: path) {
                    try replaceMarkerSection(at: path, with: wrapped)
                } else {
                    let withUserSection = wrapped + "\n\n<!-- 아래에 자유롭게 추가하세요 -->\n"
                    try withUserSection.write(toFile: path, atomically: true, encoding: .utf8)
                }
            } catch {
                NSLog("[AICompanionService] %@ 생성 실패: %@", fileName, error.localizedDescription)
            }
        }

        // .claude/agents/ — marker-based safe update
        do {
            let agentsDir = (pkmRoot as NSString).appendingPathComponent(".claude/agents")
            try fm.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
            for (name, content) in [
                ("inbox-agent", inboxAgentContent),
                ("project-agent", projectAgentContent),
                ("search-agent", searchAgentContent),
                ("synthesis-agent", synthesisAgentContent),
                ("review-agent", reviewAgentContent),
                ("note-agent", noteAgentContent),
                ("link-health-agent", linkHealthAgentContent),
                ("tag-cleanup-agent", tagCleanupAgentContent),
                ("stale-review-agent", staleReviewAgentContent),
                ("para-move-agent", paraMoveAgentContent),
                ("vault-audit-agent", vaultAuditAgentContent),
            ] {
                do {
                    let path = (agentsDir as NSString).appendingPathComponent("\(name).md")
                    let wrapped = "\(markerStart)\n\(content)\n\(markerEnd)"
                    if fm.fileExists(atPath: path) {
                        try replaceMarkerSection(at: path, with: wrapped)
                    } else {
                        try wrapped.write(toFile: path, atomically: true, encoding: .utf8)
                    }
                } catch {
                    NSLog("[AICompanionService] 에이전트 %@ 생성 실패: %@", name, error.localizedDescription)
                }
            }
        } catch {
            NSLog("[AICompanionService] 에이전트 디렉토리 생성 실패: %@", error.localizedDescription)
        }

        // .claude/skills/ — marker-based safe update
        let allSkills: [(String, String)] = [
            ("inbox-processor", skillContent),
            ("meeting-note", meetingNoteSkillContent),
            ("project-status", projectStatusSkillContent),
            ("weekly-review", weeklyReviewSkillContent),
            ("literature-note", literatureNoteSkillContent),
            ("frontmatter-validator", frontmatterValidatorSkillContent),
            ("index-integrity", indexIntegritySkillContent),
        ]
        for (skillName, skillBody) in allSkills {
            do {
                let skillsDir = (pkmRoot as NSString).appendingPathComponent(".claude/skills/\(skillName)")
                try fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
                let skillPath = (skillsDir as NSString).appendingPathComponent("SKILL.md")
                let wrappedSkill = "\(markerStart)\n\(skillBody)\n\(markerEnd)"
                if fm.fileExists(atPath: skillPath) {
                    try replaceMarkerSection(at: skillPath, with: wrappedSkill)
                } else {
                    try wrappedSkill.write(toFile: skillPath, atomically: true, encoding: .utf8)
                }
            } catch {
                NSLog("[AICompanionService] 스킬 %@ 생성 실패: %@", skillName, error.localizedDescription)
            }
        }

        // Create .obsidianignore to hide internal folders from Obsidian
        do {
            let obsidianIgnorePath = (pkmRoot as NSString).appendingPathComponent(".obsidianignore")
            if !fm.fileExists(atPath: obsidianIgnorePath) {
                let ignoreContent = "_Assets\n.meta\n.dotbrain-companion-version\n"
                try ignoreContent.write(toFile: obsidianIgnorePath, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("[AICompanionService] .obsidianignore 생성 실패: %@", error.localizedDescription)
        }

        // Create _Assets/videos directory for existing vaults
        do {
            let videosDir = (pkmRoot as NSString).appendingPathComponent("_Assets/videos")
            try fm.createDirectory(atPath: videosDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[AICompanionService] _Assets/videos 생성 실패: %@", error.localizedDescription)
        }
    }

    /// Replace content between DotBrain markers, keep everything else
    private static func replaceMarkerSection(at path: String, with newSection: String) throws {
        let existing = try String(contentsOfFile: path, encoding: .utf8)

        let searchAfterStart = { (start: Range<String.Index>) -> Range<String.Index>? in
            existing.range(of: markerEnd, range: start.upperBound..<existing.endIndex)
        }
        if let startRange = existing.range(of: markerStart),
           let endRange = searchAfterStart(startRange),
           startRange.lowerBound < endRange.lowerBound {
            // Markers found — replace only between them (inclusive)
            var updated = existing
            updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: newSection)
            // Remove trailing newline duplication
            updated = updated.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            // No markers — prepend DotBrain section, keep entire existing content as user section
            let merged = newSection + "\n\n<!-- 아래는 기존 사용자 내용입니다 -->\n\n" + existing
            try merged.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func writeVersion(pkmRoot: String) throws {
        let versionFile = (pkmRoot as NSString).appendingPathComponent(".dotbrain-companion-version")
        try "\(version)".write(toFile: versionFile, atomically: true, encoding: .utf8)
    }

    // MARK: - CLAUDE.md

    private static func generateClaudeMd(pkmRoot: String) throws {
        let fm = FileManager.default
        let path = (pkmRoot as NSString).appendingPathComponent("CLAUDE.md")
        guard !fm.fileExists(atPath: path) else { return }
        let content = "\(markerStart)\n\(claudeMdContent)\n\(markerEnd)\n\n<!-- 아래에 자유롭게 추가하세요 -->\n"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static let claudeMdContent = """
    # PKM Knowledge Base — DotBrain

    이 폴더는 **DotBrain**이 관리하는 PARA 방법론 기반 개인 지식 관리(PKM) 시스템입니다.
    Obsidian과 호환되며, AI 도구(Claude Code, Cursor, OpenClaw)가 효과적으로 탐색할 수 있도록 설계되었습니다.

    ---

    ## AI 탐색 우선순위

    이 볼트를 탐색할 때 다음 순서를 따르세요:

    1. **이 파일(CLAUDE.md)** 을 먼저 읽어 구조와 규칙을 파악
    2. **`.meta/note-index.json`** 읽기: 전체 볼트 구조, 노트 메타데이터(태그, 요약, 프로젝트, 상태) 조회
    3. **프론트매터 필드**로 필터링: `project`, `status: active`, `para` 등
    4. **`## Related Notes` 링크** 따라가기: 관계 유형(prerequisite > project > reference > related) 우선순위로 탐색
    5. **Grep 검색**으로 태그/키워드 기반 탐색 (아래 검색 패턴 참조)

    ### 노트 인덱스 (`.meta/note-index.json`)

    DotBrain이 자동 생성/갱신하는 볼트 메타데이터 인덱스입니다.
    - 모든 노트의 경로, 태그, 요약, 프로젝트, 상태 정보 포함
    - 폴더별 요약 태그 포함
    - 파일 분류/이동 시 자동으로 갱신됨
    - 볼트 전체를 파악하려면 개별 파일 대신 이 인덱스를 먼저 읽으세요

    ---

    ## 폴더 구조

    ```
    _Inbox/       → 새 파일 대기 (DotBrain이 자동 처리, 수정 금지)
    1_Project/    → 진행 중인 프로젝트 (목표 + 기한 있음)
    2_Area/       → 지속 관리 영역 (기한 없는 책임)
    3_Resource/   → 참고 자료 (관심사, 학습 자료)
    4_Archive/    → 완료/비활성 항목
    _Assets/      → 전역 첨부파일
    .Templates/   → 노트 템플릿 (Note.md, Project.md, Asset.md)
    .claude/      → AI 에이전트 및 스킬 정의
    ```

    ### 폴더별 하위 구조

    각 PARA 폴더 아래에는 주제별 하위 폴더가 있습니다:
    ```
    1_Project/
    ├── MyProject/
    │   ├── _Assets/        ← 프로젝트 첨부파일
    │   ├── meeting_0115.md
    │   └── design_spec.md
    ```

    ---

    ## DotBrain 자동화 기능

    ### 인박스 처리
    `_Inbox/`에 파일을 넣으면 DotBrain이 자동으로:
    1. 콘텐츠 추출 (마크다운/바이너리 병렬 처리)
    2. **2단계 AI 분류**: Fast 모델로 배치 분류 → 확신도 낮은 파일은 Precise 모델로 정밀 분류
    3. 기존 볼트 문서와의 가중치 기반 맥락 매칭 (🔴 Project 높음 / 🟡 Area·Resource 중간 / ⚪ Archive 낮음)
    4. **AI 시맨틱 관련 노트 링크** (note-index.json 기반 VaultContextMap 활용)
    5. 대상 폴더로 이동 + 프론트매터 삽입 + 노트 인덱스 갱신

    ### 폴더 정리 (Reorganize)
    기존 폴더를 선택하면 DotBrain이:
    1. 중첩 폴더 구조 플랫화 (모든 콘텐츠 파일을 최상위로)
    2. SHA256 해시 기반 중복 제거 (마크다운은 본문만, 바이너리는 전체)
    3. 중복 시 태그 병합 후 삭제
    4. 전체 파일 AI 재분류
    5. **잘못 분류된 파일 자동 이동** (relocated 상태로 표시)
    6. 프론트매터 갱신 + 관련 노트 링크 + 노트 인덱스 갱신

    ### PARA 관리
    대시보드 → "PARA 관리"에서:
    - **카테고리 간 폴더 이동**: 우클릭 → Project↔Area↔Resource↔Archive 간 이동
    - **프로젝트 인라인 생성**: + 버튼으로 새 프로젝트 즉시 생성
    - **폴더별 자동 정리**: 우클릭 → 자동 정리로 해당 폴더 AI 재분류
    - **Finder 열기**: 우클릭으로 해당 폴더 바로 열기
    - 이동 시 내부 노트의 프론트매터(`para` 필드)와 볼트 내 `[[위키링크]]` 자동 갱신

    ### 볼트 전체 재정리
    대시보드 → "전체 재정리"에서:
    - **전체 볼트** 또는 **카테고리별** 스캔 선택
    - AI가 각 파일의 현재 위치 vs 추천 위치를 비교
    - 체크박스로 이동할 파일 선택 → 실행
    - 최대 200개 파일 스캔 (API 비용 제어)

    ### 볼트 감사 (Audit)
    볼트 전체 건강 검사:
    - 깨진 `[[위키링크]]` 탐지 + Levenshtein 거리 기반 자동 수정 (편집 거리 ≤ 3)
    - 프론트매터 누락 탐지 + 자동 주입
    - 태그 누락 탐지
    - PARA 필드 누락 탐지 + 경로 기반 자동 추론

    ### 분류 확신도
    - confidence ≥ 0.8 → 자동 처리
    - confidence ≥ 0.5 → 처리하되 사용자에게 보고
    - confidence < 0.5 → 사용자에게 확인 요청

    ### 충돌 처리
    - **이름 충돌**: 대상에 같은 파일명이 있으면 사용자 확인
    - **중복 콘텐츠**: SHA256 일치 시 태그 병합 후 자동 삭제

    ---

    ## 프론트매터 스키마 (전체 필드)

    모든 노트는 YAML 프론트매터를 가집니다. **각 필드의 의미와 사용법:**

    ```yaml
    ---
    para: project | area | resource | archive
    tags: [태그1, 태그2]         # 최대 5개, 한국어/영어 혼용
    created: 2026-01-15          # 최초 생성일 (YYYY-MM-DD)
    status: active | draft | completed | on-hold
    summary: "문서 내용 2-3문장 요약"
    source: original | meeting | literature | import
    project: "관련 프로젝트명"    # PARA와 무관하게, 관련 프로젝트가 있으면 기재
    file:                         # 바이너리 동반 노트에만 사용
      name: "원본파일.pdf"
      format: pdf
      size_kb: 1234
    ---
    ```

    ### 필드별 상세 가이드

    **para** — PARA 카테고리
    - `project`: 해당 프로젝트의 **직접적인 작업 문서**만 (액션 아이템, 마감 관련). 반드시 `project` 필드에 프로젝트명 기재.
    - `area`: 기한 없이 지속 관리하는 영역 (운영, 모니터링, 건강)
    - `resource`: 참고 자료, 학습 자료, 가이드, 레퍼런스
    - `archive`: 완료되었거나 더 이상 활성이 아닌 항목

    **status** — 노트 상태
    - `active`: 현재 사용 중
    - `draft`: 작성 중 (미완성)
    - `completed`: 완료됨
    - `on-hold`: 일시 중단

    **source** — 노트 출처
    - `original`: 직접 작성
    - `meeting`: 미팅에서 나온 내용
    - `literature`: 외부 자료 정리 (논문, 기사, 책)
    - `import`: 다른 시스템에서 가져온 문서

    **project** — 관련 프로젝트
    - `para`가 project가 아니어도, 관련 프로젝트가 있으면 기재
    - 예: `para: resource`인 참고 자료가 특정 프로젝트와 관련 → `project: MyProject`
    - 값은 `1_Project/` 아래 폴더명과 정확히 일치해야 함

    **file** — 바이너리 동반 노트용
    - PDF, DOCX, PPTX, XLSX, 이미지 등의 바이너리 파일에 대한 마크다운 동반 노트에서 사용
    - 원본 파일은 `_Assets/`에, 동반 노트는 해당 폴더에 위치

    ---

    ## 검색 패턴

    이 볼트에서 문서를 찾을 때 사용하는 Grep 패턴:

    ### PARA 카테고리로 검색
    ```
    Grep("^para: project", glob: "**/*.md")      # 모든 프로젝트 문서
    Grep("^para: area", glob: "**/*.md")          # 모든 영역 문서
    Grep("^para: resource", glob: "**/*.md")      # 모든 참고 자료
    Grep("^para: archive", glob: "**/*.md")       # 모든 아카이브
    ```

    ### 태그로 검색
    ```
    Grep("tags:.*DeFi", glob: "**/*.md")          # DeFi 태그 포함 노트
    Grep("tags:.*회의록", glob: "**/*.md")         # 회의록 태그
    ```

    ### 상태로 검색
    ```
    Grep("^status: active", glob: "**/*.md")      # 활성 노트만
    Grep("^status: draft", glob: "**/*.md")       # 작성 중인 노트
    Grep("^status: completed", glob: "**/*.md")   # 완료된 노트
    ```

    ### 프로젝트로 검색
    ```
    Grep("^project: MyProject", glob: "**/*.md")  # 특정 프로젝트 관련 전체 노트
    ```

    ### 본문 키워드 검색
    ```
    Grep("검색어", glob: "**/*.md")                # 본문에서 키워드 검색
    ```

    ### 검색 시 제외할 폴더
    - `_Inbox/` (처리 대기 중, 미완성)
    - `.claude/`, `.Templates/`, `.obsidian/` (시스템 폴더)
    - 아카이브 결과는 포함하되 "(아카이브)" 표시

    ---

    ## PARA 분류 규칙

    DotBrain과 AI 에이전트가 문서를 분류할 때 적용하는 규칙:

    1. 프론트매터에 `para:`가 이미 있으면 → **그대로 유지**
    2. 해당 프로젝트의 직접적 작업 문서 (액션, 체크리스트, 마감) → **project** (반드시 `project` 필드 기재)
    3. 유지보수/모니터링/운영/지속적 책임 → **area**
    4. 분석 자료, 가이드, 레퍼런스, 학습 자료 → **resource**
    5. 완료되었거나 장기간 미수정 → **archive**
    6. 확신이 낮으면 → 사용자에게 질문

    ⚠️ 프로젝트와 **관련된** 참고 자료는 `project`가 아니라 `resource`로 분류 (`project` 필드에 프로젝트명 기재)
    ⚠️ 운영/관리 문서는 `project`가 아니라 `area`로 분류
    ⚠️ 활성 프로젝트 목록에 없는 프로젝트명은 자동 생성하지 않음 → 사용자에게 확인 요청

    ---

    ## ⚠️ AI 파일/폴더 이동 필수 규칙

    **AI가 파일이나 폴더를 이동할 때 반드시 아래 전체 체크리스트를 수행해야 합니다.**
    파일 이동(`mv`)만 하고 메타데이터를 갱신하지 않으면 볼트 무결성이 깨집니다.

    ### 이동 감지 키워드

    다음 표현이 나오면 이동 작업으로 인식:
    - "보내줘", "옮겨줘", "이동해줘", "Archive로", "귀속", "에 넣어줘"
    - "이 프로젝트 끝났어", "더 이상 안 써", "비활성화해줘"
    - "다시 활성화해줘", "꺼내줘"

    ### 이동 유형별 처리

    | 유형 | 예시 | para 변경 | status 변경 |
    |------|------|-----------|-------------|
    | **아카이브** | Project → Archive | `archive` | `completed` |
    | **활성화** | Archive → Project | `project` | `active` |
    | **카테고리 이동** | Project → Area | 대상 카테고리 | 유지 |
    | **폴더 내 이동** | ProjectA → PoC-Alpha 하위 | 유지 | 유지 |

    ### 필수 체크리스트 (모든 이동에 적용)

    이동 작업 시 **반드시** 다음 7단계를 순서대로 수행:

    1. **파일/폴더 이동** — `mv`로 대상 이동
    2. **프론트매터 갱신** — 이동 대상의 모든 `.md` 파일:
       - `para:` 필드를 새 카테고리에 맞게 변경
       - `status:` 필드를 이동 유형에 맞게 변경
       - Archive 이동 시: `para: archive`, `status: completed`
       - `project:` 필드가 있으면 새 상위 프로젝트명으로 갱신
    3. **노트 인덱스 자동 갱신** — DotBrain이 다음 실행 시 `.meta/note-index.json` 자동 갱신
       - AI 에이전트가 직접 인덱스를 수정할 필요 없음
    4. **하위 파일 일괄 처리** — 폴더 이동인 경우:
       - 폴더 내 모든 `.md` 파일의 프론트매터도 동일하게 갱신
    5. **결과 보고** — 변경 사항 테이블로 보고

    ### 검증 질문 (자가 점검)

    이동 완료 후 스스로 확인:
    - ✅ 이동한 모든 파일의 `para:` 필드가 새 위치와 일치하는가?
    - ✅ 하위 파일의 프론트매터도 모두 갱신되었는가?

    ---

    ## 관련 노트 링크

    DotBrain은 **AI 시맨틱 분석**으로 관련 노트를 연결합니다:
    - `.meta/note-index.json`을 파싱하여 **VaultContextMap**을 구축
    - 단순 태그 일치가 아닌 **맥락적 연관성** 기반 추천
    - 같은 폴더뿐 아니라 **다른 카테고리의 노트도** 적극 연결
    - 문서당 최대 **5개** 관련 노트
    - context는 `"~하려면"`, `"~할 때"`, `"~와 비교할 때"` 형식

    ```markdown
    ## Related Notes

    - [[Aave_Analysis]] — 프로토콜 설계의 기술적 근거를 확인하려면
    - [[DeFi_Market_Report]] — 시장 전체 트렌드와 비교할 때
    - [[Risk_Framework]] — 리스크 평가 기준을 참조할 때
    ```

    ❌ 나쁜 예: `- [[Aave_Analysis]]`
    ✅ 좋은 예: `- [[Aave_Analysis]] — 프로토콜 설계의 기술적 근거를 확인하려면`

    ---

    ## 에이전트 시스템

    이 PKM에는 특화된 AI 에이전트가 정의되어 있습니다:

    | 트리거 문구 | 에이전트 | 파일 |
    |---|---|---|
    | "인박스 정리해줘" | 인박스 분류 | `.claude/agents/inbox-agent.md` |
    | "OO 옮겨줘/보내줘/귀속" | PARA 이동 | `.claude/agents/para-move-agent.md` |
    | "프로젝트 만들어줘" | 프로젝트 관리 | `.claude/agents/project-agent.md` |
    | "OO 관련 자료 찾아줘" | 검색 | `.claude/agents/search-agent.md` |
    | "OO 종합해줘" | 종합/브리핑 | `.claude/agents/synthesis-agent.md` |
    | "주간 리뷰 해줘" | 정기 리뷰 | `.claude/agents/review-agent.md` |
    | "노트 다듬어줘" | 노트 관리 | `.claude/agents/note-agent.md` |
    | "링크 건강 점검해줘" | 링크 건강 | `.claude/agents/link-health-agent.md` |
    | "태그 정리해줘" | 태그 정리 | `.claude/agents/tag-cleanup-agent.md` |
    | "오래된 노트 점검해줘" | 콘텐츠 리뷰 | `.claude/agents/stale-review-agent.md` |
    | "볼트 점검해줘" | 볼트 건강 점검 | `.claude/agents/vault-audit-agent.md` |

    각 에이전트 파일에 상세 워크플로가 정의되어 있습니다.

    ## 스킬

    | 스킬 | 파일 | 역할 |
    |------|------|------|
    | 바이너리 처리 | `.claude/skills/inbox-processor/SKILL.md` | PDF/DOCX/PPTX/이미지 텍스트 추출 |
    | 회의록 작성 | `.claude/skills/meeting-note/SKILL.md` | 회의 내용 → 구조화된 회의록 |
    | 프로젝트 현황 | `.claude/skills/project-status/SKILL.md` | 프로젝트 상태 보고서 생성 |
    | 주간 리뷰 | `.claude/skills/weekly-review/SKILL.md` | 주간/월간 리뷰 보고서 |
    | 문헌 노트 | `.claude/skills/literature-note/SKILL.md` | 외부 자료 → 구조화된 문헌 노트 |
    | 프론트매터 검증 | `.claude/skills/frontmatter-validator/SKILL.md` | 프론트매터 스키마 검증 및 자동 수정 |
    | 인덱스 무결성 | `.claude/skills/index-integrity/SKILL.md` | note-index.json ↔ 실제 폴더/파일 동기화 검증 |

    ---

    ## 규칙

    - `_Inbox/`는 건드리지 마세요 (DotBrain이 자동 처리)
    - 새 노트 생성 시 프론트매터 포함 필수
    - `[[위키링크]]` 형식 사용 (Obsidian 호환)
    - 파일명에 특수문자 피하기
    - 기존 노트 수정 시 프론트매터 기존 값 유지

    ## ⚠️ 중요: 코드 파일 금지

    **이 폴더 안에서 코드를 작성하지 마세요!**

    - DotBrain이 코드 파일 (.swift, .ts, .py, .js, .go, .rs, .java 등)을 **인박스에서 필터링**합니다
    - 코드 프로젝트 폴더도 자동 감지하여 차단합니다
    - 개발 프로젝트는 이 PKM 폴더 **밖에서** 작업하세요
    - 이 폴더는 지식/문서 관리 전용입니다

    ## AI 작업 권장사항

    - **읽기**: 자유롭게 탐색 (위 탐색 우선순위 참조)
    - **쓰기**: 기존 노트 수정 시 프론트매터 기존 값 유지
    - **생성**: 마크다운 노트만, 적절한 PARA 폴더에, 프론트매터 필수
    - **검색**: 위 Grep 패턴 활용
    - **코드**: **절대 이 폴더 안에서 작성 금지**
    """

    // MARK: - AGENTS.md

    private static func generateAgentsMd(pkmRoot: String) throws {
        let fm = FileManager.default
        let path = (pkmRoot as NSString).appendingPathComponent("AGENTS.md")
        guard !fm.fileExists(atPath: path) else { return }
        let content = "\(markerStart)\n\(agentsMdContent)\n\(markerEnd)\n\n<!-- 아래에 자유롭게 추가하세요 -->\n"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static let agentsMdContent = """
    # AGENTS.md — DotBrain PKM Workspace

    이 파일은 AI 에이전트의 **행동 규칙**을 정의합니다.
    볼트 구조와 검색 방법은 `CLAUDE.md`를 참조하세요.

    ## 에이전트 시스템

    | 트리거 문구 | 에이전트 | 파일 |
    |---|---|---|
    | "인박스 정리해줘" | 인박스 분류 | `.claude/agents/inbox-agent.md` |
    | "OO 옮겨줘/보내줘/귀속" | PARA 이동 | `.claude/agents/para-move-agent.md` |
    | "프로젝트 만들어줘" | 프로젝트 관리 | `.claude/agents/project-agent.md` |
    | "OO 관련 자료 찾아줘" | 검색 | `.claude/agents/search-agent.md` |
    | "OO 종합해줘" | 종합/브리핑 | `.claude/agents/synthesis-agent.md` |
    | "주간 리뷰 해줘" | 정기 리뷰 | `.claude/agents/review-agent.md` |
    | "노트 다듬어줘" | 노트 관리 | `.claude/agents/note-agent.md` |
    | "링크 건강 점검해줘" | 링크 건강 | `.claude/agents/link-health-agent.md` |
    | "태그 정리해줘" | 태그 정리 | `.claude/agents/tag-cleanup-agent.md` |
    | "오래된 노트 점검해줘" | 콘텐츠 리뷰 | `.claude/agents/stale-review-agent.md` |
    | "볼트 점검해줘" | 볼트 건강 점검 | `.claude/agents/vault-audit-agent.md` |

    ## 프론트매터 병합 정책

    **인박스 처리 시:**
    - 빈 필드를 AI가 채움 (기존 값 존중)
    - `created`는 항상 보존 (없으면 오늘 날짜)
    - `tags`는 기존 태그에 추가만 가능, 삭제 금지

    **폴더 정리(Reorganize) 시:**
    - AI가 전체 프론트매터를 재생성 (`created`만 보존)
    - 잘못 분류된 파일은 올바른 PARA 위치로 자동 이동 (relocated)

    **PARA 카테고리 이동 시:**
    - 폴더 내 모든 노트의 `para` 필드를 대상 카테고리로 갱신
    - 볼트 전체에서 해당 폴더 내 파일의 `[[위키링크]]` 경로 자동 갱신

    **볼트 전체 재정리 시:**
    - AI가 현재 위치와 추천 위치를 비교하여 이동 필요 파일 식별
    - 사용자가 체크박스로 선택한 파일만 이동
    - 이동 시 프론트매터 + WikiLink 자동 갱신

    ## 관련 노트 링크 규칙

    DotBrain은 **AI 시맨틱 분석**으로 관련 노트를 찾습니다:
    - `.meta/note-index.json`을 파싱하여 VaultContextMap 구축
    - 단순 태그 일치가 아닌 **맥락적 연관성** 기반 추천
    - 같은 폴더뿐 아니라 **다른 카테고리의 노트도** 적극 연결
    - 문서당 최대 **5개** 관련 노트
    - `[[위키링크]]` 형식 사용
    - context는 `"~하려면"`, `"~할 때"`, `"~와 비교할 때"` 형식으로 작성
    - 자기 자신은 포함하지 않음

    ## 금지 사항

    - `_Inbox/` 수정 금지 (DotBrain이 자동 처리)
    - 코드 파일 생성 금지 (DotBrain이 인박스에서 필터링)
    - 기존 태그 삭제 금지
    - 개발 작업은 이 PKM 폴더 밖에서
    """

    // MARK: - .cursorrules

    private static func generateCursorRules(pkmRoot: String) throws {
        let fm = FileManager.default
        let path = (pkmRoot as NSString).appendingPathComponent(".cursorrules")
        guard !fm.fileExists(atPath: path) else { return }
        let content = "\(markerStart)\n\(cursorRulesContent)\n\(markerEnd)\n\n<!-- 아래에 자유롭게 추가하세요 -->\n"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static let cursorRulesContent = """
    # PKM Knowledge Base Rules — DotBrain

    This is a PARA-organized PKM vault managed by DotBrain.

    ## Structure
    - `_Inbox/`: Auto-processed by DotBrain (**do not modify**)
    - `1_Project/`: Active projects with goals and deadlines
    - `2_Area/`: Ongoing responsibilities without deadlines
    - `3_Resource/`: Reference materials and interests
    - `4_Archive/`: Completed or inactive items
    - `_Assets/`: Global attachments (binary files)
    - `.Templates/`: Note templates (Note.md, Project.md, Asset.md)
    - `.claude/agents/`: AI agent workflow definitions
    - `.claude/skills/`: AI skill definitions

    ## DotBrain Automation
    - **Inbox Processing**: 2-stage AI classification (Fast batch → Precise for uncertain), weighted context matching, AI semantic linking, auto note-index.json update
    - **Folder Reorganization**: Flatten nested folders → deduplicate (SHA256) → AI reclassify → auto-relocate misclassified files
    - **PARA Management**: Move folders between P/A/R/A categories, create projects, per-folder auto-reorganize (Dashboard → PARA 관리)
    - **Vault Reorganization**: Cross-category AI scan → compare current vs recommended location → selective execution (Dashboard → 전체 재정리, max 200 files)
    - **Vault Audit**: Detect broken WikiLinks, missing frontmatter/tags/PARA → auto-repair with Levenshtein matching

    ## AI Agents (11 agents in `.claude/agents/`)
    - inbox-agent: Inbox classification and processing
    - project-agent: Project lifecycle management
    - search-agent: Vault-wide knowledge search
    - synthesis-agent: Topic synthesis and briefing generation
    - review-agent: Periodic vault review (weekly/monthly)
    - note-agent: Note writing, polishing, connecting, and QA
    - link-health-agent: WikiLink health check and orphan detection
    - tag-cleanup-agent: Tag standardization and deduplication
    - stale-review-agent: Stale content review and quality check
    - vault-audit-agent: Comprehensive vault health check (structure, frontmatter, links, index)

    ## AI Skills (7 skills in `.claude/skills/`)
    - inbox-processor: Binary file text extraction
    - meeting-note: Meeting content → structured meeting note
    - project-status: Project status report generation
    - weekly-review: Weekly/monthly review report
    - literature-note: External sources → structured literature note
    - frontmatter-validator: Frontmatter schema validation and auto-fix
    - index-integrity: note-index.json ↔ folder/file synchronization check

    ## Navigation Priority
    1. Read `.meta/note-index.json` for vault structure overview (tags, summary, project, status per note)
    2. Read `CLAUDE.md` for detailed structure, frontmatter schema, and classification rules
    3. Follow `[[wikilinks]]` in `## Related Notes` sections — relation priority: prerequisite > project > reference > related
    4. Search by frontmatter fields using grep patterns

    ## Frontmatter Schema (8 fields)
    ```yaml
    para: project | area | resource | archive
    tags: [tag1, tag2]              # max 5
    created: YYYY-MM-DD
    status: active | draft | completed | on-hold
    summary: "2-3 sentence summary"
    source: original | meeting | literature | import
    project: "related project name"  # matches folder name in 1_Project/
    file:                            # binary companion notes only
      name: "filename.pdf"
      format: pdf
      size_kb: 1234
    ```

    ## Search Patterns
    ```
    grep "^para: project" **/*.md        # all project docs
    grep "tags:.*keyword" **/*.md        # search by tag
    grep "^status: active" **/*.md       # active notes
    grep "^project: ProjectName" **/*.md # notes related to a project
    grep "keyword" **/*.md               # body search
    ```

    ## PARA Classification Rules
    1. If frontmatter has `para:` already → keep it
    2. Direct project work docs (action items, checklists, deadlines) → `project` (must set `project` field)
    3. Ongoing maintenance, operations → `area`
    4. Reference, guides, learning → `resource`
    5. Completed or stale → `archive`
    ⚠️ Project-related reference material → `resource` (NOT `project`), set `project` field

    ## Related Notes
    - DotBrain uses **AI semantic analysis** (not tag matching) to find related notes
    - Based on VaultContextMap built from .meta/note-index.json
    - Cross-category linking encouraged
    - No artificial limit — all genuinely related notes are connected
    - Context format: "~하려면", "~할 때", "~와 비교할 때"

    ## Writing Rules
    - Preserve existing frontmatter values when editing
    - Use `[[wikilinks]]` for internal links
    - Include contextual descriptions in Related Notes
    - New notes must include full frontmatter

    ## ⚠️ NO CODE FILES
    DO NOT create code files (.swift, .ts, .py, .js, .go, .rs, .java, etc.) in this folder!
    DotBrain filters out code files from inbox processing.
    """

    // MARK: - .claude/agents/

    private static func generateClaudeAgents(pkmRoot: String) throws {
        let fm = FileManager.default
        let agentsDir = (pkmRoot as NSString).appendingPathComponent(".claude/agents")
        try fm.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)

        let agents: [(String, String)] = [
            ("inbox-agent", inboxAgentContent),
            ("project-agent", projectAgentContent),
            ("search-agent", searchAgentContent),
            ("synthesis-agent", synthesisAgentContent),
            ("review-agent", reviewAgentContent),
            ("note-agent", noteAgentContent),
            ("link-health-agent", linkHealthAgentContent),
            ("tag-cleanup-agent", tagCleanupAgentContent),
            ("stale-review-agent", staleReviewAgentContent),
            ("para-move-agent", paraMoveAgentContent),
            ("vault-audit-agent", vaultAuditAgentContent),
        ]

        for (name, content) in agents {
            let path = (agentsDir as NSString).appendingPathComponent("\(name).md")
            if !fm.fileExists(atPath: path) {
                let wrapped = "\(markerStart)\n\(content)\n\(markerEnd)"
                try wrapped.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    private static let inboxAgentContent = """
    # 인박스 분류 에이전트

    ## 트리거
    - "인박스 정리해줘"
    - "이 파일 분류해줘"
    - "인박스에 뭐 있어?"
    - "이 노트 정리해줘"

    ## 워크플로 (DotBrain 자동 처리와 동일)

    ### Step 1: 인박스 스캔
    ```
    Glob("_Inbox/*")
    ```
    파일 목록과 개수를 확인합니다.

    ### Step 2: 프로젝트 컨텍스트 맵 구축
    기존 프로젝트와 폴더를 파악하여 분류 정확도를 높입니다:
    ```
    Glob("1_Project/*/")         → 활성 프로젝트 목록
    Glob("2_Area/*/")            → 영역 폴더 목록
    Glob("3_Resource/*/")        → 자료 폴더 목록
    ```
    `.meta/note-index.json`에서 각 폴더의 태그와 요약 정보를 수집합니다.
    기존 문서와의 가중치 기반 맥락도 구축합니다 (🔴 Project 높음 / 🟡 Area·Resource 중간 / ⚪ Archive 낮음).

    ### Step 3: 콘텐츠 추출 (병렬)

    **마크다운 파일 (.md):**
    - 본문 텍스트 추출 (최대 5,000자)

    **바이너리 파일 (PDF, DOCX, PPTX, XLSX, 이미지):**
    - 텍스트 추출 (`.claude/skills/inbox-processor/SKILL.md` 참조)

    **폴더:**
    - 내부 파일들의 내용을 합쳐서 추출

    ### Step 4: 2단계 AI 분류

    **Stage 1 — Fast 배치 분류:**
    - 파일 전체 내용(5000자)으로 분류 (5개씩 배치, 최대 3개 동시)
    - 기존 폴더가 있으면 해당 폴더명 우선 사용

    **Stage 2 — Precise 정밀 분류:**
    - Stage 1에서 confidence < 0.8인 파일만 전체 내용으로 정밀 분류
    - 2~3문장 요약 자동 생성

    ### Step 5: AI 시맨틱 관련 노트 링크

    - `.meta/note-index.json`을 파싱하여 VaultContextMap 구축
    - 맥락적 연관성 기반으로 관련 노트 추천
    - 같은 폴더뿐 아니라 다른 카테고리 노트도 적극 연결
    - context 형식: `"~하려면"`, `"~할 때"`, `"~와 비교할 때"`

    ### Step 6: 파일 이동 + 충돌 처리

    **자동 처리 (confidence ≥ 0.5):**
    - 대상 폴더로 이동 + 프론트매터 삽입 + 관련 노트 섹션 추가
    - 바이너리: 원본 → `_Assets/`, 동반 노트 생성

    **사용자 확인 필요:**
    - confidence < 0.5 → 분류 옵션 제시
    - 이름 충돌 → 대상에 같은 파일명이 존재할 때

    ### Step 7: 인덱스 갱신 + 알림

    - 영향받은 모든 폴더의 노트 인덱스 자동 갱신
    - macOS 알림으로 처리 결과 보고

    ### Step 8: 결과 요약

    처리 완료 후 테이블로 결과를 보고합니다:
    ```
    | 파일 | PARA | 대상 폴더 | 태그 |
    |------|------|----------|------|
    | meeting_0115.md | project | MyProject | 회의록, Q1 |
    ```

    ## 노트 정리 모드

    "이 노트 정리해줘" 트리거 시:
    - 파일을 이동하지 **않음**
    - 빈 프론트매터 필드만 AI로 채움
    - 관련 노트 링크 보강

    ## 관련 노트 추가 규칙

    단순 링크가 아닌 컨텍스트를 포함:
    ```markdown
    ## Related Notes
    - [[프로젝트명]] — 소속 프로젝트
    - [[관련노트]] — 이 자료를 왜 참조해야 하는지 한 줄 설명
    ```
    """

    private static let projectAgentContent = """
    # 프로젝트 관리 에이전트

    ## 트리거
    - "프로젝트 만들어줘"
    - "이 프로젝트 끝났어"
    - "이 프로젝트 다시 시작할게"
    - "프로젝트 이름 바꿔줘"

    ## 프로젝트 생성

    1. 이름 파싱 → 폴더명 생성 (특수문자 제거)
    2. `1_Project/폴더명/` 디렉토리 생성
    3. 결과 보고

    ## 프로젝트 완료 (아카이브)

    1. 모든 노트의 `status` → `completed`, `para` → `archive`로 갱신
    2. `1_Project/폴더명/` → `4_Archive/폴더명/`으로 이동
    3. 볼트 전체에서 `[[프로젝트명]]` 링크 뒤에 "(완료됨)" 추가
    4. 갱신된 노트 수 보고

    ## 프로젝트 재활성화

    1. `4_Archive/폴더명/` → `1_Project/폴더명/`으로 이동
    2. 모든 노트의 `status` → `active`, `para` → `project`로 갱신
    3. "(완료됨)" 마크 제거
    4. 갱신된 노트 수 보고

    ## PARA 카테고리 간 이동 (DotBrain UI)

    DotBrain의 "PARA 관리" 화면에서 우클릭으로도 가능:
    - Project → Area/Resource/Archive
    - Area → Project/Resource/Archive
    - 이동 시 내부 노트의 `para` 필드 자동 갱신
    - 볼트 내 `[[위키링크]]` 경로 자동 갱신

    ## 프로젝트 이름 변경

    1. 새 폴더명 생성
    2. 폴더명 변경
    3. 볼트 전체에서 `[[이전이름]]` → `[[새이름]]`으로 변경
    4. 변경된 참조 수 보고
    """

    private static let searchAgentContent = """
    # 검색 에이전트

    ## 트리거
    - "OO 관련 자료 찾아줘"
    - "OO 검색해줘"
    - "OO에 대한 노트 있어?"

    ## 검색 워크플로

    ### Step 1: 검색 실행

    세 가지 방법을 순차적으로 사용합니다:

    **1단계: 프론트매터 태그 검색**
    ```
    Grep("tags:.*검색어", glob: "**/*.md")
    ```
    태그는 `tags: ["tag1", "tag2"]` 인라인 배열 형식입니다.
    정확한 태그 매칭이 필요하면: `Grep("\"검색어\"", glob: "**/*.md")`

    **2단계: 본문 키워드 검색**
    ```
    Grep("검색어", glob: "**/*.md")
    ```

    **3단계: 바이너리 동반 노트 포함**
    `.pdf.md`, `.pptx.md` 등 동반 노트도 검색 대상에 포함합니다.

    ### Step 2: 결과 정리

    검색 결과를 관련도 순으로 테이블로 정리합니다:
    ```
    | 노트 | 위치 | 요약 | 관련도 |
    |------|------|------|--------|
    | [[Note_A]] | 1_Project/MyProject | 핵심 분석 문서 | 높음 |
    | [[Note_B]] | 3_Resource/DeFi | 참고 자료 | 중간 |
    | [[Note_C]] | 4_Archive/Old (아카이브) | 이전 버전 | 낮음 |
    ```

    ### Step 3: 관련 검색 제안

    결과가 부족하면 유사 태그나 관련 주제를 제안합니다:
    - "이런 태그도 검색해볼까요: DeFi, 블록체인, 스마트컨트랙트"

    ## 검색 범위

    **포함:**
    - `1_Project/`, `2_Area/`, `3_Resource/`, `4_Archive/` 아래 모든 `.md` 파일

    **제외:**
    - `_Inbox/` (미처리 파일)
    - `.claude/`, `.Templates/`, `.obsidian/` (시스템 폴더)
    - `_Assets/` 내 바이너리 파일 (동반 .md는 검색)

    ## 아카이브 처리

    - 아카이브 결과는 포함하되 "(아카이브)" 표시
    - 관련도가 동일하면 활성 노트 우선
    """

    private static let synthesisAgentContent = """
    # 종합/브리핑 에이전트

    ## 트리거
    - "OO 종합해줘"
    - "OO 브리핑 만들어줘"
    - "OO 주제로 정리해줘"
    - "OO에 대해 알고 있는 것 모아줘"

    ## 워크플로

    ### Step 1: 주제 파악 및 검색
    사용자가 요청한 주제 키워드를 추출하고, 볼트 전체를 검색합니다:
    ```
    Grep("키워드", glob: "**/*.md")
    Grep("tags:.*키워드", glob: "**/*.md")
    ```

    ### Step 2: 관련 노트 수집
    검색 결과에서 관련 노트를 읽고 핵심 내용을 추출합니다:
    - 프론트매터의 `tags`, `summary`, `project` 확인
    - 본문에서 주제 관련 핵심 문장 추출
    - `## Related Notes` 섹션의 링크를 따라가며 추가 노트 수집

    ### Step 3: 종합 브리핑 생성
    수집한 내용을 다음 구조로 종합합니다:

    ```markdown
    ---
    para: resource
    tags: [주제, 브리핑, 종합]
    created: YYYY-MM-DD
    status: active
    summary: "OO 주제에 대한 볼트 내 지식 종합"
    source: original
    ---

    # OO 브리핑

    ## 핵심 요약
    (3-5문장으로 주제의 전체 그림)

    ## 상세 내용
    ### 주요 발견
    (노트에서 추출한 핵심 인사이트)

    ### 데이터 포인트
    (수치, 날짜, 구체적 사실)

    ### 관점과 논쟁
    (상충하는 의견이 있으면 정리)

    ## 출처 노트
    - [[노트1]] — 핵심 분석 자료
    - [[노트2]] — 배경 정보

    ## 지식 갭
    (볼트에 없는 정보, 추가 조사 필요한 부분)

    ## Related Notes
    ```

    ### Step 4: 저장 위치 결정
    - 특정 프로젝트 관련 → `1_Project/프로젝트명/`
    - 일반 주제 → `3_Resource/적절한폴더/`
    - 사용자에게 위치 확인

    ### Step 5: 인덱스 갱신
    DotBrain이 노트 인덱스 자동 갱신 (에이전트 수동 작업 불필요)

    ## 주의사항
    - 볼트에 없는 정보를 지어내지 않음
    - 출처 노트를 반드시 명시
    - "지식 갭" 섹션으로 부족한 부분 투명하게 표시
    """

    private static let reviewAgentContent = """
    # 정기 리뷰 에이전트

    ## 트리거
    - "주간 리뷰 해줘"
    - "월간 리뷰 해줘"
    - "볼트 리뷰해줘"
    - "이번 주 정리해줘"

    ## 워크플로

    ### Step 1: 기간 결정
    - "주간" → 최근 7일
    - "월간" → 최근 30일
    - 명시 없으면 → 주간(7일) 기본

    ### Step 2: 활동 스캔

    **최근 생성된 노트:**
    ```
    Grep("^created: YYYY-MM-", glob: "**/*.md")
    ```
    날짜 범위 내 생성된 노트를 수집합니다.

    **최근 수정된 파일:**
    파일 시스템 수정일 기준으로 변경된 파일을 확인합니다.

    **프로젝트 상태 점검:**
    ```
    Glob("1_Project/*/")
    ```
    `.meta/note-index.json`에서 각 프로젝트 노트의 status를 확인합니다.

    ### Step 3: 건강 지표 수집

    - **인박스 잔량**: `Glob("_Inbox/*")` → 미처리 파일 수
    - **드래프트 노트**: `Grep("^status: draft", glob: "**/*.md")` → 미완성 노트
    - **고아 노트**: 다른 노트에서 링크되지 않은 노트 (link-health-agent 로직 참조)
    - **태그 없는 노트**: `tags: []`인 노트 수

    ### Step 4: 리뷰 보고서 생성

    `.claude/skills/weekly-review/SKILL.md`의 템플릿을 사용하여 보고서를 생성합니다.

    ### Step 5: 액션 아이템 제안

    리뷰 결과에 기반한 실행 가능한 제안:
    - "드래프트 3개를 완성하거나 아카이브하세요"
    - "인박스에 5개 파일이 대기 중입니다"
    - "ProjectX에 2주간 업데이트가 없습니다"
    - "고아 노트 7개를 연결하거나 정리하세요"

    ### Step 6: 저장
    `3_Resource/Reviews/` 폴더에 `review_YYYY-MM-DD.md`로 저장

    ## 주의사항
    - 판단을 내리지 않고 사실만 보고
    - 액션 아이템은 구체적이고 실행 가능하게
    - 이전 리뷰가 있으면 비교하여 트렌드 언급
    """

    private static let noteAgentContent = """
    # 노트 관리 에이전트

    ## 트리거
    - "노트 써줘" (작성 모드)
    - "노트 다듬어줘" (다듬기 모드)
    - "이 노트 연결해줘" (연결 모드)
    - "노트 QA해줘" (품질 검사 모드)

    ## 모드 1: 작성 (Write)

    트리거: "노트 써줘", "OO에 대한 노트 만들어줘"

    ### 워크플로
    1. 사용자에게 주제/내용 확인
    2. 기존 관련 노트 검색 → 중복 방지
    3. 적절한 PARA 카테고리와 폴더 결정
    4. 프론트매터 포함 노트 생성:
       ```yaml
       ---
       para: (AI 판단)
       tags: [주제관련태그]
       created: YYYY-MM-DD
       status: active
       summary: "내용 요약"
       source: original
       ---
       ```
    5. `## Related Notes` 섹션에 관련 노트 링크
    6. DotBrain이 노트 인덱스 자동 갱신

    ## 모드 2: 다듬기 (Polish)

    트리거: "노트 다듬어줘", "이 노트 개선해줘"

    ### 워크플로
    1. 대상 노트 읽기
    2. 다음 항목 점검 및 개선:
       - 프론트매터 빈 필드 채우기
       - 문장 다듬기 (명확성, 간결성)
       - 구조화 (헤딩, 리스트, 볼드)
       - 맞춤법/문법 교정
    3. 변경 사항 요약 보고
    4. **원본 의미를 변경하지 않음**

    ## 모드 3: 연결 (Connect)

    트리거: "이 노트 연결해줘", "관련 노트 찾아서 연결해줘"

    ### 워크플로
    1. 대상 노트의 주제/태그/키워드 분석
    2. 볼트 전체에서 관련 노트 검색:
       ```
       Grep("tags:.*키워드", glob: "**/*.md")
       Grep("키워드", glob: "**/*.md")
       ```
    3. 관련도 순으로 최대 5개 선별
    4. `## Related Notes` 섹션 갱신:
       ```markdown
       - [[관련노트]] — 연결 이유 설명
       ```
    5. 양방향 링크: 관련 노트에도 역방향 링크 추가

    ## 모드 4: QA (Quality Assurance)

    트리거: "노트 QA해줘", "노트 품질 검사해줘"

    ### 워크플로
    1. 대상 노트(또는 폴더) 읽기
    2. 다음 품질 기준 점검:
       - ✅ 프론트매터 완전성 (8개 필드)
       - ✅ 태그 존재 여부
       - ✅ summary 필드 품질
       - ✅ Related Notes 존재 여부
       - ✅ 깨진 [[위키링크]]
       - ✅ 내용 길이 적절성
       - ✅ PARA 분류 정확성
    3. 점수와 개선점 보고:
       ```
       | 항목 | 상태 | 비고 |
       |------|------|------|
       | 프론트매터 | ✅ | 완전 |
       | 태그 | ⚠️ | 1개만 있음 |
       | Related Notes | ❌ | 없음 |
       ```
    4. "자동 수정할까요?" 제안

    ## 공통 규칙
    - 기존 프론트매터 값 보존
    - 기존 태그 삭제 금지
    - DotBrain이 노트 인덱스 자동 갱신
    """

    private static let linkHealthAgentContent = """
    # 링크 건강 에이전트

    ## 트리거
    - "링크 건강 점검해줘"
    - "깨진 링크 확인해줘"
    - "고아 노트 찾아줘"
    - "링크 분석해줘"

    ## 워크플로

    ### Step 1: 모든 위키링크 수집
    볼트 전체에서 `[[위키링크]]`를 추출합니다:
    ```
    Grep("\\[\\[.+?\\]\\]", glob: "**/*.md")
    ```

    ### Step 2: 깨진 링크 탐지
    각 `[[링크대상]]`에 대해 실제 파일 존재 여부를 확인합니다:
    ```
    Glob("**/링크대상.md")
    ```
    - 존재하지 않으면 → 깨진 링크
    - Levenshtein 거리 ≤ 3인 유사 파일 검색 → 자동 수정 후보 제시

    ### Step 3: 고아 노트 탐지
    다른 어떤 노트에서도 `[[참조]]`되지 않는 노트를 찾습니다:
    - `.Templates/`, `.claude/` 등 시스템 폴더 제외

    ### Step 4: 링크 밀도 분석
    각 노트의 링크 수를 분석합니다:
    - 링크 0개 → "고립된 노트" (연결 필요)
    - 링크 10개 이상 → "허브 노트" (정상)

    ### Step 5: 보고서 생성

    ```markdown
    # 링크 건강 보고서 (YYYY-MM-DD)

    ## 요약
    - 전체 노트: N개
    - 전체 링크: N개
    - 깨진 링크: N개
    - 고아 노트: N개

    ## 깨진 링크
    | 파일 | 깨진 링크 | 수정 후보 |
    |------|----------|----------|
    | note_a.md | [[없는노트]] | [[비슷한노트]] ? |

    ## 고아 노트
    | 파일 | 위치 | 제안 |
    |------|------|------|
    | lonely.md | 3_Resource/Topic | 연결 또는 아카이브 |

    ## 고립된 노트 (링크 0개)
    (목록)
    ```

    ### Step 6: 자동 수정 제안
    - "깨진 링크 N개를 자동 수정할까요?"
    - "고아 노트를 관련 노트에 연결할까요?"
    - 사용자 확인 후 실행

    ## 주의사항
    - 자동 수정은 Levenshtein 거리 ≤ 3인 경우만
    - 삭제는 절대 하지 않음 — 연결 또는 아카이브만 제안
    """

    private static let tagCleanupAgentContent = """
    # 태그 정리 에이전트

    ## 트리거
    - "태그 정리해줘"
    - "태그 통일해줘"
    - "중복 태그 찾아줘"
    - "태그 현황 보여줘"

    ## 워크플로

    ### Step 1: 전체 태그 수집
    볼트의 모든 마크다운 파일에서 `tags:` 필드를 파싱합니다:
    ```
    Grep("^tags:", glob: "**/*.md")
    ```
    태그 형식: `tags: [태그1, 태그2]` (인라인 YAML 배열)

    ### Step 2: 태그 분석

    **빈도 집계:**
    각 태그의 사용 횟수를 집계합니다.

    **유사 태그 탐지:**
    - 대소문자 차이: `DeFi` vs `defi` vs `DEFI`
    - 하이픈/언더스코어: `web-dev` vs `web_dev`
    - 단수/복수: `meeting` vs `meetings`
    - 영한 혼용: `blockchain` vs `블록체인`

    **고빈도/저빈도 분석:**
    - 1회만 사용된 태그 → 통합 또는 삭제 후보
    - 50회 이상 사용된 태그 → 세분화 필요 여부

    ### Step 3: 정리 계획 제시

    ```markdown
    # 태그 정리 계획

    ## 통합 제안 (유사 태그)
    | 현재 | 통합 대상 | 영향 파일 |
    |------|----------|----------|
    | DeFi, defi, DEFI | DeFi | 15개 |
    | web-dev, web_dev | web-dev | 8개 |

    ## 삭제 후보 (1회 사용)
    | 태그 | 파일 | 대체 제안 |
    |------|------|----------|
    | 임시메모 | note_x.md | 메모 |

    ## 태그 클라우드 (상위 20)
    DeFi(42) 회의록(35) 리서치(28) ...
    ```

    ### Step 4: 사용자 승인 후 실행
    - 각 통합/삭제에 대해 사용자 확인
    - 프론트매터의 `tags` 필드를 일괄 수정
    - DotBrain이 노트 인덱스 자동 갱신

    ## 주의사항
    - 태그 삭제는 반드시 사용자 확인 후
    - 대체 태그 없이 삭제하지 않음
    - 기존 태그 추가만 가능, 자동 삭제 금지 (사용자 명시적 요청 시에만)
    """

    private static let staleReviewAgentContent = """
    # 콘텐츠 리뷰 에이전트

    ## 트리거
    - "오래된 노트 점검해줘"
    - "콘텐츠 품질 검사해줘"
    - "정리 필요한 노트 찾아줘"
    - "볼트 품질 점검해줘"

    ## 워크플로

    ### Step 1: 오래된 노트 탐지
    다음 기준으로 "stale" 노트를 식별합니다:
    - `status: active`인데 90일 이상 수정 없음
    - `status: draft`인데 30일 이상 수정 없음
    - `para: project`인데 해당 프로젝트가 이미 아카이브됨

    ```
    Grep("^status: active", glob: "**/*.md")
    Grep("^status: draft", glob: "**/*.md")
    ```
    파일 수정일을 확인하여 기간 초과 여부 판단.

    ### Step 2: 품질 점검
    각 노트의 품질 지표를 검사합니다:

    **프론트매터 완전성:**
    - 필수 필드: `para`, `tags`, `created`, `status`, `summary`
    - 비어 있거나 누락된 필드 탐지

    **내용 품질:**
    - 본문 50자 미만 → "내용 부족"
    - 프론트매터만 있고 본문 없음 → "빈 노트"
    - `## Related Notes` 없음 → "연결 부족"

    **PARA 정합성:**
    - 파일 위치와 `para` 필드 불일치 → "분류 불일치"
    - 예: `1_Project/`에 있는데 `para: resource`

    ### Step 3: 보고서 생성

    ```markdown
    # 콘텐츠 품질 보고서 (YYYY-MM-DD)

    ## 요약
    - 전체 노트: N개
    - 오래된 노트 (90일+): N개
    - 미완성 드래프트 (30일+): N개
    - 품질 이슈: N개

    ## 오래된 활성 노트
    | 파일 | 위치 | 마지막 수정 | 제안 |
    |------|------|------------|------|
    | old_note.md | 2_Area/Ops | 120일 전 | 아카이브? |

    ## 미완성 드래프트
    | 파일 | 위치 | 생성일 | 제안 |
    |------|------|--------|------|
    | draft.md | 1_Project/X | 45일 전 | 완성 또는 삭제? |

    ## 품질 이슈
    | 파일 | 이슈 | 심각도 |
    |------|------|--------|
    | empty.md | 빈 노트 | 높음 |
    | no_tags.md | 태그 없음 | 중간 |
    ```

    ### Step 4: 액션 제안
    - "오래된 노트 N개를 아카이브할까요?"
    - "미완성 드래프트 N개를 정리할까요?"
    - "프론트매터 빈 필드를 자동 채울까요?"
    - 사용자 확인 후 실행

    ## 주의사항
    - 삭제는 절대 제안하지 않음 — 아카이브만 제안
    - 프론트매터 자동 채우기는 AI 추론, 사용자 확인 필요
    - `created` 필드는 절대 변경하지 않음
    """

    private static let paraMoveAgentContent = """
    # PARA 이동 에이전트

    파일/폴더의 PARA 카테고리 간 이동 및 폴더 내 재배치를 처리합니다.
    이동 시 프론트매터를 자동으로 갱신합니다. DotBrain이 노트 인덱스를 자동 갱신합니다.

    ## 트리거

    - "OO를 Archive로 보내줘"
    - "OO 옮겨줘", "OO 이동해줘"
    - "OO는 OO에 귀속이야", "OO에 넣어줘"
    - "이 프로젝트 끝났어", "더 이상 안 써"
    - "OO 다시 꺼내줘", "OO 활성화해줘"

    ## 이동 유형 판별

    사용자 의도를 파악하여 유형 결정:

    | 유형 | 판별 기준 | 예시 |
    |------|-----------|------|
    | **아카이브** | "끝났어", "Archive", "비활성", "안 써" | "ProjectA Archive로 보내줘" |
    | **활성화** | "꺼내줘", "다시 시작", "활성화" | "PoC-Alpha 다시 꺼내줘" |
    | **카테고리 이동** | "Area로", "Resource로" 등 명시적 카테고리 | "이건 Resource로 옮겨줘" |
    | **폴더 내 이동** | "귀속", "하위로", "안에 넣어줘" | "SubProject는 PoC-Alpha에 귀속이야" |

    ## 워크플로

    ### Step 1: 이동 대상 확인
    1. 사용자가 언급한 파일/폴더의 현재 위치 확인
    2. 이동 대상이 폴더인 경우 하위 파일 목록 확인
    3. 이동 목적지 경로 결정

    ### Step 2: 파일/폴더 이동

    ### Step 3: 프론트매터 갱신
    이동한 모든 `.md` 파일에 대해:
    - **아카이브**: `para: archive`, `status: completed`
    - **활성화**: `para: project`, `status: active`
    - **카테고리 이동**: `para:` → 대상 카테고리, status 유지
    - **폴더 내 이동**: para/status 유지, `project:` 필드만 갱신

    ### Step 4: 인덱스 자동 갱신
    - DotBrain이 `.meta/note-index.json`을 자동 갱신
    - AI 에이전트가 직접 인덱스를 수정할 필요 없음

    ### Step 5: 결과 보고
    변경 사항을 테이블로 보고

    ## 다중 이동
    여러 항목 동시 이동 시:
    1. 파일 이동을 먼저 모두 수행
    2. 프론트매터를 일괄 갱신
    3. DotBrain이 인덱스 자동 갱신
    4. 전체 결과를 하나의 테이블로 보고

    ## 검증 (자가 점검)
    - ✅ 이동한 모든 파일의 `para:` 필드가 새 위치와 일치?
    - ✅ 하위 파일 프론트매터 모두 갱신됨?

    ## 주의 사항
    - `_Inbox/`는 이동 대상/목적지로 사용 불가
    - 대상 폴더에 같은 이름의 파일이 있으면 사용자에게 확인
    - 위키링크는 파일명 기반이므로 경로 이동으로는 깨지지 않음
    """

    private static let vaultAuditAgentContent = """
    # 볼트 건강 점검 에이전트

    ## 트리거
    - "볼트 점검해줘"
    - "볼트 건강 확인해줘"
    - "전체 감사 해줘"
    - "vault audit"

    ## 개요

    볼트 전체의 구조, 프론트매터, 링크, 인덱스 무결성을 한번에 검사합니다.
    3개 검사를 **병렬 에이전트**로 실행한 뒤 종합 보고서를 생성하고, 자동 수정을 제안합니다.

    ## 워크플로

    ### Phase 1: 병렬 검사 (에이전트 3개 동시 실행)

    **에이전트 A: PARA 구조 + 프론트매터**
    `.claude/skills/frontmatter-validator/SKILL.md` 참조

    검사 항목:
    1. 4개 PARA 폴더 존재 (1_Project, 2_Area, 3_Resource, 4_Archive)
    2. 시스템 폴더 존재 (_Inbox, _Assets, .Templates)
    3. 최상위 orphan 파일 탐지 (PARA 폴더 밖의 .md 파일)
    4. 전체 프론트매터 스키마 검증

    **에이전트 B: 링크 무결성**
    `.claude/agents/link-health-agent.md` 워크플로 + 추가 검사:
    1. 깨진 `[[위키링크]]` 탐지
    2. Related Notes 형식 검증 (`[[링크]] — 설명` 형식)
    3. Related Notes 누락 파일 탐지 (콘텐츠 파일 중)
    4. 고아 노트 탐지

    **에이전트 C: 인덱스 무결성**
    `.claude/skills/index-integrity/SKILL.md` 참조

    ### Phase 2: 종합 보고서 생성

    ```markdown
    # 볼트 건강 점검 보고서 (YYYY-MM-DD)

    ## 종합 점수: N/100

    | 영역 | 점수 | 상태 | 발견 |
    |------|------|------|------|
    | PARA 구조 | /25 | ✅/⚠️/❌ | N건 |
    | 프론트매터 | /25 | ✅/⚠️/❌ | N건 |
    | 링크 무결성 | /25 | ✅/⚠️/❌ | N건 |
    | 인덱스 무결성 | /25 | ✅/⚠️/❌ | N건 |

    ## 높은 우선순위 (자동 수정 가능)
    | # | 파일 | 문제 | 수정 내용 |
    |---|------|------|----------|

    ## 중간 우선순위 (반자동)
    | # | 파일 | 문제 | 수정 내용 |
    |---|------|------|----------|

    ## 낮은 우선순위 (수동 확인)
    | # | 파일 | 문제 | 제안 |
    |---|------|------|------|
    ```

    ### 채점 기준

    각 영역 25점 만점:

    **PARA 구조 (25점)**
    - PARA 4폴더 존재: 10점
    - 시스템 폴더 존재: 5점
    - orphan 파일 없음: 5점
    - 하위 폴더 구조 정상: 5점

    **프론트매터 (25점)**
    - 필수 필드 존재율 × 10
    - para ↔ 폴더 일치율 × 5
    - Enum 값 유효율 × 5
    - summary 존재율 × 3
    - tags 규칙 준수율 × 2

    **링크 무결성 (25점)**
    - 깨진 링크 비율: (1 - 깨진/전체) × 15
    - Related Notes 커버율 × 5
    - 고아 노트 비율: (1 - 고아/전체) × 5

    **인덱스 무결성 (25점)**
    - note-index.json 존재 및 최신 여부: 10점
    - 인덱스 ↔ 실제 파일 동기화율 × 10
    - 인덱스 메타데이터(태그, 요약) 완성도: 5점

    ### Phase 3: 자동 수정

    사용자에게 확인 후 우선순위별로 수정 실행:

    **자동 수정 (확인 불필요):**
    - para ↔ 폴더 불일치 → para 값 변경
    - Archive 파일 status → completed
    - 인덱스 누락 노트 → DotBrain 재생성 트리거
    - 인덱스 ↔ 실제 불일치 → DotBrain 재생성 트리거

    **반자동 수정 (사용자 확인):**
    - summary 빈 값 → AI 요약 생성
    - tags > 5개 → 축소 제안
    - 깨진 링크 → 유사 파일 제안
    - orphan 파일 → PARA 분류 제안

    **수정 안함:**
    - 노트 인덱스 (DotBrain 자동 생성)
    - _Inbox 내부 (DotBrain 자동 처리)

    ### Phase 4: 변경 보고

    ```markdown
    ## 수정 완료 요약
    | # | 파일 | 변경 내용 |
    |---|------|----------|

    총 N개 파일 수정, N개 생성, N개 삭제
    ```

    ## 제외 대상
    - `_Inbox/` (DotBrain 자동 처리)
    - `.claude/`, `.Templates/`, `.obsidian/` (시스템)
    - Personal_Images 스텁 (summary 검증에서 제외)

    ## 주의사항
    - 삭제는 절대 하지 않음 — 이동 또는 수정만
    - 수정 전 반드시 사용자 확인 (자동 수정 항목 제외)
    - 보고서는 화면에 출력, 파일로 저장하지 않음
    """

    // MARK: - .claude/skills/

    private static func generateClaudeSkills(pkmRoot: String) throws {
        let fm = FileManager.default
        let allSkills: [(String, String)] = [
            ("inbox-processor", skillContent),
            ("meeting-note", meetingNoteSkillContent),
            ("project-status", projectStatusSkillContent),
            ("weekly-review", weeklyReviewSkillContent),
            ("literature-note", literatureNoteSkillContent),
            ("frontmatter-validator", frontmatterValidatorSkillContent),
            ("index-integrity", indexIntegritySkillContent),
        ]
        for (skillName, skillBody) in allSkills {
            let skillsDir = (pkmRoot as NSString).appendingPathComponent(".claude/skills/\(skillName)")
            try fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
            let path = (skillsDir as NSString).appendingPathComponent("SKILL.md")
            if !fm.fileExists(atPath: path) {
                let wrapped = "\(markerStart)\n\(skillBody)\n\(markerEnd)"
                try wrapped.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    private static let skillContent = """
    # 바이너리 파일 처리 스킬

    ## 용도

    인박스에 들어온 바이너리 파일(PDF, DOCX, PPTX, XLSX, 이미지)에서 텍스트와 메타데이터를 추출합니다.
    DotBrain이 자동으로 처리하지만, AI 에이전트가 수동으로 처리할 때 참조합니다.

    ## 지원 형식

    | 형식 | 추출 내용 | 동반 노트 |
    |------|----------|----------|
    | PDF | 텍스트 + 메타데이터 (제목, 작성자, 페이지 수) | `파일명.pdf.md` |
    | DOCX | 문서 텍스트 (ZIP 기반 추출) | `파일명.docx.md` |
    | PPTX | 슬라이드별 텍스트 | `파일명.pptx.md` |
    | XLSX | 시트별 데이터 | `파일명.xlsx.md` |
    | 이미지 | EXIF 메타데이터 | `파일명.jpg.md` |

    ## 동반 노트 구조

    바이너리 파일마다 마크다운 동반 노트를 생성합니다:

    ```yaml
    ---
    para: (AI가 분류)
    tags: []
    created: YYYY-MM-DD
    status: active
    summary: "추출된 내용 요약"
    source: import
    file:
      name: "원본파일.pdf"
      format: pdf
      size_kb: 1234
    ---

    # 원본파일.pdf

    ## 핵심 내용

    (추출된 텍스트 요약)

    ## Related Notes
    ```

    ## 파일 배치

    - 원본 바이너리 → 대상 폴더의 `_Assets/`
    - 동반 마크다운 → 대상 폴더 루트
    - 예: `3_Resource/DeFi/_Assets/report.pdf` + `3_Resource/DeFi/report.pdf.md`

    ## 텍스트 제한

    추출 텍스트는 최대 5,000자로 제한합니다.
    """

    private static let meetingNoteSkillContent = """
    # 회의록 작성 스킬

    ## 용도
    회의 내용(음성 전사, 메모, 요약)을 구조화된 회의록 노트로 변환합니다.

    ## 입력
    - 회의 제목 또는 주제
    - 회의 원문 (전사 텍스트, 메모, 또는 요약)
    - (선택) 참석자, 날짜, 관련 프로젝트

    ## 출력 형식

    ```yaml
    ---
    para: (project 또는 area)
    tags: [회의록, 프로젝트명]
    created: YYYY-MM-DD
    status: active
    summary: "회의 핵심 내용 2-3문장"
    source: meeting
    project: "관련프로젝트명"
    ---
    ```

    ```markdown
    # 회의 제목 (YYYY-MM-DD)

    ## 참석자
    - 이름1, 이름2, ...

    ## 안건
    1. 안건1
    2. 안건2

    ## 논의 내용

    ### 안건1: 제목
    - 핵심 논의 포인트
    - 결정 사항

    ### 안건2: 제목
    - 핵심 논의 포인트

    ## 결정 사항
    - [ ] 담당자: 액션 아이템 1 (기한: MM/DD)
    - [ ] 담당자: 액션 아이템 2

    ## 다음 단계
    - 후속 회의 일정
    - 확인 필요 사항

    ## Related Notes
    - [[관련노트]] — 연결 이유
    ```

    ## 처리 규칙
    - 원문의 핵심만 추출, 불필요한 대화 제거
    - 액션 아이템은 체크박스 형식 (`- [ ]`)
    - 담당자가 명확하면 반드시 기재
    - 관련 프로젝트가 있으면 `project` 필드 기재
    - 저장 위치: 관련 프로젝트 폴더 또는 `2_Area/`

    ## 파일명 규칙
    `meeting_MMDD_주제.md` (예: `meeting_0215_스프린트리뷰.md`)
    """

    private static let projectStatusSkillContent = """
    # 프로젝트 현황 보고서 스킬

    ## 용도
    특정 프로젝트의 모든 노트를 분석하여 현황 보고서를 생성합니다.

    ## 입력
    - 프로젝트명 (1_Project/ 아래 폴더명)

    ## 워크플로

    ### 1. 프로젝트 노트 수집
    ```
    Glob("1_Project/프로젝트명/**/*.md")
    Grep("^project: 프로젝트명", glob: "**/*.md")
    ```

    ### 2. 노트 분석
    - 각 노트의 `status` 집계 (active/draft/completed/on-hold)
    - 최근 수정된 노트 식별
    - 액션 아이템 (`- [ ]`, `- [x]`) 수집
    - 관련 다른 프로젝트 노트 확인

    ### 3. 보고서 생성

    ## 출력 형식

    ```markdown
    # 프로젝트명 — 현황 보고서 (YYYY-MM-DD)

    ## 요약
    (프로젝트의 목적/설명)

    ## 현재 상태
    - 전체 노트: N개
    - 활성: N개 | 드래프트: N개 | 완료: N개 | 보류: N개

    ## 최근 활동 (7일)
    | 노트 | 상태 | 마지막 수정 |
    |------|------|------------|
    | [[note1]] | active | 2일 전 |

    ## 미완료 액션 아이템
    - [ ] 항목1 (출처: [[meeting_0210]])
    - [ ] 항목2 (출처: [[task_list]])

    ## 완료 항목
    - [x] 항목A (출처: [[meeting_0205]])

    ## 관련 자료 (프로젝트 외부)
    - [[리소스노트]] — 참고 자료 (3_Resource/)

    ## 주의 사항
    - (오래된 드래프트, 누락된 정보 등)
    ```

    ## 저장
    `1_Project/프로젝트명/status_YYYY-MM-DD.md`
    """

    private static let weeklyReviewSkillContent = """
    # 주간/월간 리뷰 스킬

    ## 용도
    볼트 전체의 주간 또는 월간 활동을 분석하여 리뷰 보고서를 생성합니다.
    `review-agent`가 이 스킬을 사용합니다.

    ## 입력
    - 리뷰 기간: "주간" (7일) 또는 "월간" (30일)
    - (선택) 시작일

    ## 출력 형식

    ```yaml
    ---
    para: resource
    tags: [리뷰, 주간리뷰]
    created: YYYY-MM-DD
    status: completed
    summary: "YYYY-MM-DD 주간 리뷰"
    source: original
    ---
    ```

    ```markdown
    # 주간 리뷰 (MM/DD ~ MM/DD)

    ## 이번 주 요약
    - 새로 생성된 노트: N개
    - 수정된 노트: N개
    - 완료된 항목: N개

    ## 프로젝트별 진행
    ### ProjectA
    - 새 노트 2개, 완료 항목 3개
    - 주요 진전: (요약)

    ### ProjectB
    - 새 노트 1개
    - 주요 진전: (요약)

    ## 새로 추가된 노트
    | 노트 | 위치 | 태그 |
    |------|------|------|
    | [[new_note]] | 3_Resource/Topic | 키워드 |

    ## 인박스 현황
    - 처리 완료: N개
    - 대기 중: N개

    ## 볼트 건강
    - 전체 노트 수: N개
    - 깨진 링크: N개
    - 태그 없는 노트: N개
    - 드래프트 노트: N개

    ## 다음 주 제안
    - [ ] 드래프트 N개 완성 필요
    - [ ] 오래된 노트 N개 리뷰 필요
    - [ ] 프로젝트X 업데이트 필요

    ## Related Notes
    - [[이전 리뷰]] — 트렌드 비교
    ```

    ## 저장
    `3_Resource/Reviews/review_YYYY-MM-DD.md`
    (Reviews 폴더가 없으면 자동 생성)
    """

    private static let literatureNoteSkillContent = """
    # 문헌 노트 스킬

    ## 용도
    외부 자료(논문, 기사, 책, 영상)를 구조화된 문헌 노트로 변환합니다.

    ## 입력
    - URL, 제목, 또는 원문 텍스트
    - (선택) 관련 프로젝트, 추가 메모

    ## 출력 형식

    ```yaml
    ---
    para: resource
    tags: [문헌, 주제태그]
    created: YYYY-MM-DD
    status: active
    summary: "자료 핵심 내용 2-3문장"
    source: literature
    project: "관련프로젝트명"
    ---
    ```

    ```markdown
    # 자료 제목

    ## 메타데이터
    - **저자**: 이름
    - **출처**: URL 또는 출판 정보
    - **날짜**: 발행일
    - **유형**: 논문 | 기사 | 책 | 영상 | 보고서

    ## 핵심 요약
    (자료의 핵심 내용 3-5문장)

    ## 주요 내용

    ### 핵심 주장/발견
    1. 포인트 1
    2. 포인트 2
    3. 포인트 3

    ### 데이터/증거
    - 주요 수치나 데이터 포인트

    ### 방법론 (해당 시)
    - 연구 방법, 분석 프레임워크

    ## 나의 생각
    (사용자의 코멘트, 의견, 질문 — 사용자가 제공한 경우)

    ## 인용/발췌
    > "핵심 인용문" (p.XX)

    ## 적용 가능성
    - 어떤 프로젝트/영역에 활용 가능한지
    - 후속 조사가 필요한 부분

    ## Related Notes
    - [[관련노트]] — 연결 이유
    ```

    ## 처리 규칙
    - URL이 주어지면 내용을 읽고 요약 (WebFetch 활용)
    - 원문이 길면 핵심만 추출 (최대 5,000자)
    - 저자의 주장과 사용자의 의견을 명확히 구분
    - `source: literature` 필수
    - 관련 프로젝트가 있으면 `project` 필드 기재

    ## 파일명 규칙
    `저자_제목요약.md` 또는 `제목요약.md`
    (예: `Buterin_Endgame.md`, `DeFi_Risk_Report_2026.md`)

    ## 저장 위치
    `3_Resource/적절한주제폴더/`
    """

    private static let frontmatterValidatorSkillContent = """
    # 프론트매터 검증 스킬

    ## 용도

    볼트 전체 또는 특정 폴더의 마크다운 파일 프론트매터가 스키마를 준수하는지 검증하고, 위반 항목을 자동 수정합니다.
    `vault-audit-agent`의 하위 검사로 호출되거나, 단독으로 "프론트매터 점검해줘"로 실행할 수 있습니다.

    ## 스키마 정의

    ### 필수 필드

    ```yaml
    para: project | area | resource | archive
    tags: [태그1, 태그2]       # 최대 5개
    created: YYYY-MM-DD
    status: active | draft | completed | on-hold
    summary: "2-3문장 요약"    # 빈 값 불가
    source: original | meeting | literature | import
    ```

    ### 선택 필드

    ```yaml
    project: "프로젝트명"      # 1_Project/ 하위 폴더명과 일치해야 함
    file:                       # 바이너리 동반 노트에만
      name: "원본파일.pdf"
      format: pdf
      size_kb: 1234
    ```

    ## 검증 절차

    ### Step 1: 대상 파일 수집

    ```
    Glob("**/*.md") 에서 제외:
    - _Inbox/**
    - .claude/**
    - .Templates/**
    - .obsidian/**
    ```

    ### Step 2: 필수 필드 존재 확인

    각 파일에 대해 6개 필수 필드 존재 여부 검사:

    ```
    Grep("^para:", glob: "**/*.md")
    Grep("^tags:", glob: "**/*.md")
    Grep("^created:", glob: "**/*.md")
    Grep("^status:", glob: "**/*.md")
    Grep("^summary:", glob: "**/*.md")
    Grep("^source:", glob: "**/*.md")
    ```

    ### Step 3: Enum 값 유효성

    | 필드 | 허용 값 |
    |------|--------|
    | para | project, area, resource, archive |
    | status | active, draft, completed, on-hold |
    | source | original, meeting, literature, import |

    유효하지 않은 값 → 위반으로 기록

    ### Step 4: para ↔ 폴더 일치

    | 파일 위치 | 기대 para 값 |
    |----------|-------------|
    | 1_Project/** | project |
    | 2_Area/** | area |
    | 3_Resource/** | resource |
    | 4_Archive/** | archive |

    불일치 → **자동 수정** (폴더 기준으로 para 변경)

    ### Step 5: tags 개수

    - 최대 5개. 초과 시 위반.

    ### Step 6: summary 비어있는지

    ```
    Grep("^summary: ?$|^summary: \\"\\"$", glob: "**/*.md")
    ```

    비어있는 파일 중 제외:
    - .Templates/ 파일
    - Personal_Images 스텁 (*.png.md, *.jpg.md 등)
    - 본문이 프론트매터만 있는 빈 파일

    비어있는 콘텐츠 파일 → 본문을 읽고 AI가 1-2문장 한글 요약 생성

    ### Step 7: project 필드 참조 유효성

    `project` 값이 있으면 `1_Project/` 하위에 해당 폴더가 존재하는지 확인:
    ```
    Glob("1_Project/{project값}/")
    ```

    존재하지 않으면 → 위반 기록 (자동 수정 안함, 사용자 확인)

    ### Step 8: Archive 파일 status

    `4_Archive/**` 내 파일은 `status: completed` 또는 `status: on-hold`여야 함.
    `status: active`이면 → `completed`로 **자동 수정**

    ## 자동 수정 규칙

    | 위반 유형 | 수정 방법 | 사용자 확인 |
    |----------|----------|-----------
    | para ↔ 폴더 불일치 | para를 폴더에 맞게 변경 | 불필요 |
    | Archive status: active | → completed | 불필요 |
    | summary 비어있음 | AI 요약 생성 | 필요 |
    | tags > 5개 (비인덱스) | 상위 5개 유지 제안 | 필요 |
    | Enum 값 오류 | 유사 값 제안 | 필요 |
    | project 참조 없음 | 보고만 (수정 안함) | - |

    ## 보고서 형식

    ```markdown
    # 프론트매터 검증 보고서

    ## 요약
    - 검사 파일: N개
    - 정상: N개 (N%)
    - 위반: N개 (N%)

    ## 위반 상세

    ### 자동 수정 완료
    | 파일 | 위반 | 변경 전 | 변경 후 |
    |------|------|--------|--------|

    ### 사용자 확인 필요
    | 파일 | 위반 | 현재 값 | 제안 |
    |------|------|--------|------|

    ### 참고 (수정 불필요)
    | 파일 | 항목 | 비고 |
    |------|------|------|
    ```

    ## 주의사항
    - 기존 프론트매터 값은 최대한 보존
    - created 필드는 절대 변경하지 않음
    - tags는 기존 태그에서 선택하여 축소 (임의 태그 추가 금지)
    - 프론트매터가 아예 없는 파일은 생성하지 않고 보고만
    """

    private static let indexIntegritySkillContent = """
    # 인덱스 무결성 점검 스킬

    ## 용도

    `.meta/note-index.json`이 실제 볼트 내용과 동기화되어 있는지 검증하고, 불일치를 보고합니다.
    `vault-audit-agent`의 하위 검사로 호출되거나, 단독으로 "인덱스 점검해줘"로 실행할 수 있습니다.

    ## 인덱스 파일

    | 파일 | 역할 |
    |------|------|
    | `.meta/note-index.json` | 전체 볼트 노트/폴더 메타데이터 인덱스 |

    DotBrain이 자동 생성/갱신합니다. 구조:
    - `notes`: 노트명 → {path, folder, para, tags, summary, project, status}
    - `folders`: 폴더명 → {path, para, summary, tags}
    - `version`, `updated` (ISO8601 타임스탬프)

    ## 검증 절차

    ### Step 1: 인덱스 파일 존재 확인

    ```
    Read(".meta/note-index.json")
    ```

    **누락 시**: DotBrain에서 "볼트 점검" 실행을 안내

    ### Step 2: 인덱스 ↔ 실제 파일 동기화

    1. 인덱스의 `notes` 키 목록 추출
    2. 실제 PARA 폴더 내 .md 파일 목록과 비교 (_Assets 제외)
    3. 차이 기록:
       - 인덱스에 있지만 실제 없음 → **삭제된 문서** (인덱스 재생성 필요)
       - 실제 있지만 인덱스에 없음 → **누락 문서** (인덱스 재생성 필요)

    ### Step 3: 폴더 동기화

    1. 인덱스의 `folders` 키 목록 추출
    2. 실제 PARA 하위 폴더 목록과 비교
    3. 차이 기록

    ### Step 4: 메타데이터 정확성 (샘플링)

    무작위 10개 노트에 대해:
    1. 실제 파일의 프론트매터 읽기
    2. 인덱스의 tags, summary, para, project와 비교
    3. 불일치율 기록

    ### Step 5: 타임스탬프 확인

    `updated` 필드가 24시간 이내인지 확인.
    오래된 경우 → DotBrain "볼트 점검" 실행 안내

    ## 자동 수정 규칙

    | 위반 유형 | 수정 방법 | 사용자 확인 |
    |----------|----------|-----------
    | 인덱스 파일 누락 | DotBrain "볼트 점검" 실행 안내 | 필요 |
    | 누락/잔여 노트 | DotBrain "볼트 점검" 실행 안내 | 필요 |
    | 메타데이터 불일치 | DotBrain "볼트 점검" 실행 안내 | 필요 |
    | 타임스탬프 오래됨 | DotBrain "볼트 점검" 실행 안내 | 불필요 |

    ## 보고서 형식

    ```markdown
    # 인덱스 무결성 보고서

    ## 요약
    - 인덱스 등록 노트 수: N개
    - 실제 노트 수: N개
    - 동기화율: N%
    - 메타데이터 정확도: N% (샘플 10개 기준)

    ## 불일치 상세

    ### 누락 노트 (실제 존재 → 인덱스 미등록)
    | 파일 경로 | PARA |
    |----------|------|

    ### 잔여 노트 (인덱스 등록 → 실제 삭제됨)
    | 노트명 | 인덱스 경로 |
    |--------|-----------|

    ### 메타데이터 불일치
    | 노트명 | 필드 | 인덱스 값 | 실제 값 |
    |--------|------|----------|---------|
    ```

    ## 주의사항
    - 인덱스는 DotBrain이 자동 관리하므로 직접 수정하지 않음
    - 불일치 발견 시 DotBrain "볼트 점검" 실행으로 해결
    - _Assets 폴더는 인덱스에 포함되지 않음
    """
}
