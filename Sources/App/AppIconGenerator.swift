import AppKit

enum AppIconGenerator {
    static func generate(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius = size * 0.22

        let path = CGPath(
            roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // Black background
        context.addPath(path)
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0))
        context.fillPath()

        // White face ·_·
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1.0)
        context.setFillColor(white)
        context.setStrokeColor(white)

        // Eyes (dots)
        let eyeRadius = size * 0.035
        let eyeY = size * 0.52
        let eyeSpacing = size * 0.15

        context.fillEllipse(in: CGRect(
            x: size / 2 - eyeSpacing - eyeRadius,
            y: eyeY - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        ))
        context.fillEllipse(in: CGRect(
            x: size / 2 + eyeSpacing - eyeRadius,
            y: eyeY - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        ))

        // Mouth (flat line _)
        context.setLineWidth(size * 0.02)
        context.setLineCap(.round)
        let mouthY = eyeY - size * 0.10
        context.move(to: CGPoint(x: size / 2 - eyeSpacing * 0.6, y: mouthY))
        context.addLine(to: CGPoint(x: size / 2 + eyeSpacing * 0.6, y: mouthY))
        context.strokePath()

        image.unlockFocus()
        return image
    }
}
