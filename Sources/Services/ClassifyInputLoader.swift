import Foundation

/// Builds classifier inputs in parallel while preserving the caller's file order.
enum ClassifyInputLoader {
    static func load(
        filePaths: [String],
        maxConcurrent: Int = 5,
        contentExtractor: @escaping @Sendable (String) -> String = { path in
            FileContentExtractor.extract(from: path)
        },
        shouldInclude: @escaping @Sendable (String, String) -> Bool = { _, _ in true },
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [ClassifyInput] {
        guard !filePaths.isEmpty else { return [] }

        return await withTaskGroup(
            of: (Int, ClassifyInput?).self,
            returning: [ClassifyInput].self
        ) { group in
            var collected: [Int: ClassifyInput] = [:]
            collected.reserveCapacity(filePaths.count)
            var nextIndex = 0
            var activeTasks = 0
            var completed = 0

            while nextIndex < filePaths.count || !group.isEmpty {
                while activeTasks < maxConcurrent && nextIndex < filePaths.count {
                    let currentIndex = nextIndex
                    let filePath = filePaths[currentIndex]
                    nextIndex += 1
                    activeTasks += 1

                    group.addTask {
                        let content = contentExtractor(filePath)
                        guard shouldInclude(filePath, content) else {
                            return (currentIndex, nil)
                        }

                        let fileName = (filePath as NSString).lastPathComponent
                        let preview = FileContentExtractor.extractPreview(
                            from: filePath,
                            content: content
                        )

                        return (
                            currentIndex,
                            ClassifyInput(
                                filePath: filePath,
                                content: content,
                                fileName: fileName,
                                preview: preview
                            )
                        )
                    }
                }

                guard let (index, input) = await group.next() else { continue }
                activeTasks -= 1
                completed += 1
                if let input {
                    collected[index] = input
                }
                onProgress(completed, filePaths.count)
            }

            return filePaths.indices.compactMap { collected[$0] }
        }
    }
}
