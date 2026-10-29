import AppKit

/// One copy, kept in every format it was put on the clipboard in, so it pastes back with its
/// formatting, line breaks and images as they came.
struct Clip {
    enum Content {
        case text(String)
        case image(thumbnail: NSImage, pixelSize: NSSize)
        case files([URL])
    }

    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// Larger copies are left out, so a few huge images can't fill up memory.
    private static let maxBytes = 32 << 20
    private static let thumbnailHeight: CGFloat = 32

    /// Each pasteboard item's data by type, in the order they came.
    let representations: [[NSPasteboard.PasteboardType: Data]]
    /// What the menu shows.
    let content: Content
    /// Password managers mark passwords this way. They're shown as dots.
    let isConcealed: Bool

    init?(from pasteboard: NSPasteboard) {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        var bytes = 0
        representations = items.map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let value = item.data(forType: type) else { continue }
                data[type] = value
                bytes += value.count
            }
            return data
        }
        guard bytes <= Self.maxBytes else { return nil }
        isConcealed = pasteboard.types?.contains(Self.concealedType) ?? false

        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty {
            content = .files(files)
        } else if let text = pasteboard.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = .text(text)
        } else if let image = NSImage(pasteboard: pasteboard), let thumbnail = Self.thumbnail(of: image) {
            let rep = image.representations.first
            let pixelSize = rep.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
            content = .image(thumbnail: thumbnail, pixelSize: pixelSize)
        } else {
            return nil
        }
    }

    /// Whether this is the same thing copied again. Text counts as the same whatever its
    /// formatting, so copying it again moves it to the top instead of adding it twice.
    func isSame(as other: Clip) -> Bool {
        switch (content, other.content) {
        case let (.text(a), .text(b)): return a == b
        case let (.files(a), .files(b)): return a == b
        default: return representations == other.representations
        }
    }

    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(representations.map { data in
            let item = NSPasteboardItem()
            for (type, value) in data { item.setData(value, forType: type) }
            return item
        })
    }

    /// Drawn into a small bitmap now, so the menu doesn't hold on to the full image or decode it
    /// each time it opens.
    private static func thumbnail(of image: NSImage) -> NSImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(thumbnailHeight / image.size.height, thumbnailHeight * 4 / image.size.width, 1)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        // Twice the size, for Retina screens.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        rep.size = size
        let thumbnail = NSImage(size: size)
        thumbnail.addRepresentation(rep)
        return thumbnail
    }
}
