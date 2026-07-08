import Foundation

/// Partial-read helper for feeding note bodies into AI prompts.
/// Mirrors the FileHandle + UTF-8 boundary-trim pattern in NoteIndexGenerator.
enum NoteExcerptReader {
    static func read(_ absolutePath: String, maxBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: absolutePath) else { return nil }
        let data = handle.readData(ofLength: maxBytes)
        handle.closeFile()
        // readData may cut in the middle of a multi-byte UTF-8 character;
        // trim up to 3 trailing bytes to recover a valid string
        for trim in 0...min(3, data.count) {
            if let s = String(data: data.dropLast(trim), encoding: .utf8) {
                return s
            }
        }
        return nil
    }
}
