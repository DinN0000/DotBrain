import Foundation
import ZIPFoundation

/// Extracts text and metadata from XLSX files (ZIP + XML)
enum XLSXExtractor {
    static let maxTextLength = 50_000
    static let maxRowsPerSheet = 100

    static func extract(at path: String) -> ExtractResult {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let sizeKB = Double(fileSize) / 1024.0

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return .failure(name: fileName, error: "XLSX 파일을 열 수 없습니다: \(error.localizedDescription)")
        }

        var metadata = extractOOXMLMetadata(from: archive)

        // Load shared strings
        let sharedStrings = loadSharedStrings(from: archive)

        // Load sheet names from workbook.xml
        let sheetNames = loadSheetNames(from: archive)
        metadata["sheet_count"] = sheetNames.count
        metadata["sheet_names"] = sheetNames

        // Find sheet files
        var sheetEntries: [(Int, Entry)] = []
        for entry in archive {
            if let match = entry.path.range(of: #"xl/worksheets/sheet(\d+)\.xml"#, options: .regularExpression) {
                let numStr = entry.path[match]
                    .replacingOccurrences(of: "xl/worksheets/sheet", with: "")
                    .replacingOccurrences(of: ".xml", with: "")
                if let num = Int(numStr) {
                    sheetEntries.append((num, entry))
                }
            }
        }
        sheetEntries.sort { $0.0 < $1.0 }

        // Extract text from sheets
        var sheetsText: [String] = []

        for (idx, entry) in sheetEntries {
            guard let content = readEntry(entry, from: archive) else { continue }
            let sheetName = (idx - 1) < sheetNames.count ? sheetNames[idx - 1] : "Sheet\(idx)"
            let rows = extractRows(from: content, sharedStrings: sharedStrings)

            if !rows.isEmpty {
                sheetsText.append("[시트: \(sheetName)]\n\(rows.joined(separator: "\n"))")
            }
        }

        var text: String? = sheetsText.isEmpty ? nil : sheetsText.joined(separator: "\n\n")
        if let t = text, t.count > maxTextLength {
            text = String(t.prefix(maxTextLength)) + "\n... (잘림)"
        }

        return ExtractResult(
            success: true,
            file: ExtractResult.FileInfo(name: fileName, format: "xlsx", sizeKB: round(sizeKB * 10) / 10),
            metadata: metadata,
            text: text,
            error: nil
        )
    }

    // MARK: - Private

    private static func loadSharedStrings(from archive: Archive) -> [String] {
        guard let entry = archive["xl/sharedStrings.xml"],
              let content = readEntry(entry, from: archive) else {
            return []
        }

        var strings: [String] = []

        // Parse <si>...<t>text</t>...</si> blocks
        let siPattern = #"<si[^>]*>([\s\S]*?)</si>"#
        guard let siRegex = try? NSRegularExpression(pattern: siPattern) else { return strings }

        let nsRange = NSRange(content.startIndex..., in: content)
        let siMatches = siRegex.matches(in: content, range: nsRange)

        let tPattern = #"<t[^>]*>([^<]*)</t>"#
        guard let tRegex = try? NSRegularExpression(pattern: tPattern) else { return strings }

        for siMatch in siMatches {
            guard let siRange = Range(siMatch.range(at: 1), in: content) else { continue }
            let siContent = String(content[siRange])
            let siNSRange = NSRange(siContent.startIndex..., in: siContent)
            let tMatches = tRegex.matches(in: siContent, range: siNSRange)

            var texts: [String] = []
            for tMatch in tMatches {
                if let textRange = Range(tMatch.range(at: 1), in: siContent) {
                    texts.append(String(siContent[textRange]))
                }
            }
            strings.append(texts.joined())
        }

        return strings
    }

    private static func loadSheetNames(from archive: Archive) -> [String] {
        guard let entry = archive["xl/workbook.xml"],
              let content = readEntry(entry, from: archive) else {
            return []
        }

        var names: [String] = []

        // Find <sheets>...</sheets> section
        let sheetsPattern = #"<sheets>([\s\S]*?)</sheets>"#
        guard let sheetsRegex = try? NSRegularExpression(pattern: sheetsPattern),
              let sheetsMatch = sheetsRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let sheetsRange = Range(sheetsMatch.range(at: 1), in: content) else {
            return names
        }

        let sheetsContent = String(content[sheetsRange])
        let namePattern = #"name="([^"]+)""#
        guard let nameRegex = try? NSRegularExpression(pattern: namePattern) else { return names }

        let nsRange = NSRange(sheetsContent.startIndex..., in: sheetsContent)
        let matches = nameRegex.matches(in: sheetsContent, range: nsRange)
        for match in matches {
            if let range = Range(match.range(at: 1), in: sheetsContent) {
                names.append(String(sheetsContent[range]))
            }
        }

        return names
    }

    private static func extractRows(from xml: String, sharedStrings: [String]) -> [String] {
        var rows: [String] = []

        let rowPattern = #"<row[^>]*>([\s\S]*?)</row>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern) else { return rows }

        let nsRange = NSRange(xml.startIndex..., in: xml)
        let rowMatches = rowRegex.matches(in: xml, range: nsRange)

        let cellPattern = #"<c[^>]*?(t="([^"]*)")?[^>]*>([\s\S]*?)</c>"#
        let valuePattern = #"<v>([^<]*)</v>"#
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern),
              let valueRegex = try? NSRegularExpression(pattern: valuePattern) else { return rows }

        for rowMatch in rowMatches {
            guard let rowRange = Range(rowMatch.range(at: 0), in: xml) else { continue }
            let rowContent = String(xml[rowRange])
            let rowNSRange = NSRange(rowContent.startIndex..., in: rowContent)

            var cells: [String] = []
            let cellMatches = cellRegex.matches(in: rowContent, range: rowNSRange)

            for cellMatch in cellMatches {
                let cellType: String
                if let typeRange = Range(cellMatch.range(at: 2), in: rowContent) {
                    cellType = String(rowContent[typeRange])
                } else {
                    cellType = ""
                }

                guard let cellContentRange = Range(cellMatch.range(at: 3), in: rowContent) else {
                    cells.append("")
                    continue
                }
                let cellContent = String(rowContent[cellContentRange])
                let cellNSRange = NSRange(cellContent.startIndex..., in: cellContent)

                if let vMatch = valueRegex.firstMatch(in: cellContent, range: cellNSRange),
                   let vRange = Range(vMatch.range(at: 1), in: cellContent) {
                    let value = String(cellContent[vRange])
                    if cellType == "s", let idx = Int(value), idx < sharedStrings.count {
                        cells.append(sharedStrings[idx])
                    } else {
                        cells.append(value)
                    }
                } else {
                    cells.append("")
                }
            }

            if cells.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(cells.joined(separator: " | "))
            }

            if rows.count >= maxRowsPerSheet {
                rows.append("... (이하 생략)")
                break
            }
        }

        return rows
    }
}
