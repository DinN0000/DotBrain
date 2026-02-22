import Foundation

struct TagNormalizer: Sendable {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    struct Result {
        var filesModified: Int = 0
        var tagsAdded: Int = 0
    }

    func normalize() throws -> Result {
        var result = Result()
        let fm = FileManager.default

        // 1. Project folder notes: ensure project folder name is in tags
        let projectsBase = pathManager.projectsPath
        if let projects = try? fm.contentsOfDirectory(atPath: projectsBase) {
            for project in projects {
                guard !project.hasPrefix("."), !project.hasPrefix("_") else { continue }
                let projectPath = (projectsBase as NSString).appendingPathComponent(project)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                    guard file != "\(project).md" else { continue }

                    let filePath = (projectPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                    if try addTagIfMissing(filePath: filePath, content: content, tag: project) {
                        result.filesModified += 1
                        result.tagsAdded += 1
                    }
                }
            }
        }

        // 2. Non-project notes with project field: ensure project value is in tags
        let nonProjectBases = [pathManager.areaPath, pathManager.resourcePath, pathManager.archivePath]
        for basePath in nonProjectBases {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                    guard file != "\(folder).md" else { continue }

                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                    let (frontmatter, _) = Frontmatter.parse(markdown: content)

                    guard let projectName = frontmatter.project, !projectName.isEmpty else { continue }

                    if try addTagIfMissing(filePath: filePath, content: content, tag: projectName) {
                        result.filesModified += 1
                        result.tagsAdded += 1
                    }
                }
            }
        }

        return result
    }

    @discardableResult
    private func addTagIfMissing(filePath: String, content: String, tag: String) throws -> Bool {
        let (frontmatter, body) = Frontmatter.parse(markdown: content)

        let normalizedTag = tag.trimmingCharacters(in: .whitespaces)
        guard !normalizedTag.isEmpty else { return false }

        let lowerTag = normalizedTag.lowercased()
        if frontmatter.tags.contains(where: { $0.lowercased() == lowerTag }) {
            return false
        }

        var updatedFM = frontmatter
        updatedFM.tags.append(normalizedTag)

        let newContent = updatedFM.stringify() + "\n" + body
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        return true
    }
}
