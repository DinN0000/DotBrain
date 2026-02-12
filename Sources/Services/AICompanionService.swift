import Foundation

/// Generates AI companion files for PKM vault
/// (CLAUDE.md, AGENTS.md, .cursorrules, .claude/agents/, .claude/skills/)
enum AICompanionService {

    /// Bump this when companion file content changes — triggers overwrite on existing vaults
    static let version = 2

    /// Generate all AI companion files in the PKM root (first-time only)
    static func generateAll(pkmRoot: String) throws {
        try generateClaudeMd(pkmRoot: pkmRoot)
        try generateAgentsMd(pkmRoot: pkmRoot)
        try generateCursorRules(pkmRoot: pkmRoot)
        try generateClaudeAgents(pkmRoot: pkmRoot)
        try generateClaudeSkills(pkmRoot: pkmRoot)
        try writeVersion(pkmRoot: pkmRoot)
    }

    /// Check version and regenerate if outdated — call on every app launch
    static func updateIfNeeded(pkmRoot: String) {
        let versionFile = (pkmRoot as NSString).appendingPathComponent(".dotbrain-companion-version")

        // Read current version
        let currentVersion = (try? String(contentsOfFile: versionFile, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0

        guard currentVersion < version else { return }

        // Force-regenerate all companion files
        do {
            try forceGenerateAll(pkmRoot: pkmRoot)
            try writeVersion(pkmRoot: pkmRoot)
        } catch {
            // Non-fatal — vault still works without updated companion files
        }
    }

    /// Overwrite all companion files regardless of existence
    private static func forceGenerateAll(pkmRoot: String) throws {
        let fm = FileManager.default

        // Root-level files: just overwrite
        let claudePath = (pkmRoot as NSString).appendingPathComponent("CLAUDE.md")
        try claudeMdContent.write(toFile: claudePath, atomically: true, encoding: .utf8)

        let agentsPath = (pkmRoot as NSString).appendingPathComponent("AGENTS.md")
        try agentsMdContent.write(toFile: agentsPath, atomically: true, encoding: .utf8)

        let cursorPath = (pkmRoot as NSString).appendingPathComponent(".cursorrules")
        try cursorRulesContent.write(toFile: cursorPath, atomically: true, encoding: .utf8)

        // .claude/agents/
        let agentsDir = (pkmRoot as NSString).appendingPathComponent(".claude/agents")
        try fm.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        for (name, content) in [("inbox-agent", inboxAgentContent), ("project-agent", projectAgentContent), ("search-agent", searchAgentContent)] {
            let path = (agentsDir as NSString).appendingPathComponent("\(name).md")
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        }

        // .claude/skills/
        let skillsDir = (pkmRoot as NSString).appendingPathComponent(".claude/skills/inbox-processor")
        try fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
        let skillPath = (skillsDir as NSString).appendingPathComponent("SKILL.md")
        try skillContent.write(toFile: skillPath, atomically: true, encoding: .utf8)
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
        try claudeMdContent.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static let claudeMdContent = """
    # PKM Knowledge Base — DotBrain

    이 폴더는 **DotBrain**이 관리하는 PARA 방법론 기반 개인 지식 관리(PKM) 시스템입니다.
    Obsidian과 호환되며, AI 도구(Claude Code, Cursor, OpenClaw)가 효과적으로 탐색할 수 있도록 설계되었습니다.

    ---

    ## AI 탐색 우선순위

    이 볼트를 탐색할 때 다음 순서를 따르세요:

    1. **이 파일(CLAUDE.md)** 을 먼저 읽어 구조와 규칙을 파악
    2. **프로젝트 인덱스 노트** 확인: `1_Project/프로젝트명/프로젝트명.md`
    3. **각 폴더의 인덱스 노트** 확인: `폴더명/폴더명.md` (MOC 역할)
    4. **Grep 검색**으로 태그/키워드 기반 탐색 (아래 검색 패턴 참조)
    5. **관련 노트 링크** 따라가기: 프론트매터 `project` 필드 및 `## Related Notes` 섹션

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
    │   ├── MyProject.md    ← 인덱스 노트 (MOC)
    │   ├── _Assets/        ← 프로젝트 첨부파일
    │   ├── meeting_0115.md
    │   └── design_spec.md
    ```

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
    - `project`: 목표와 기한이 있는 작업 문서 (액션 아이템, 마감 관련)
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
    - PDF, PPTX, XLSX 등의 바이너리 파일에 대한 마크다운 동반 노트에서 사용
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

    ## PARA 분류 우선순위

    새 문서를 분류할 때 다음 의사결정 트리를 따르세요:

    1. 프론트매터에 `para:`가 이미 있으면 → **그대로 유지**
    2. 미팅 노트, 발표 자료, 제안서, 마감/액션 중심 → **project**
    3. 유지/모니터링/운영/지속적 책임 → **area**
    4. 분석 자료, 가이드, 레퍼런스, 학습 자료 → **resource**
    5. 완료되었거나 장기간 미수정 → **archive**
    6. 확신이 낮으면 → 사용자에게 질문

    ⚠️ 프로젝트와 **관련된** 참고 자료는 `project`가 아니라 `resource`로 분류
    ⚠️ 운영/관리 문서는 `project`가 아니라 `area`로 분류
    ⚠️ `para`와 별개로, 관련 프로젝트가 있으면 `project` 필드에 기재

    ---

    ## 관련 노트 작성법

    관련 노트 링크는 단순 나열이 아니라 **"언제, 왜 참조해야 하는지"** 컨텍스트를 포함합니다:

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
    | "프로젝트 만들어줘" | 프로젝트 관리 | `.claude/agents/project-agent.md` |
    | "OO 관련 자료 찾아줘" | 검색 | `.claude/agents/search-agent.md` |

    각 에이전트 파일에 상세 워크플로가 정의되어 있습니다.

    ---

    ## 규칙

    - `_Inbox/`는 건드리지 마세요 (DotBrain이 자동 처리)
    - 새 노트 생성 시 프론트매터 포함 필수
    - `[[위키링크]]` 형식 사용 (Obsidian 호환)
    - 파일명에 특수문자 피하기
    - 기존 노트 수정 시 프론트매터 기존 값 유지

    ## ⚠️ 중요: 코드 파일 금지

    **이 폴더 안에서 코드를 작성하지 마세요!**

    - DotBrain이 코드 파일 (.swift, .ts, .py, .js 등)을 자동 삭제합니다
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
        try agentsMdContent.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static let agentsMdContent = """
    # AGENTS.md — DotBrain PKM Workspace

    이 PKM은 DotBrain으로 관리되는 PARA 방법론 기반 지식 베이스입니다.

    ## 폴더 구조

    - `_Inbox/`: 처리 대기 (DotBrain이 자동 분류, **수정 금지**)
    - `1_Project/`: 활성 프로젝트 (목표 + 기한)
    - `2_Area/`: 지속 관리 영역 (기한 없는 책임)
    - `3_Resource/`: 참고 자료 (관심사, 학습)
    - `4_Archive/`: 완료/비활성 항목
    - `.Templates/`: 노트 템플릿
    - `.claude/`: AI 에이전트 및 스킬 정의

    ## 에이전트 시스템

    특화된 워크플로를 위한 에이전트가 정의되어 있습니다:

    | 에이전트 | 파일 | 역할 |
    |---------|------|------|
    | 인박스 분류 | `.claude/agents/inbox-agent.md` | 파일 분류, 프론트매터 삽입, 관련 노트 연결 |
    | 프로젝트 관리 | `.claude/agents/project-agent.md` | 프로젝트 생성/완료/재활성화/이름변경 |
    | 검색 | `.claude/agents/search-agent.md` | 태그/키워드/본문 검색 |

    ## 탐색 방법

    1. **CLAUDE.md** 먼저 읽기 — 전체 구조와 규칙
    2. **인덱스 노트** 확인: `폴더명/폴더명.md` (각 폴더의 MOC)
    3. **프론트매터 검색**: `tags`, `para`, `project`, `status` 필드로 필터링
    4. **관련 노트**: `## Related Notes` 섹션의 위키링크 따라가기

    ## 프론트매터 필드 (8개)

    - `para`: project | area | resource | archive
    - `tags`: [태그 배열, 최대 5개]
    - `created`: YYYY-MM-DD
    - `status`: active | draft | completed | on-hold
    - `summary`: 2-3문장 요약
    - `source`: original | meeting | literature | import
    - `project`: 관련 프로젝트명 (폴더명과 일치)
    - `file`: 바이너리 동반 노트용 {name, format, size_kb}

    ## 수정 규칙

    - 프론트매터 기존 값 유지 (빈 필드만 채우기)
    - `[[위키링크]]` 형식 사용
    - 새 노트는 적절한 PARA 폴더에 생성
    - 관련 노트 링크에 컨텍스트 설명 포함

    ## ⚠️ 코드 작성 금지

    **이 폴더 안에서 코드 파일을 생성하지 마세요.**
    DotBrain이 코드 파일을 자동 삭제합니다.
    개발 작업은 이 PKM 폴더 밖에서 하세요.
    """

    // MARK: - .cursorrules

    private static func generateCursorRules(pkmRoot: String) throws {
        let fm = FileManager.default
        let path = (pkmRoot as NSString).appendingPathComponent(".cursorrules")
        guard !fm.fileExists(atPath: path) else { return }
        try cursorRulesContent.write(toFile: path, atomically: true, encoding: .utf8)
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
    - `.Templates/`: Note templates (Note.md, Project.md, Asset.md)
    - `.claude/agents/`: AI agent workflow definitions

    ## Navigation Priority
    1. Read `CLAUDE.md` first for full structure and rules
    2. Check index notes: `FolderName/FolderName.md` (MOC for each folder)
    3. Search by frontmatter fields using grep patterns
    4. Follow `[[wikilinks]]` in Related Notes sections

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

    ## PARA Classification Priority
    1. If frontmatter has `para:` already → keep it
    2. Action items, deadlines, deliverables → `project`
    3. Ongoing maintenance, operations → `area`
    4. Reference, guides, learning → `resource`
    5. Completed or stale → `archive`

    ## Writing Rules
    - Preserve existing frontmatter values when editing
    - Use `[[wikilinks]]` for internal links
    - Include contextual descriptions in Related Notes
    - New notes must include full frontmatter

    ## ⚠️ NO CODE FILES
    DO NOT create code files (.swift, .ts, .py, .js, etc.) in this folder!
    DotBrain automatically deletes code files during cleanup.
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
        ]

        for (name, content) in agents {
            let path = (agentsDir as NSString).appendingPathComponent("\(name).md")
            if !fm.fileExists(atPath: path) {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
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

    ## 워크플로

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
    각 폴더의 인덱스 노트(`폴더명.md`)를 읽어 태그와 키워드를 수집합니다.

    ### Step 3: 파일별 처리

    **마크다운 파일 (.md):**
    1. 내용 읽기
    2. PARA 분류 (CLAUDE.md의 분류 우선순위 참조)
    3. 프론트매터 삽입/병합 (기존 값 존중)
    4. 대상 폴더로 이동
    5. 관련 노트 링크 추가 (컨텍스트 포함)
    6. 인덱스 노트 갱신

    **바이너리 파일 (PDF, PPTX, XLSX, 이미지):**
    1. 텍스트 추출 (`.claude/skills/inbox-processor/SKILL.md` 참조)
    2. 추출된 텍스트로 PARA 분류
    3. 원본 → 대상 폴더의 `_Assets/`로 이동
    4. 동반 마크다운 노트 생성 (`file:` 메타데이터 포함)

    ### Step 4: 하위 폴더 자동 생성

    Area/Resource/Archive에서 주제별 하위 폴더가 필요하면 자동 생성합니다:
    - 폴더명: 짧고 의미 있는 1-3 단어
    - 기존 폴더와 중복 금지
    - 인덱스 노트(`폴더명/폴더명.md`) 자동 생성

    ### Step 5: 분류 확신도 검증

    - confidence >= 0.8 → 자동 처리
    - confidence >= 0.5 → 처리하되 사용자에게 보고
    - confidence < 0.5 → 사용자에게 확인 요청

    ### Step 6: 결과 요약

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
    - 인덱스 노트에 등록

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
    3. `1_Project/폴더명/_Assets/` 생성
    4. `.Templates/Project.md` 기반으로 인덱스 노트 생성
    5. 결과 보고

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

    ## 프로젝트 이름 변경

    1. 새 폴더명 생성
    2. 인덱스 노트 파일명 변경
    3. 폴더명 변경
    4. 볼트 전체에서 `[[이전이름]]` → `[[새이름]]`으로 변경
    5. 변경된 참조 수 보고

    ## 인덱스 노트 구조

    ```markdown
    ---
    para: project
    tags: []
    created: YYYY-MM-DD
    status: active
    summary: "프로젝트 설명"
    source: original
    ---

    # 프로젝트명

    ## 목적

    ## 현재 상태

    ## 포함된 노트

    ## 관련 노트
    ```
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

    // MARK: - .claude/skills/

    private static func generateClaudeSkills(pkmRoot: String) throws {
        let fm = FileManager.default
        let skillsDir = (pkmRoot as NSString).appendingPathComponent(".claude/skills/inbox-processor")
        try fm.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let path = (skillsDir as NSString).appendingPathComponent("SKILL.md")
        if !fm.fileExists(atPath: path) {
            try skillContent.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static let skillContent = """
    # 바이너리 파일 처리 스킬

    ## 용도

    인박스에 들어온 바이너리 파일(PDF, PPTX, XLSX, 이미지)에서 텍스트와 메타데이터를 추출합니다.
    DotBrain이 자동으로 처리하지만, AI 에이전트가 수동으로 처리할 때 참조합니다.

    ## 지원 형식

    | 형식 | 추출 내용 | 동반 노트 |
    |------|----------|----------|
    | PDF | 텍스트 + 메타데이터 (제목, 작성자, 페이지 수) | `파일명.pdf.md` |
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

    ## 관련 노트
    ```

    ## 파일 배치

    - 원본 바이너리 → 대상 폴더의 `_Assets/`
    - 동반 마크다운 → 대상 폴더 루트
    - 예: `3_Resource/DeFi/_Assets/report.pdf` + `3_Resource/DeFi/report.pdf.md`

    ## 텍스트 제한

    추출 텍스트는 최대 5,000자로 제한합니다.
    """
}
