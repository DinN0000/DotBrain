import Foundation

/// 2-stage document classifier (Fast batch → Precise for uncertain)
/// Supports Claude (Haiku/Sonnet) and Gemini (Flash/Pro)
actor Classifier {
    private let aiService = AIService.shared
    private let batchSize = 10
    private let confidenceThreshold = 0.8
    private let previewLength = 200

    // MARK: - Main Classification

    /// Classify files using 2-stage approach
    func classifyFiles(
        _ files: [ClassifyInput],
        projectContext: String,
        subfolderContext: String,
        projectNames: [String],
        weightedContext: String = "",
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> [ClassifyResult] {
        guard !files.isEmpty else { return [] }

        // Stage 1: Haiku batch classification
        var stage1Results: [String: ClassifyResult.Stage1Item] = [:]
        let batches = stride(from: 0, to: files.count, by: batchSize).map {
            Array(files[$0..<min($0 + batchSize, files.count)])
        }

        // Stage 1: Process batches concurrently (max 3 concurrent API calls)
        let maxConcurrentBatches = 3

        let totalBatches = batches.count
        stage1Results = try await withThrowingTaskGroup(
            of: [String: ClassifyResult.Stage1Item].self,
            returning: [String: ClassifyResult.Stage1Item].self
        ) { group in
            var activeTasks = 0
            var batchIndex = 0
            var completedBatches = 0
            var combined: [String: ClassifyResult.Stage1Item] = [:]

            for batch in batches {
                if activeTasks >= maxConcurrentBatches {
                    if let results = try await group.next() {
                        for (key, value) in results {
                            combined[key] = value
                        }
                        activeTasks -= 1
                        completedBatches += 1
                        onProgress?(Double(completedBatches) / Double(totalBatches) * 0.6, "Stage 1: 배치 \(completedBatches)/\(totalBatches) 완료")
                    }
                }

                let idx = batchIndex
                group.addTask {
                    return try await self.classifyBatchStage1(
                        batch,
                        projectContext: projectContext,
                        subfolderContext: subfolderContext,
                        weightedContext: weightedContext
                    )
                }
                activeTasks += 1
                batchIndex += 1
                onProgress?(Double(completedBatches) / Double(totalBatches) * 0.6, "배치 \(idx + 1)/\(totalBatches) 분류 중...")
            }

            for try await results in group {
                for (key, value) in results {
                    combined[key] = value
                }
                completedBatches += 1
                onProgress?(Double(completedBatches) / Double(totalBatches) * 0.6, "Stage 1: 배치 \(completedBatches)/\(totalBatches) 완료")
            }
            return combined
        }

        // Stage 2: Sonnet for uncertain files
        let uncertainFiles = files.filter { file in
            guard let s1 = stage1Results[file.fileName] else { return true }
            return s1.confidence < confidenceThreshold
        }

        var stage2Results: [String: ClassifyResult.Stage2Item] = [:]

        if !uncertainFiles.isEmpty {
            // Stage 2: Process uncertain files concurrently (max 5)
            let maxConcurrentStage2 = 5

            stage2Results = try await withThrowingTaskGroup(
                of: (String, ClassifyResult.Stage2Item).self,
                returning: [String: ClassifyResult.Stage2Item].self
            ) { group in
                var activeTasks = 0
                var combined: [String: ClassifyResult.Stage2Item] = [:]

                for file in uncertainFiles {
                    if activeTasks >= maxConcurrentStage2 {
                        if let (fileName, result) = try await group.next() {
                            combined[fileName] = result
                            activeTasks -= 1
                        }
                    }

                    group.addTask {
                        let result = try await self.classifySingleStage2(
                            file,
                            projectContext: projectContext,
                            subfolderContext: subfolderContext,
                            weightedContext: weightedContext
                        )
                        return (file.fileName, result)
                    }
                    activeTasks += 1
                }

                for try await (fileName, result) in group {
                    combined[fileName] = result
                }
                return combined
            }
        }

        onProgress?(0.9, "결과 정리 중...")

        // Combine results with project validation
        return files.map { file in
            var result: ClassifyResult
            let s2 = stage2Results[file.fileName]
            let s1 = stage1Results[file.fileName]

            // Capture raw project name before fuzzy matching
            let rawProject = s2?.project ?? s1?.project

            if let s2 = s2 {
                result = ClassifyResult(
                    para: s2.para,
                    tags: s2.tags,
                    summary: s2.summary,
                    targetFolder: s2.targetFolder,
                    project: rawProject.flatMap { fuzzyMatchProject($0, projectNames: projectNames) },
                    confidence: s2.confidence ?? 0.9
                )
            } else if let s1 = s1 {
                result = ClassifyResult(
                    para: s1.para,
                    tags: s1.tags,
                    summary: "",
                    targetFolder: stripParaPrefix(s1.targetFolder ?? ""),
                    project: rawProject.flatMap { fuzzyMatchProject($0, projectNames: projectNames) },
                    confidence: s1.confidence
                )
            } else {
                // Fallback
                result = ClassifyResult(
                    para: .resource,
                    tags: [],
                    summary: "",
                    targetFolder: "",
                    confidence: 0
                )
            }

            // para가 project인데 매칭 프로젝트 없으면 → suggestedProject에 원래 이름 보존
            // InboxProcessor가 PendingConfirmation을 생성하도록 para: .project 유지
            if result.para == .project && result.project == nil {
                result.suggestedProject = rawProject
            }

            return result
        }
    }

    // MARK: - Stage 1: Haiku Batch

    private func classifyBatchStage1(
        _ files: [ClassifyInput],
        projectContext: String,
        subfolderContext: String,
        weightedContext: String
    ) async throws -> [String: ClassifyResult.Stage1Item] {
        let previews = files.map { file in
            (fileName: file.fileName, preview: String(file.content.prefix(previewLength)))
        }

        let prompt = buildStage1Prompt(previews, projectContext: projectContext, subfolderContext: subfolderContext, weightedContext: weightedContext)

        let response = try await aiService.sendFast(maxTokens: 4096, message: prompt)

        var results: [String: ClassifyResult.Stage1Item] = [:]
        if let items = parseJSONSafe([Stage1RawItem].self, from: response) {
            for item in items {
                guard let para = PARACategory(rawValue: item.para), !item.fileName.isEmpty else { continue }
                results[item.fileName] = ClassifyResult.Stage1Item(
                    fileName: item.fileName,
                    para: para,
                    tags: Array((item.tags ?? []).prefix(5)),
                    confidence: max(0, min(1, item.confidence ?? 0)),
                    project: item.project,
                    targetFolder: item.targetFolder.map { stripParaPrefix($0) }
                )
            }
        }

        // Fill missing with default
        for file in files where results[file.fileName] == nil {
            results[file.fileName] = ClassifyResult.Stage1Item(
                fileName: file.fileName,
                para: .resource,
                tags: [],
                confidence: 0,
                project: nil,
                targetFolder: nil
            )
        }

        return results
    }

    // MARK: - Stage 2: Sonnet Precise

    private func classifySingleStage2(
        _ file: ClassifyInput,
        projectContext: String,
        subfolderContext: String,
        weightedContext: String
    ) async throws -> ClassifyResult.Stage2Item {
        let prompt = buildStage2Prompt(
            fileName: file.fileName,
            content: file.content,
            projectContext: projectContext,
            subfolderContext: subfolderContext,
            weightedContext: weightedContext
        )

        let response = try await aiService.sendPrecise(maxTokens: 2048, message: prompt)

        if let item = parseJSONSafe(Stage2RawItem.self, from: response),
           let para = PARACategory(rawValue: item.para) {
            return ClassifyResult.Stage2Item(
                para: para,
                tags: Array((item.tags ?? []).prefix(5)),
                summary: item.summary ?? "",
                targetFolder: stripParaPrefix(item.targetFolder ?? item.targetPath ?? ""),
                project: item.project,
                confidence: item.confidence.map { max(0, min(1, $0)) }
            )
        }

        // Fallback
        return ClassifyResult.Stage2Item(
            para: .resource,
            tags: [],
            summary: "",
            targetFolder: "",
            project: nil
        )
    }

    // MARK: - Prompt Builders (Korean)

    private func buildStage1Prompt(
        _ files: [(fileName: String, preview: String)],
        projectContext: String,
        subfolderContext: String,
        weightedContext: String
    ) -> String {
        let fileList = files.enumerated().map { (i, f) in
            "[\(i)] 파일명: \(f.fileName)\n미리보기: \(f.preview)"
        }.joined(separator: "\n\n")

        let weightedSection = weightedContext.isEmpty ? "" : """

        ## 기존 문서 맥락 (가중치 기반)
        아래 기존 문서 정보를 참고하여, 새 문서가 기존 문서와 태그나 주제가 겹치면 같은 카테고리/폴더로 분류하세요.
        🔴 Project 문서와 겹치면 → 해당 프로젝트 연결 가중치 높음
        🟡 Area/Resource 문서와 겹치면 → 해당 폴더 연결 가중치 중간
        ⚪ Archive는 참고만 (낮은 가중치)

        \(weightedContext)

        """

        return """
        당신은 PARA 방법론 기반 문서 분류 전문가입니다.

        ## 활성 프로젝트 목록
        \(projectContext)

        ## 기존 하위 폴더
        \(subfolderContext)
        \(weightedSection)
        ## 분류 규칙
        - project: 활성 프로젝트 목록에 있는 프로젝트의 직접적인 작업 문서만 (액션 아이템, 체크리스트, 마감 관련 문서). 반드시 project 필드에 위 목록의 정확한 프로젝트명을 기재.
        - area: 유지보수, 모니터링, 운영, 지속적 책임 영역의 문서
        - resource: 분석 자료, 가이드, 레퍼런스, 하우투, 학습 자료
        - archive: 완료된 작업, 오래된 내용, 더 이상 활성이 아닌 문서

        ⚠️ 프로젝트와 관련된 참고 자료는 project가 아니라 resource로, 운영/관리 문서는 area로 분류하세요.
        ⚠️ 포트폴리오, 이력서, 프로젝트 소개/설명/개요 문서는 resource입니다 (직접 작업 문서가 아님).
        ⚠️ 프로젝트에 대한 분석/리뷰/회고는 resource 또는 archive입니다.
        ⚠️ para가 project가 아니더라도, 활성 프로젝트와 관련이 있으면 project 필드에 해당 프로젝트명을 기재하세요. 관련 없으면 생략.
        ⚠️ 활성 프로젝트 목록에 없지만 명확히 프로젝트 작업(회의록, 체크리스트, 마감일, 진행 상태)인 문서는 para: "project", project: "제안할_프로젝트명"으로 분류하세요. 시스템이 사용자에게 확인합니다.

        ## 분류할 파일 목록
        \(fileList)

        ## 응답 형식
        반드시 아래 JSON 배열만 출력하세요. 설명이나 마크다운 코드블록 없이 순수 JSON만 반환합니다.
        [
          {
            "fileName": "파일명",
            "para": "project" | "area" | "resource" | "archive",
            "tags": ["태그1", "태그2"],
            "confidence": 0.0~1.0,
            "project": "관련 프로젝트명 (관련 있을 때만, 없으면 생략)",
            "targetFolder": "하위 폴더명 (예: DevOps, 회의록). PARA 접두사 포함하지 말 것"
          }
        ]

        각 파일에 대해 정확히 하나의 객체를 반환하세요. tags는 최대 5개, 한국어 또는 영어 혼용 가능합니다.
        confidence는 분류 확신도입니다 (0.0=모름, 1.0=확실).
        ⚠️ 같은 주제의 기존 폴더가 있으면 반드시 그 폴더명을 그대로 사용하세요.
        """
    }

    private func buildStage2Prompt(
        fileName: String,
        content: String,
        projectContext: String,
        subfolderContext: String,
        weightedContext: String
    ) -> String {
        let weightedSection = weightedContext.isEmpty ? "" : """

        ## 기존 문서 맥락 (가중치 기반)
        아래 기존 문서 정보를 참고하여, 이 문서가 기존 문서와 태그나 주제가 겹치면 같은 카테고리/폴더로 분류하세요.
        🔴 Project 문서와 겹치면 → 해당 프로젝트 연결 가중치 높음
        🟡 Area/Resource 문서와 겹치면 → 해당 폴더 연결 가중치 중간
        ⚪ Archive는 참고만 (낮은 가중치)

        \(weightedContext)

        """

        return """
        당신은 PARA 방법론 기반 문서 분류 전문가입니다. 이 문서를 정밀하게 분석해주세요.

        ## 활성 프로젝트 목록
        \(projectContext)

        ## 기존 하위 폴더
        \(subfolderContext)
        \(weightedSection)
        ## 분류 규칙
        - project: 활성 프로젝트 목록에 있는 프로젝트의 직접적인 작업 문서만 (액션 아이템, 체크리스트, 마감 관련 문서). 반드시 project 필드에 위 목록의 정확한 프로젝트명을 기재.
        - area: 유지보수, 모니터링, 운영, 지속적 책임 영역의 문서
        - resource: 분석 자료, 가이드, 레퍼런스, 하우투, 학습 자료
        - archive: 완료된 작업, 오래된 내용, 더 이상 활성이 아닌 문서

        ⚠️ 프로젝트와 관련된 참고 자료는 project가 아니라 resource로, 운영/관리 문서는 area로 분류하세요.
        ⚠️ 포트폴리오, 이력서, 프로젝트 소개/설명/개요 문서는 resource입니다 (직접 작업 문서가 아님).
        ⚠️ 프로젝트에 대한 분석/리뷰/회고는 resource 또는 archive입니다.
        ⚠️ para가 project가 아니더라도, 활성 프로젝트와 관련이 있으면 project 필드에 해당 프로젝트명을 기재하세요. 관련 없으면 생략.
        ⚠️ 활성 프로젝트 목록에 없지만 명확히 프로젝트 작업(회의록, 체크리스트, 마감일, 진행 상태)인 문서는 para: "project", project: "제안할_프로젝트명"으로 분류하세요. 시스템이 사용자에게 확인합니다.

        ## 대상 파일
        파일명: \(fileName)

        ## 전체 내용
        \(content)

        ## 응답 형식
        반드시 아래 JSON 객체만 출력하세요. 설명이나 마크다운 코드블록 없이 순수 JSON만 반환합니다.
        {
          "para": "project" | "area" | "resource" | "archive",
          "tags": ["태그1", "태그2"],
          "summary": "문서 내용을 2~3문장으로 요약",
          "confidence": 0.0~1.0,
          "targetFolder": "하위 폴더명. PARA 접두사 포함하지 말 것",
          "project": "관련 프로젝트명 (관련 있을 때만, 없으면 생략)"
        }

        tags는 최대 5개, summary는 한국어로 작성하세요.
        confidence는 분류 확신도입니다 (0.0=모름, 1.0=확실).
        ⚠️ 같은 주제의 기존 폴더가 있으면 반드시 그 폴더명을 그대로 사용하세요.
        """
    }

    // MARK: - JSON Parsing

    /// Raw JSON types for decoding (using String for para to allow validation)
    private struct Stage1RawItem: Decodable {
        let fileName: String
        let para: String
        var tags: [String]?
        var confidence: Double?
        var project: String?
        var targetFolder: String?
    }

    private struct Stage2RawItem: Decodable {
        let para: String
        var tags: [String]?
        var summary: String?
        var targetFolder: String?
        var targetPath: String?  // legacy field
        var project: String?
        var confidence: Double?
    }

    /// Safely parse JSON from LLM response (handles markdown code blocks)
    private func parseJSONSafe<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        let cleaned = text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct parse
        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                // Will try extraction below
            }
        }

        // Extract JSON from first [ or { to last ] or }
        if let startBracket = cleaned.firstIndex(where: { $0 == "[" || $0 == "{" }),
           let endBracket = cleaned.lastIndex(where: { $0 == "]" || $0 == "}" }) {
            let jsonStr = String(cleaned[startBracket...endBracket])
            if let data = jsonStr.data(using: .utf8) {
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    print("[Classifier] JSON 파싱 실패: \(error.localizedDescription)")
                    print("[Classifier] 원본 응답 (처음 200자): \(String(cleaned.prefix(200)))")
                }
            }
        }

        print("[Classifier] JSON 추출 실패 — 응답에서 JSON을 찾을 수 없습니다")
        return nil
    }

    // MARK: - Utilities

    /// Remove PARA prefix from folder path (e.g., "3_Resource/DevOps" → "DevOps", "Area/DevOps" → "DevOps")
    private func stripParaPrefix(_ folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // Phase 1: "2_Area/DevOps" → "DevOps" (숫자 접두사 포함된 경우)
        let numericPrefixPattern = #"^[1-4][\s_\-]?(?:Project|Area|Resource|Archive)/?"#
        var result = trimmed
        if let regex = try? NSRegularExpression(pattern: numericPrefixPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Phase 2: "Area/DevOps" → "DevOps" (bare 카테고리명이 경로 앞에 올 때)
        let barePrefixPattern = #"^(?:Project|Area|Resource|Archive|_?Inbox)/"#
        if let regex = try? NSRegularExpression(pattern: barePrefixPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Phase 3: 전체가 bare 카테고리명이면 빈 문자열
        let bareNames: Set<String> = [
            "project", "area", "resource", "archive",
            "inbox", "_inbox", "projects", "areas", "resources", "archives"
        ]
        if bareNames.contains(result.lowercased().trimmingCharacters(in: .whitespaces)) {
            return ""
        }

        return result
    }

    /// Fuzzy match AI-returned project name against actual folder names.
    /// Returns nil if no match found — prevents creating arbitrary new project folders.
    private func fuzzyMatchProject(_ aiName: String, projectNames: [String]) -> String? {
        guard !projectNames.isEmpty else { return nil }
        if projectNames.contains(aiName) { return aiName }

        let normalize = { (s: String) -> String in
            s.lowercased().replacingOccurrences(of: #"[\s\-]+"#, with: "_", options: .regularExpression)
        }

        let normalizedAI = normalize(aiName)

        // Exact normalized match
        for name in projectNames {
            if normalize(name) == normalizedAI { return name }
        }

        // Substring match
        for name in projectNames {
            let normName = normalize(name)
            if normName.contains(normalizedAI) || normalizedAI.contains(normName) {
                return name
            }
        }

        // No match → do not create new project
        return nil
    }
}
