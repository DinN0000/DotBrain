import Foundation

/// AI-based context linker that finds semantically related notes using the vault context map
struct ContextLinker: Sendable {
    let pkmRoot: String
    private let aiService = AIService.shared
    private let batchSize = 5
    private let maxConcurrentBatches = 3

    /// Find related notes for a batch of classified files using AI
    func findRelatedNotes(
        for files: [(input: ClassifyInput, classification: ClassifyResult)],
        contextMap: VaultContextMap,
        onProgress: ((Double, String) -> Void)? = nil
    ) async -> [Int: [RelatedNote]] {
        guard !files.isEmpty else { return [:] }

        let contextText = contextMap.toPromptText()

        // Skip if vault is empty
        guard contextMap.entries.count > 0 else { return [:] }

        // Create batches with original indices preserved
        let indexedFiles = files.enumerated().map { ($0.offset, $0.element) }
        let batches = stride(from: 0, to: indexedFiles.count, by: batchSize).map {
            Array(indexedFiles[$0..<min($0 + batchSize, indexedFiles.count)])
        }

        let totalBatches = batches.count

        // Process batches concurrently (max 3)
        let results: [Int: [RelatedNote]] = await withTaskGroup(
            of: [(Int, [RelatedNote])].self,
            returning: [Int: [RelatedNote]].self
        ) { group in
            var activeTasks = 0
            var completedBatches = 0
            var combined: [Int: [RelatedNote]] = [:]

            for batch in batches {
                if activeTasks >= maxConcurrentBatches {
                    if let batchResults = await group.next() {
                        for (idx, notes) in batchResults {
                            combined[idx] = notes
                        }
                        activeTasks -= 1
                        completedBatches += 1
                        let progress = Double(completedBatches) / Double(totalBatches)
                        onProgress?(progress, "노트 연결 \(completedBatches)/\(totalBatches) 배치 완료")
                    }
                }

                group.addTask {
                    return await self.processBatch(batch, contextText: contextText)
                }
                activeTasks += 1
            }

            for await batchResults in group {
                for (idx, notes) in batchResults {
                    combined[idx] = notes
                }
                completedBatches += 1
                let progress = Double(completedBatches) / Double(totalBatches)
                onProgress?(progress, "노트 연결 \(completedBatches)/\(totalBatches) 배치 완료")
            }
            return combined
        }

        return results
    }

    /// Process a single batch of files with one AI call
    private func processBatch(
        _ batch: [(index: Int, file: (input: ClassifyInput, classification: ClassifyResult))],
        contextText: String
    ) async -> [(Int, [RelatedNote])] {
        let noteDescriptions = batch.enumerated().map { (i, item) in
            let c = item.file.classification
            let tags = c.tags.joined(separator: ", ")
            // Use summary if available; otherwise extract a short content preview
            let description: String
            if !c.summary.isEmpty {
                description = c.summary
            } else {
                let preview = FileContentExtractor.extractPreview(
                    from: item.file.input.filePath,
                    content: item.file.input.content,
                    maxLength: 300
                )
                description = preview
            }
            return """
            [\(i)] 파일명: \(item.file.input.fileName)
            분류: \(c.para.rawValue)/\(c.targetFolder)
            태그: \(tags)
            내용: \(description)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        당신은 PKM 볼트의 노트 연결 전문가입니다.

        ## 중요 규칙
        1. 단순 태그 일치가 아닌 맥락적 연관성을 찾으세요
        2. context는 "~하려면", "~할 때", "~와 비교할 때" 형식으로 작성
        3. 같은 폴더뿐 아니라 다른 폴더/카테고리의 노트도 적극 연결
        4. 자기 자신은 포함하지 마세요
        5. 관련 노트가 없으면 빈 배열을 반환하세요

        ## 볼트 전체 맥락 (MOC 기반)
        \(contextText)

        ## 분석할 문서들
        \(noteDescriptions)

        ## 응답 형식
        반드시 아래 JSON 배열만 출력하세요. 설명이나 마크다운 코드블록 없이 순수 JSON만 반환합니다.
        [
          {
            "index": 0,
            "relatedNotes": [
              {"name": "노트명 (확장자 없이)", "context": "~하려면 참고"}
            ]
          }
        ]

        각 문서에 대해 최대 5개의 관련 노트를 추천하세요.
        """

        do {
            let response = try await aiService.sendFast(maxTokens: 2048, message: prompt)

            // Track API cost for context linking batch
            let estimatedCost = Double(batch.count) * 0.0005  // ~$0.0005 per file for fast model
            StatisticsService.addApiCost(estimatedCost)

            let parsed = parseResponse(response)

            return batch.enumerated().map { (i, item) in
                let notes = parsed[i] ?? []
                // Filter out self-references
                let selfName = (item.file.input.fileName as NSString).deletingPathExtension
                let filtered = notes.filter { $0.name != selfName }
                return (item.index, filtered)
            }
        } catch {
            // On failure, return empty results for all files in batch
            return batch.map { ($0.index, []) }
        }
    }

    /// Parse AI response JSON into index → [RelatedNote] mapping
    private func parseResponse(_ text: String) -> [Int: [RelatedNote]] {
        let cleaned = text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else {
            return [:]
        }

        let jsonStr = String(cleaned[startBracket...endBracket])
        guard let data = jsonStr.data(using: .utf8) else { return [:] }

        do {
            let items = try JSONDecoder().decode([LinkResponseItem].self, from: data)
            var result: [Int: [RelatedNote]] = [:]
            for item in items {
                let notes = (item.relatedNotes ?? []).compactMap { raw -> RelatedNote? in
                    guard !raw.name.isEmpty else { return nil }
                    return RelatedNote(name: raw.name, context: raw.context ?? "관련 문서")
                }
                result[item.index] = Array(notes.prefix(5))
            }
            return result
        } catch {
            return [:]
        }
    }

    // MARK: - JSON Types

    private struct LinkResponseItem: Decodable {
        let index: Int
        let relatedNotes: [LinkNoteRaw]?
    }

    private struct LinkNoteRaw: Decodable {
        let name: String
        var context: String?
    }
}
