import Foundation

/// 2-stage document classifier (Fast batch → Precise for uncertain)
/// Supports Claude (Haiku/Sonnet) and Gemini (Flash/Pro)
actor Classifier {
    private let aiService = AIService()
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

        for (i, batch) in batches.enumerated() {
            let progress = Double(i) / Double(batches.count) * 0.6
            onProgress?(progress, "Stage 1: 배치 \(i + 1)/\(batches.count) 분류 중...")

            let results = try await classifyBatchStage1(
                batch,
                projectContext: projectContext,
                subfolderContext: subfolderContext,
                weightedContext: weightedContext
            )
            for (key, value) in results {
                stage1Results[key] = value
            }
        }

        // Stage 2: Sonnet for uncertain files
        let uncertainFiles = files.filter { file in
            guard let s1 = stage1Results[file.fileName] else { return true }
            return s1.confidence < confidenceThreshold
        }

        var stage2Results: [String: ClassifyResult.Stage2Item] = [:]

        if !uncertainFiles.isEmpty {
            for (i, file) in uncertainFiles.enumerated() {
                let progress = 0.6 + Double(i) / Double(uncertainFiles.count) * 0.3
                onProgress?(progress, "Stage 2: \(file.fileName) 정밀 분류 중...")

                let result = try await classifySingleStage2(
                    file,
                    projectContext: projectContext,
                    subfolderContext: subfolderContext,
                    weightedContext: weightedContext
                )
                stage2Results[file.fileName] = result
            }
        }

        onProgress?(0.9, "결과 정리 중...")

        // Combine results
        return files.map { file in
            if let s2 = stage2Results[file.fileName] {
                return ClassifyResult(
                    para: s2.para,
                    tags: s2.tags,
                    summary: s2.summary,
                    targetFolder: s2.targetFolder,
                    project: s2.project.flatMap { fuzzyMatchProject($0, projectNames: projectNames) },
                    confidence: s2.confidence ?? 0.9
                )
            }

            if let s1 = stage1Results[file.fileName] {
                return ClassifyResult(
                    para: s1.para,
                    tags: s1.tags,
                    summary: "",
                    targetFolder: stripParaPrefix(s1.targetFolder ?? ""),
                    project: s1.project.flatMap { fuzzyMatchProject($0, projectNames: projectNames) },
                    confidence: s1.confidence
                )
            }

            // Fallback
            return ClassifyResult(
                para: .resource,
                tags: [],
                summary: "",
                targetFolder: "",
                confidence: 0
            )
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
        - project: 해당 프로젝트의 직접적인 작업 문서만 (액션 아이템, 체크리스트, 마감 관련 문서). 반드시 project 필드에 프로젝트명 기재.
        - area: 유지보수, 모니터링, 운영, 지속적 책임 영역의 문서
        - resource: 분석 자료, 가이드, 레퍼런스, 하우투, 학습 자료
        - archive: 완료된 작업, 오래된 내용, 더 이상 활성이 아닌 문서

        ⚠️ 프로젝트와 관련된 참고 자료는 project가 아니라 resource로, 운영/관리 문서는 area로 분류하세요.
        ⚠️ para가 project가 아니더라도, 활성 프로젝트와 관련이 있으면 project 필드에 해당 프로젝트명을 기재하세요. 관련 없으면 생략.

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
        - project: 해당 프로젝트의 직접적인 작업 문서만 (액션 아이템, 체크리스트, 마감 관련 문서). 반드시 project 필드에 프로젝트명 기재.
        - area: 유지보수, 모니터링, 운영, 지속적 책임 영역의 문서
        - resource: 분석 자료, 가이드, 레퍼런스, 하우투, 학습 자료
        - archive: 완료된 작업, 오래된 내용, 더 이상 활성이 아닌 문서

        ⚠️ 프로젝트와 관련된 참고 자료는 project가 아니라 resource로, 운영/관리 문서는 area로 분류하세요.
        ⚠️ para가 project가 아니더라도, 활성 프로젝트와 관련이 있으면 project 필드에 해당 프로젝트명을 기재하세요. 관련 없으면 생략.

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

    /// Remove PARA prefix from folder path (e.g., "3_Resource/DevOps" → "DevOps")
    private func stripParaPrefix(_ folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        let pattern = #"^[1-4]_(?:Project|Area|Resource|Archive)/?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return trimmed
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
    }

    /// Fuzzy match AI-returned project name against actual folder names
    private func fuzzyMatchProject(_ aiName: String, projectNames: [String]) -> String {
        guard !projectNames.isEmpty else { return aiName }
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

        return aiName
    }
}
