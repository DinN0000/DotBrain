import Foundation

/// Repairs notes that users created directly inside PARA folders without going through the inbox.
/// It reuses the classifier for richer metadata, but preserves the user's current location by default.
struct ManualPlacementRepairer: Sendable {
    let pkmRoot: String

    struct Result {
        let processedCount: Int
        let affectedPaths: [String]
    }

    private struct LocationContext {
        let para: PARACategory
        let folderPath: String?
        let topLevelFolder: String?
        let isRootLevel: Bool
    }

    func process(
        filePaths: [String],
        onProgress: ((Double, String) -> Void)? = nil
    ) async -> Result {
        let uniqueFiles = Array(Set(filePaths))
            .filter { $0.hasSuffix(".md") }
            .sorted()
        guard !uniqueFiles.isEmpty else {
            return Result(processedCount: 0, affectedPaths: [])
        }

        let pathManager = PKMPathManager(root: pkmRoot)
        let noteIndex = pathManager.loadNoteIndex()
        let contextBuilder = ProjectContextBuilder(pkmRoot: pkmRoot, noteIndex: noteIndex)

        onProgress?(0.05, L10n.VaultInspector.manualRepairPreparing)

        let projectContext = contextBuilder.buildProjectContext()
        let subfolderContext = contextBuilder.buildSubfolderContext()
        let projectNames = contextBuilder.extractProjectNames(from: projectContext)
        let weightedContext = contextBuilder.buildWeightedContext()
        let areaContext = contextBuilder.buildAreaContext()
        let tagVocabulary = contextBuilder.buildTagVocabulary()
        let correctionContext = CorrectionMemory.buildPromptContext(pkmRoot: pkmRoot)

        onProgress?(0.15, L10n.VaultInspector.manualRepairExtracting)
        let inputs = await ClassifyInputLoader.load(
            filePaths: uniqueFiles,
            shouldInclude: { _, content in
                !content.hasPrefix("[읽기 실패")
            }
        ) { completed, total in
            let progress = 0.15 + (Double(completed) / Double(max(total, 1))) * 0.15
            onProgress?(progress, L10n.VaultInspector.manualRepairExtractingProgress(completed, total))
        }
        guard !inputs.isEmpty else {
            return Result(processedCount: 0, affectedPaths: [])
        }

        onProgress?(0.30, L10n.VaultInspector.manualRepairClassifying)

        let classifications: [ClassifyResult]
        do {
            classifications = try await Classifier().classifyFiles(
                inputs,
                projectContext: projectContext,
                subfolderContext: subfolderContext,
                projectNames: projectNames,
                weightedContext: weightedContext,
                areaContext: areaContext,
                tagVocabulary: tagVocabulary,
                correctionContext: correctionContext,
                pkmRoot: pkmRoot,
                onProgress: { progress, status in
                    onProgress?(0.30 + progress * 0.45, status)
                }
            )
        } catch {
            NSLog("[ManualPlacementRepairer] classify 실패: %@", error.localizedDescription)
            return Result(processedCount: 0, affectedPaths: [])
        }

        let mover = FileMover(pkmRoot: pkmRoot)
        var processedCount = 0
        var affectedPaths: [String] = []

        for (index, pair) in zip(inputs, classifications).enumerated() {
            let input = pair.0
            let classification = pair.1

            guard let location = locationContext(for: input.filePath) else { continue }
            let adjusted = adjustClassification(classification, location: location)

            do {
                let result: ProcessedFileResult
                if shouldMove(location: location, classification: adjusted) {
                    result = try await mover.moveFile(at: input.filePath, with: adjusted)
                } else {
                    result = updateFrontmatterInPlace(
                        at: input.filePath,
                        classification: adjusted,
                        location: location
                    )
                }

                if result.isSuccess {
                    processedCount += 1
                    if !result.targetPath.isEmpty {
                        affectedPaths.append(result.targetPath)
                    }
                    StatisticsService.recordActivity(
                        fileName: result.fileName,
                        category: adjusted.para.rawValue,
                        action: "manual-repaired",
                        detail: result.displayTarget
                    )
                }
            } catch {
                NSLog(
                    "[ManualPlacementRepairer] 처리 실패 %@: %@",
                    input.fileName,
                    error.localizedDescription
                )
            }

            let progress = 0.75 + (Double(index + 1) / Double(max(inputs.count, 1))) * 0.25
            onProgress?(progress, L10n.VaultInspector.manualRepairProcessingProgress(index + 1, inputs.count))
        }

        return Result(
            processedCount: processedCount,
            affectedPaths: Array(Set(affectedPaths)).sorted()
        )
    }

    // MARK: - Classification Adjustment

    private func locationContext(for filePath: String) -> LocationContext? {
        let normalized = URL(fileURLWithPath: filePath).standardizedFileURL.path
        let components = normalized.split(separator: "/").map(String.init)

        guard let paraIndex = components.firstIndex(where: { PARACategory(folderPrefix: $0) != nil }),
              let para = PARACategory(folderPrefix: components[paraIndex]) else {
            return nil
        }

        let relativeComponents = components.dropFirst(paraIndex + 1)
        guard !relativeComponents.isEmpty else { return nil }

        let relativeArray = Array(relativeComponents)
        let pathWithoutFile = relativeArray.count > 1
            ? Array(relativeArray[..<(relativeArray.count - 1)])
            : []
        let folderPath = pathWithoutFile.isEmpty ? nil : pathWithoutFile.joined(separator: "/")

        return LocationContext(
            para: para,
            folderPath: folderPath,
            topLevelFolder: pathWithoutFile.first,
            isRootLevel: folderPath == nil
        )
    }

    private func adjustClassification(
        _ classification: ClassifyResult,
        location: LocationContext
    ) -> ClassifyResult {
        var adjusted = classification
        adjusted.para = location.para

        if let folderPath = location.folderPath, !folderPath.isEmpty {
            adjusted.targetFolder = folderPath
            if location.para == .project, let project = location.topLevelFolder, !project.isEmpty {
                adjusted.project = project
            }
            return adjusted
        }

        if location.para == .project, let project = adjusted.project, !project.isEmpty {
            adjusted.targetFolder = project
        }

        return adjusted
    }

    private func shouldMove(location: LocationContext, classification: ClassifyResult) -> Bool {
        if !location.isRootLevel {
            return false
        }

        return !classification.targetFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Write Back

    private func updateFrontmatterInPlace(
        at filePath: String,
        classification: ClassifyResult,
        location: LocationContext
    ) -> ProcessedFileResult {
        let fileName = (filePath as NSString).lastPathComponent

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: filePath,
                tags: classification.tags,
                status: .error("파일 읽기 실패")
            )
        }

        let (existing, body) = Frontmatter.parse(markdown: content)
        let mergedTags = Array(Set(existing.tags + classification.tags)).sorted()
        let inferredArea = classification.para == .area ? location.topLevelFolder : existing.area
        let inferredProject: String?
        if let project = classification.project, !project.isEmpty {
            inferredProject = project
        } else if classification.para == .project {
            inferredProject = location.topLevelFolder
        } else {
            inferredProject = existing.project
        }

        let summary = classification.summary.isEmpty
            ? existing.summary
            : classification.summary

        let updated = Frontmatter(
            para: classification.para,
            tags: mergedTags,
            created: existing.created ?? Frontmatter.today(),
            status: existing.status ?? .active,
            summary: summary,
            source: existing.source ?? .import,
            project: inferredProject,
            area: inferredArea,
            projects: existing.projects,
            file: existing.file
        )

        let result = updated.stringify() + "\n" + body
        do {
            try result.write(toFile: filePath, atomically: true, encoding: .utf8)
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: filePath,
                tags: mergedTags
            )
        } catch {
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: filePath,
                tags: mergedTags,
                status: .error("쓰기 실패: \(error.localizedDescription)")
            )
        }
    }
}
