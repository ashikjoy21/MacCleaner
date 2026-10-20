import Foundation

/// Helps Quick Look preview files that have no extension, like Telegram's cache files.
public enum QuickLookSupport {
    /// Returns `url` itself when Quick Look can recognise it. Otherwise identifies the file from its
    /// header and returns a symlink with the right extension in a temporary folder.
    public static func previewableURL(for url: URL) -> URL {
        guard url.pathExtension.isEmpty, !FileSystem.isDirectory(url) else { return url }
        let (_, format) = TelegramCategory.classify(url)
        let extensions = ["MKV": "mkv", "MOV": "mov", "MP4": "mp4", "M4A": "m4a", "HEIC": "heic", "JPEG": "jpg",
                          "PNG": "png", "GIF": "gif", "WebP": "webp", "Ogg": "ogg", "MP3": "mp3", "PDF": "pdf", "ZIP": "zip"]
        guard let ext = extensions[format] else { return url }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacCleaner Previews")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent(url.lastPathComponent).appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: link)
        return (try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)) != nil ? link : url
    }
}
