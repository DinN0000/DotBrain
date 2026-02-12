import Foundation

/// Loads note templates from .Templates/ folder, with built-in fallbacks
enum TemplateService {
    /// Load a template by name from .Templates/ folder
    static func loadTemplate(name: String, pkmRoot: String) -> String? {
        let templatesDir = (pkmRoot as NSString).appendingPathComponent(".Templates")
        let templatePath = (templatesDir as NSString).appendingPathComponent("\(name).md")
        return try? String(contentsOfFile: templatePath, encoding: .utf8)
    }

    /// Create default .Templates/ folder with Note.md, Project.md, Asset.md
    static func initializeTemplates(pkmRoot: String) throws {
        let fm = FileManager.default
        let templatesDir = (pkmRoot as NSString).appendingPathComponent(".Templates")
        try fm.createDirectory(atPath: templatesDir, withIntermediateDirectories: true)

        let templates: [(String, String)] = [
            ("Note", noteTemplate),
            ("Project", projectTemplate),
            ("Asset", assetTemplate),
        ]

        for (name, content) in templates {
            let path = (templatesDir as NSString).appendingPathComponent("\(name).md")
            if !fm.fileExists(atPath: path) {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Default Templates

    private static let noteTemplate = """
    ---
    para:
    tags: []
    created: {{date}}
    status: active
    summary:
    source: original
    ---

    # {{title}}

    ## Related Notes

    """

    private static let projectTemplate = """
    ---
    para: project
    tags: []
    created: {{date}}
    status: active
    summary:
    source: original
    ---

    # {{project_name}}

    ## 목적

    ## 현재 상태

    ## 포함된 노트

    ## Related Notes

    """

    private static let assetTemplate = """
    ---
    para:
    tags: []
    created: {{date}}
    status: active
    summary:
    source: import
    file:
      name: {{filename}}
      format: {{format}}
      size_kb: {{size_kb}}
    ---

    # {{filename}}

    ## 핵심 내용

    ## Related Notes

    """

    /// Apply template variables
    static func apply(template: String, variables: [String: String]) -> String {
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        // Replace date placeholder with today
        result = result.replacingOccurrences(of: "{{date}}", with: Frontmatter.today())
        return result
    }
}
