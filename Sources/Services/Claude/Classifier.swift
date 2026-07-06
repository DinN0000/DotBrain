import Foundation

/// 2-stage document classifier (Fast batch → Precise for uncertain)
/// Supports Claude (Haiku/Sonnet) and Gemini (Flash/Pro)
actor Classifier {
    private let aiService = AIService.shared
    private let maxBatchSize = 25
    private let confidenceThreshold = 0.6
    private let estimatedTokensPerFile = 200
    private let maxOutputTokens = 8192

    private struct ProviderTuning {
        let stage1PreviewLength: Int
        let stage1CharBudget: Int
        let stage1MaxFilesPerBatch: Int
        let stage1Concurrency: Int
        let stage2Concurrency: Int
        let stage2ContentLimit: Int?
    }

    private enum Stage1BatchError: LocalizedError {
        case emptyResponse
        case partialResponse(expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Stage 1 returned no valid items"
            case .partialResponse(let expected, let actual):
                return "Stage 1 returned \(actual)/\(expected) valid items"
            }
        }
    }

    private static let numericPrefixRegex = try? NSRegularExpression(
        pattern: #"^[1-4][\s_\-]?(?:Project|Area|Resource|Archive)/?"#,
        options: .caseInsensitive
    )
    private static let barePrefixRegex = try? NSRegularExpression(
        pattern: #"^(?:Project|Area|Resource|Archive|_?Inbox)/"#,
        options: .caseInsensitive
    )

    // MARK: - Main Classification

    /// Classify files using 2-stage approach
    func classifyFiles(
        _ files: [ClassifyInput],
        projectContext: String,
        subfolderContext: String,
        projectNames: [String],
        weightedContext: String = "",
        areaContext: String = "",
        tagVocabulary: String = "[]",
        correctionContext: String = "",
        pkmRoot: String = "",
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> [ClassifyResult] {
        guard !files.isEmpty else { return [] }
        let provider = currentProvider()
        let tuning = tuning(for: provider)

        // Build system prompt once for prompt caching (shared across Stage 1 and Stage 2)
        let systemPrompt = buildSystemPrompt(
            projectContext: projectContext,
            subfolderContext: subfolderContext,
            weightedContext: weightedContext,
            areaContext: areaContext,
            tagVocabulary: tagVocabulary,
            correctionContext: correctionContext
        )

        // Stage 1: Haiku batch classification (dynamic batch size based on file count)
        var stage1Results: [String: ClassifyResult.Stage1Item] = [:]
        let batches = makeStage1Batches(files, tuning: tuning)

        // Stage 1: Process batches concurrently (max 3 concurrent API calls)
        // Uses non-throwing TaskGroup — individual batch failures are caught and skipped
        // so a single 429 doesn't kill the entire scan
        let maxConcurrentBatches = tuning.stage1Concurrency

        let totalBatches = batches.count
        onProgress?(0.0, L10n.VaultInspector.stage1Preparing(files.count, totalBatches))
        stage1Results = await withTaskGroup(
            of: [String: ClassifyResult.Stage1Item].self,
            returning: [String: ClassifyResult.Stage1Item].self
        ) { group in
            var activeTasks = 0
            var batchIndex = 0
            var completedBatches = 0
            var combined: [String: ClassifyResult.Stage1Item] = [:]

            for batch in batches {
                if activeTasks >= maxConcurrentBatches {
                    if let results = await group.next() {
                        for (key, value) in results {
                            combined[key] = value
                        }
                        activeTasks -= 1
                        completedBatches += 1
                        onProgress?(Double(completedBatches) / Double(totalBatches) * 0.6, "Stage 1: 배치 \(completedBatches)/\(totalBatches) 완료")
                    }
                }

                let idx = batchIndex
                let batchFiles = batch
                group.addTask {
                    await self.classifyBatchStage1Recovering(
                        batchFiles,
                        systemPrompt: systemPrompt,
                        batchIndex: idx,
                        totalBatches: totalBatches,
                        onProgress: onProgress
                    )
                }
                activeTasks += 1
                batchIndex += 1
                onProgress?(
                    Double(completedBatches) / Double(totalBatches) * 0.6,
                    L10n.VaultInspector.stage1InProgress(idx + 1, totalBatches, batchFiles.count)
                )
            }

            for await results in group {
                for (key, value) in results {
                    combined[key] = value
                }
                completedBatches += 1
                onProgress?(
                    Double(completedBatches) / Double(totalBatches) * 0.6,
                    L10n.VaultInspector.stage1Completed(completedBatches, totalBatches)
                )
            }
            return combined
        }

        // Stage 2: Sonnet for uncertain files
        // All stage result maps are keyed by filePath — fileName collides when
        // different folders contain same-named files (회의록.md, README.md)
        let uncertainFiles = files.filter { file in
            guard let s1 = stage1Results[file.filePath] else { return true }
            return s1.confidence < confidenceThreshold
        }

        var stage2Results: [String: ClassifyResult.Stage2Item] = [:]

        if !uncertainFiles.isEmpty {
            onProgress?(0.6, L10n.VaultInspector.stage2Preparing(uncertainFiles.count))

            // Stage 2: Process uncertain files concurrently (max 3)
            // Uses non-throwing TaskGroup — individual file failures fall back to Stage 1 result
            let maxConcurrentStage2 = tuning.stage2Concurrency

            stage2Results = await withTaskGroup(
                of: (String, ClassifyResult.Stage2Item?).self,
                returning: [String: ClassifyResult.Stage2Item].self
            ) { group in
                var activeTasks = 0
                var completedStage2 = 0
                var combined: [String: ClassifyResult.Stage2Item] = [:]

                func reportStage2Progress() {
                    let total = max(uncertainFiles.count, 1)
                    let progress = 0.6 + (Double(completedStage2) / Double(total) * 0.3)
                    onProgress?(progress, L10n.VaultInspector.stage2InProgress(completedStage2, uncertainFiles.count))
                }

                for file in uncertainFiles {
                    if activeTasks >= maxConcurrentStage2 {
                        if let (filePath, result) = await group.next() {
                            if let result { combined[filePath] = result }
                            activeTasks -= 1
                            completedStage2 += 1
                            reportStage2Progress()
                        }
                    }

                    let key = file.filePath
                    let fileName = file.fileName
                    group.addTask {
                        do {
                            let result = try await self.classifySingleStage2(
                                file,
                                systemPrompt: systemPrompt,
                                contentLimit: tuning.stage2ContentLimit
                            )
                            return (key, result)
                        } catch {
                            NSLog("[Classifier] Stage2 %@ 실패 (Stage1 결과 사용): %@", fileName, error.localizedDescription)
                            return (key, nil)
                        }
                    }
                    activeTasks += 1
                }

                for await (filePath, result) in group {
                    if let result { combined[filePath] = result }
                    completedStage2 += 1
                    reportStage2Progress()
                }
                return combined
            }
        } else {
            onProgress?(0.75, L10n.VaultInspector.stage2Skipped)
        }

        onProgress?(0.9, L10n.VaultInspector.finalizingResults)

        // Combine results with project validation
        return files.map { file in
            var result: ClassifyResult
            let s2 = stage2Results[file.filePath]
            let s1 = stage1Results[file.filePath]

            // Capture raw project name before fuzzy matching
            let rawProject = s2?.project ?? s1?.project

            if let s2 = s2 {
                result = ClassifyResult(
                    para: s2.para,
                    tags: s2.tags,
                    summary: s2.summary,
                    targetFolder: s2.targetFolder,
                    project: rawProject.flatMap { fuzzyMatchProject($0, projectNames: projectNames, pkmRoot: pkmRoot) },
                    confidence: s2.confidence ?? 0.0
                )
            } else if let s1 = s1 {
                result = ClassifyResult(
                    para: s1.para,
                    tags: s1.tags,
                    summary: s1.summary,
                    targetFolder: stripNewPrefix(stripParaPrefix(s1.targetFolder ?? "")),
                    project: rawProject.flatMap { fuzzyMatchProject($0, projectNames: projectNames, pkmRoot: pkmRoot) },
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

            // Remove project names from tags (AI hallucination prevention)
            let projectNameSet = Set(projectNames.map { $0.lowercased() })
            result.tags = result.tags.filter { !projectNameSet.contains($0.lowercased()) }

            return result
        }
    }

    // MARK: - Stage 1: Haiku Batch

    private func classifyBatchStage1Recovering(
        _ files: [ClassifyInput],
        systemPrompt: String,
        batchIndex: Int,
        totalBatches: Int,
        onProgress: ((Double, String) -> Void)?,
        splitDepth: Int = 0
    ) async -> [String: ClassifyResult.Stage1Item] {
        do {
            return try await classifyBatchStage1(files, systemPrompt: systemPrompt)
        } catch {
            NSLog(
                "[Classifier] Stage1 배치 %d 실패 (depth=%d, files=%d): %@",
                batchIndex,
                splitDepth,
                files.count,
                error.localizedDescription
            )

            guard files.count > 1 else {
                let file = files[0]
                NSLog("[Classifier] Stage1 단일 파일 폴백 사용: %@", file.fileName)
                return [file.filePath: fallbackStage1Item(for: file)]
            }

            let midpoint = files.count / 2
            let left = Array(files[..<midpoint])
            let right = Array(files[midpoint...])
            let baseProgress = Double(batchIndex) / Double(max(totalBatches, 1)) * 0.6

            onProgress?(
                baseProgress,
                splitDepth == 0
                    ? L10n.VaultInspector.stage1RetrySplit(batchIndex + 1, totalBatches, files.count, left.count, right.count)
                    : L10n.VaultInspector.stage1RetrySplitCompact(files.count, left.count, right.count)
            )

            let leftResults = await classifyBatchStage1Recovering(
                left,
                systemPrompt: systemPrompt,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                onProgress: onProgress,
                splitDepth: splitDepth + 1
            )
            let rightResults = await classifyBatchStage1Recovering(
                right,
                systemPrompt: systemPrompt,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                onProgress: onProgress,
                splitDepth: splitDepth + 1
            )
            return leftResults.merging(rightResults) { _, new in new }
        }
    }

    private func fallbackStage1Item(for file: ClassifyInput) -> ClassifyResult.Stage1Item {
        ClassifyResult.Stage1Item(
            fileName: file.fileName,
            para: .resource,
            tags: [],
            summary: "",
            confidence: 0,
            project: nil,
            targetFolder: nil
        )
    }

    private func classifyBatchStage1(
        _ files: [ClassifyInput],
        systemPrompt: String
    ) async throws -> [String: ClassifyResult.Stage1Item] {
        let provider = currentProvider()
        let previewLimit = tuning(for: provider).stage1PreviewLength

        // Use condensed preview (2000 chars) instead of full content (5000 chars) for Stage 1 triage
        let fileContents = files.map { file in
            (fileName: file.fileName, content: String(file.preview.prefix(previewLimit)))
        }

        let userMessage = buildStage1UserMessage(fileContents)

        let dynamicMaxTokens = min(maxOutputTokens, max(4096, files.count * estimatedTokensPerFile))
        let response = try await aiService.sendFastWithUsage(maxTokens: dynamicMaxTokens, message: userMessage, systemMessage: systemPrompt)
        if let usage = response.usage {
            let model = await aiService.fastModel
            StatisticsService.logTokenUsage(operation: "classify-stage1", model: model, usage: usage, isEstimated: response.isEstimated)
        }

        var results: [String: ClassifyResult.Stage1Item] = [:]
        guard let items = parseJSONSafe([Stage1RawItem].self, from: response.text) else {
            NSLog("[Classifier] Stage1 JSON parse failed — response: %@", String(response.text.prefix(200)))
            throw Stage1BatchError.emptyResponse
        }

        if items.isEmpty {
            NSLog("[Classifier] Stage1 JSON parsed but empty array — response: %@", String(response.text.prefix(200)))
            throw Stage1BatchError.emptyResponse
        }

        // Map response items back to inputs via the [i] index; fileName is
        // only a fallback and only when unique within the batch
        var uniqueNameToPath: [String: String] = [:]
        var duplicateNames: Set<String> = []
        for file in files {
            if uniqueNameToPath[file.fileName] != nil {
                duplicateNames.insert(file.fileName)
            } else {
                uniqueNameToPath[file.fileName] = file.filePath
            }
        }
        for name in duplicateNames { uniqueNameToPath[name] = nil }

        for item in items {
            guard let para = PARACategory(rawValue: item.para) else { continue }
            let filePath: String
            if let id = item.id, files.indices.contains(id) {
                filePath = files[id].filePath
            } else if !item.fileName.isEmpty, let path = uniqueNameToPath[item.fileName] {
                filePath = path
            } else {
                continue
            }
            results[filePath] = ClassifyResult.Stage1Item(
                fileName: item.fileName,
                para: para,
                tags: Array((item.tags ?? []).prefix(5)),
                summary: item.summary ?? "",
                confidence: max(0, min(1, item.confidence ?? 0)),
                project: item.project,
                targetFolder: item.targetFolder.map { stripNewPrefix(stripParaPrefix($0)) }
            )
        }

        if results.count != files.count {
            throw Stage1BatchError.partialResponse(expected: files.count, actual: results.count)
        }

        return results
    }

    // MARK: - Stage 2: Sonnet Precise

    private func classifySingleStage2(
        _ file: ClassifyInput,
        systemPrompt: String,
        contentLimit: Int? = nil
    ) async throws -> ClassifyResult.Stage2Item {
        let userMessage = buildStage2UserMessage(
            fileName: file.fileName,
            content: contentLimit.map { String(file.content.prefix($0)) } ?? file.content
        )

        let response = try await aiService.sendPreciseWithUsage(maxTokens: 2048, message: userMessage, systemMessage: systemPrompt)
        if let usage = response.usage {
            let model = await aiService.preciseModel
            StatisticsService.logTokenUsage(operation: "classify-stage2", model: model, usage: usage, isEstimated: response.isEstimated)
        }

        if let item = parseJSONSafe(Stage2RawItem.self, from: response.text),
           let para = PARACategory(rawValue: item.para) {
            return ClassifyResult.Stage2Item(
                para: para,
                tags: Array((item.tags ?? []).prefix(5)),
                summary: item.summary ?? "",
                targetFolder: stripNewPrefix(stripParaPrefix(item.targetFolder ?? item.targetPath ?? "")),
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

    /// Build the static system prompt shared across Stage 1 and Stage 2.
    /// Contains role instruction, vault context, classification rules.
    /// Called once per classify batch for prompt caching.
    private func buildSystemPrompt(
        projectContext: String,
        subfolderContext: String,
        weightedContext: String,
        areaContext: String,
        tagVocabulary: String,
        correctionContext: String
    ) -> String {

        let weightedSection = weightedContext.isEmpty ? "" : """

        ## 기존 문서 맥락 (가중치 기반)
        아래 기존 문서 정보를 참고하여, 새 문서가 기존 문서와 태그나 주제가 겹치면 같은 카테고리/폴더로 분류하세요.
        (높음) Project 문서와 겹치면 → 해당 프로젝트 연결 가중치 높음
        (중간) Area/Resource 문서와 겹치면 → 해당 폴더 연결 가중치 중간
        (낮음) Archive는 참고만 (낮은 가중치)

        \(weightedContext)

        """

        let tagSection = tagVocabulary == "[]" ? "" : """

        ## 기존 태그 참고
        볼트에서 사용 중인 태그입니다. 동일한 개념이면 아래 표기를 그대로 따르세요.
        새로운 개념의 태그는 자유롭게 생성해도 됩니다.
        \(tagVocabulary)

        """

        let areaSection = areaContext.isEmpty ? "" : """

        ## Area(도메인) 목록
        아래 등록된 도메인과 소속 프로젝트를 참고하세요. Area는 지속적으로 책임지고 관리·갱신하는 영역이며, 여러 프로젝트를 묶는 상위 영역이기도 합니다.
        \(areaContext)

        """

        return """
        당신은 PARA 방법론 기반 문서 분류 전문가입니다.

        ## 활성 프로젝트 목록
        \(projectContext)
        \(areaSection)
        ## 기존 하위 폴더 (이 목록의 정확한 이름만 사용)
        \(subfolderContext)
        각 폴더의 name, tags, summary, noteCount를 참고하여 가장 적합한 폴더를 선택하세요.
        새 폴더가 필요하면 targetFolder에 "NEW:폴더명"을 사용하세요. 기존 폴더와 비슷한 이름이 있으면 반드시 기존 이름을 사용하세요.
        \(weightedSection)\(tagSection)\(correctionContext.isEmpty ? "" : "\n\(correctionContext)\n")
        ## 분류 규칙

        | para | 조건 | 예시 | project 필드 |
        |------|------|------|-------------|
        | project | 활성 프로젝트의 직접 작업 문서 (마감 있는 작업, 체크리스트, 회의록) | 스프린트 백로그, 회의록, TODO | 필수: 정확한 프로젝트명 |
        | area | 지속적으로 책임지고 관리·갱신하는 영역의 운영/정책/상태 문서. 특정 프로젝트에 속하지 않고, 프로젝트가 끝나도 계속 유지·갱신됨 (단발 참고자료 아님) | 운영 기준, 인프라·보안 정책, 장기 상태 문서 | 관련시만 |
        | resource | 참고/학습/분석 자료 | 기술 가이드, API 레퍼런스, 분석 보고서 | 관련시만 |
        | archive | 완료/비활성/오래된 문서 | 종료된 작업, 과거 회고록 | 관련시만 |

        Area vs Resource 판별: 계속 책임지고 갱신해야 하면 area, 한 번 참고하고 마는 자료면 resource. Area는 도메인(상위 영역)으로서 여러 Project를 묶을 수도 있음.

        ## 주의사항

        | 문서 유형 | 올바른 분류 | 흔한 오분류 |
        |-----------|-----------|-----------|
        | 프로젝트 참고자료/분석 | resource | project |
        | 프로젝트 소개/개요/제안서 | resource | project |
        | 프로젝트 회고/리뷰 | resource 또는 archive | project |
        | 도메인 운영/관리 문서 | area | project |
        | 지속 책임·갱신하는 운영/정책/기준 문서 | area | resource |
        | project가 아닌데 프로젝트 관련 | project 필드에 프로젝트명 기재 | project 필드 생략 |
        | 목록에 없는 명확한 프로젝트 작업 | project (project: "제안명") | resource |

        ## 프로젝트 경계 규칙
        - project 필드는 해당 문서가 프로젝트의 **직접 작업물**이거나 **직접 참조 자료**일 때만 기재
        - 같은 회사/조직의 문서라도 주제가 다르면 다른 프로젝트 (또는 프로젝트 없음)
        - 확실하지 않으면 project 필드를 생략 (잘못 연결하는 것보다 비워두는 게 나음)
        - 프로젝트 이름을 태그에 넣지 말 것 (태그는 주제/기술 키워드만)
        """
    }

    /// Build Stage 1 user message: file list + JSON array response format
    private func buildStage1UserMessage(
        _ files: [(fileName: String, content: String)]
    ) -> String {
        let fileList = files.enumerated().map { (i, f) in
            return "[\(i)] 파일명: \(f.fileName)\n내용: \(f.content)"
        }.joined(separator: "\n\n")

        return """
        ## 분류할 파일 목록
        \(fileList)

        ## 응답 형식
        반드시 아래 JSON 배열만 출력하세요. 설명이나 마크다운 코드블록 없이 순수 JSON만 반환합니다.
        [
          {
            "id": 파일 번호 ([i]의 i 값을 그대로 반환),
            "fileName": "파일명",
            "para": "project" | "area" | "resource" | "archive",
            "tags": ["태그1", "태그2"],
            "summary": "핵심 내용 한 줄 요약 (15자 이상)",
            "confidence": 0.0~1.0,
            "project": "관련 프로젝트명 (관련 있을 때만, 없으면 생략)",
            "targetFolder": "기존 폴더명 또는 NEW:폴더명. PARA 접두사 포함하지 말 것"
          }
        ]

        각 파일에 대해 정확히 하나의 객체를 반환하세요. tags는 최대 5개, 한국어 또는 영어 혼용 가능합니다.
        summary는 이 문서가 무엇에 관한 것인지 구체적으로 한 줄로 요약하세요 (후속 노트 연결에 사용됩니다).

        confidence 기준:
        - 0.9~1.0: 기존 폴더와 명확히 매칭됨
        - 0.7~0.8: 카테고리는 확실하지만 폴더 선택이 약간 불확실
        - 0.5~0.6: 카테고리 자체가 애매함
        - 0.0~0.4: 분류 불가
        기존 폴더 목록에 적합한 폴더가 있으면 confidence를 0.8 이상으로 주세요.
        """
    }

    /// Build Stage 2 user message: single file content + JSON object response format
    private func buildStage2UserMessage(
        fileName: String,
        content: String
    ) -> String {
        return """
        이 문서를 정밀하게 분석해주세요.

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
          "targetFolder": "기존 폴더명 또는 NEW:폴더명. PARA 접두사 포함하지 말 것",
          "project": "관련 프로젝트명 (관련 있을 때만, 없으면 생략)"
        }

        tags는 최대 5개, summary는 한국어로 작성하세요.

        confidence 기준:
        - 0.9~1.0: 기존 폴더와 명확히 매칭됨
        - 0.7~0.8: 카테고리는 확실하지만 폴더 선택이 약간 불확실
        - 0.5~0.6: 카테고리 자체가 애매함
        - 0.0~0.4: 분류 불가
        기존 폴더 목록에 적합한 폴더가 있으면 confidence를 0.8 이상으로 주세요.
        """
    }

    private func currentProvider() -> AIProvider {
        if let saved = UserDefaults.standard.string(forKey: AppState.DefaultsKey.selectedProvider),
           let provider = AIProvider(rawValue: saved) {
            return provider
        }
        return .claudeCLI
    }

    private func tuning(for provider: AIProvider) -> ProviderTuning {
        switch provider {
        case .claudeCLI:
            return ProviderTuning(
                stage1PreviewLength: 1600,
                stage1CharBudget: 12000,
                stage1MaxFilesPerBatch: 12,
                stage1Concurrency: 2,
                stage2Concurrency: 2,
                stage2ContentLimit: 4500
            )
        case .codexCLI:
            return ProviderTuning(
                stage1PreviewLength: 1400,
                stage1CharBudget: 10000,
                stage1MaxFilesPerBatch: 10,
                stage1Concurrency: 2,
                stage2Concurrency: 2,
                stage2ContentLimit: 4000
            )
        case .claude, .gemini:
            return ProviderTuning(
                stage1PreviewLength: 2000,
                stage1CharBudget: 50000,
                stage1MaxFilesPerBatch: maxBatchSize,
                stage1Concurrency: 3,
                stage2Concurrency: 3,
                stage2ContentLimit: nil
            )
        }
    }

    private func makeStage1Batches(
        _ files: [ClassifyInput],
        tuning: ProviderTuning
    ) -> [[ClassifyInput]] {
        guard !files.isEmpty else { return [] }

        var batches: [[ClassifyInput]] = []
        var currentBatch: [ClassifyInput] = []
        var currentChars = 0

        for file in files {
            let previewChars = min(file.preview.count, tuning.stage1PreviewLength)
            let wouldExceedCharBudget = currentChars + previewChars > tuning.stage1CharBudget
            let wouldExceedFileLimit = currentBatch.count >= tuning.stage1MaxFilesPerBatch

            if !currentBatch.isEmpty && (wouldExceedCharBudget || wouldExceedFileLimit) {
                batches.append(currentBatch)
                currentBatch = []
                currentChars = 0
            }

            currentBatch.append(file)
            currentChars += previewChars
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    // MARK: - JSON Parsing

    /// Raw JSON types for decoding (using String for para to allow validation)
    private struct Stage1RawItem: Decodable {
        var id: Int?
        let fileName: String
        let para: String
        var tags: [String]?
        var summary: String?
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
                    NSLog("[Classifier] JSON 파싱 실패: %@", error.localizedDescription)
                    NSLog("[Classifier] 원본 응답 (처음 200자): %@", String(cleaned.prefix(200)))
                }
            }
        }

        NSLog("[Classifier] JSON 추출 실패 — 응답에서 JSON을 찾을 수 없습니다")
        return nil
    }

    // MARK: - Utilities

    /// Remove PARA prefix from folder path (e.g., "3_Resource/DevOps" → "DevOps", "Area/DevOps" → "DevOps")
    private func stripParaPrefix(_ folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // Phase 1: "2_Area/DevOps" → "DevOps" (숫자 접두사 포함된 경우)
        var result = trimmed
        if let regex = Self.numericPrefixRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Phase 2: "Area/DevOps" → "DevOps" (bare 카테고리명이 경로 앞에 올 때)
        if let regex = Self.barePrefixRegex {
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

    /// Strip "NEW:" prefix from targetFolder (hallucination prevention protocol)
    private func stripNewPrefix(_ folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("NEW:") {
            return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    /// Fuzzy match AI-returned project name against actual folder names.
    /// Returns nil if no match found — prevents creating arbitrary new project folders.
    private func fuzzyMatchProject(_ aiName: String, projectNames: [String], pkmRoot: String = "") -> String? {
        guard !projectNames.isEmpty else { return nil }
        if projectNames.contains(aiName) { return aiName }

        // Phase 0: Alias registry lookup (learned from user corrections)
        if !pkmRoot.isEmpty, let resolved = ProjectAliasRegistry.resolve(aiName, pkmRoot: pkmRoot) {
            if projectNames.contains(resolved) { return resolved }
        }

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
