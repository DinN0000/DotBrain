import SwiftUI
import QuickLookThumbnailing

struct FileThumbnailView: View {
    let url: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: iconForExtension(url.pathExtension))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 64, height: 64),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = rep.nsImage
        }
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "pptx", "ppt": return "doc.text.image"
        case "xlsx", "xls": return "tablecells"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "md", "txt": return "doc.plaintext"
        default: return "doc"
        }
    }
}
