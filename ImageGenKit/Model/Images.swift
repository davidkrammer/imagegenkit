import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum Paths {
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    /// `-configDir <path>` points the app at another folder (demo data for screenshots).
    static let config: URL = UserDefaults.standard.string(forKey: "configDir").map { URL(fileURLWithPath: $0) }
        ?? home.appending(path: ".config/imagegenkit")
    static let legacyConfig = home.appending(path: ".config/imagegen")
    static let log = config.appending(path: "log.jsonl")
    static let thumbs = config.appending(path: "thumbs")
    static let grokSessions = home.appending(path: ".grok/sessions")
    static let cli = home.appending(path: ".local/bin/imagegenkit")

    /// Moves the old CLI's ~/.config/imagegen to ~/.config/imagegenkit once (same as the CLI does),
    /// leaving a symlink so paths already in the log keep working.
    static func migrateLegacyConfig() {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: legacyConfig.path, isDirectory: &isDir), isDir.boolValue,
              (try? fm.destinationOfSymbolicLink(atPath: legacyConfig.path)) == nil,
              !fm.fileExists(atPath: config.path) else { return }
        do {
            try fm.moveItem(at: legacyConfig, to: config)
            try fm.createSymbolicLink(at: legacyConfig, withDestinationURL: config)
        } catch {}
    }
}

/// One generated image: output `index` of the run logged at `ts`.
nonisolated struct ImageRef: Sendable, Hashable {
    let ts: String
    let output: String
    let cliThumb: String?
    let grokSession: String?
    let index: Int
}

extension LogEntry {
    nonisolated func imageRef(_ i: Int) -> ImageRef {
        ImageRef(ts: ts, output: outputs[i], cliThumb: i < thumbs.count ? thumbs[i] : nil,
                 grokSession: grokSession, index: i)
    }
}

nonisolated enum SourceKind: Sendable {
    case original   // the file imagegen saved
    case grokCopy   // original gone, Grok Build still has its own copy in ~/.grok/sessions
    case preview    // only the 512 px archived preview is left
}

/// Finds where an image still exists on disk.
nonisolated enum ImageLocator {
    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    /// Grok Build keeps each headless run's images in ~/.grok/sessions/<encoded cwd>/<session>/images/.
    static func grokCopies(session: String) -> [URL] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: Paths.grokSessions, includingPropertiesForKeys: nil)
        else { return [] }
        for dir in dirs {
            let images = dir.appending(path: session).appending(path: "images")
            guard let files = try? fm.contentsOfDirectory(at: images, includingPropertiesForKeys: [.contentModificationDateKey]),
                  !files.isEmpty else { continue }
            return files.sorted { mtime($0) < mtime($1) }
        }
        return []
    }

    /// Best full-size file still on disk.
    static func source(for r: ImageRef) -> (url: URL, kind: SourceKind)? {
        if exists(r.output) { return (URL(fileURLWithPath: r.output), .original) }
        if let s = r.grokSession {
            let copies = grokCopies(session: s)
            if r.index < copies.count { return (copies[r.index], .grokCopy) }
        }
        return nil
    }

    /// Same key the imagegen CLI uses: sha1("<ts>|<absolute output path>")[:16].
    static func thumbKey(ts: String, path: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data("\(ts)|\(path)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    static func archiveFolder(ts: String) -> URL { Paths.thumbs.appending(path: String(ts.prefix(7))) }

    static func existingThumb(for r: ImageRef) -> URL? {
        if let t = r.cliThumb, exists(t) { return URL(fileURLWithPath: t) }
        let base = archiveFolder(ts: r.ts).appending(path: thumbKey(ts: r.ts, path: r.output))
        for ext in ["jpg", "png"] {
            let url = base.appendingPathExtension(ext)
            if exists(url.path) { return url }
        }
        return nil
    }

    private static func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Small previews (512 px), kept in ~/.config/imagegen/thumbs so history survives deleted originals.
nonisolated enum Thumbnails {
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>()
        c.countLimit = 1000
        return c
    }()

    static func thumbnail(_ r: ImageRef) async -> CGImage? {
        let key = "\(r.ts)|\(r.output)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { loadOrCreate(r) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// A larger image for the detail panel: the original (or Grok's copy), else the archived preview.
    static func preview(_ r: ImageRef, maxPixel: Int = 1800) async -> (image: CGImage, kind: SourceKind)? {
        await Task.detached(priority: .userInitiated) { () -> (image: CGImage, kind: SourceKind)? in
            if let src = ImageLocator.source(for: r), let img = downsample(src.url, maxPixel: maxPixel) {
                return (img, src.kind)
            }
            if let t = ImageLocator.existingThumb(for: r), let img = decode(t) { return (img, .preview) }
            return nil
        }.value
    }

    /// Returns the archived preview, creating it from the original or Grok's copy when missing.
    static func loadOrCreate(_ r: ImageRef) -> CGImage? {
        if let t = ImageLocator.existingThumb(for: r), let img = decode(t) { return img }
        return create(r)
    }

    /// Makes sure a preview exists. Returns true if one exists afterwards.
    @discardableResult
    static func ensureArchived(_ r: ImageRef) -> Bool {
        if ImageLocator.existingThumb(for: r) != nil { return true }
        return create(r) != nil
    }

    private static func create(_ r: ImageRef) -> CGImage? {
        guard let src = ImageLocator.source(for: r),
              let image = downsample(src.url, maxPixel: 512) else { return nil }
        let alpha = hasAlpha(src.url)
        let folder = ImageLocator.archiveFolder(ts: r.ts)
        let url = folder.appending(path: ImageLocator.thumbKey(ts: r.ts, path: r.output))
            .appendingPathExtension(alpha ? "png" : "jpg")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let type = (alpha ? UTType.png : UTType.jpeg).identifier as CFString
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) {
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
        return image
    }

    static func downsample(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }

    private static func hasAlpha(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return props[kCGImagePropertyHasAlpha] as? Bool ?? false
    }
}

/// Runs a command with a PATH that finds imagegen, python3 and grok (GUI apps start with a minimal PATH).
nonisolated enum Shell {
    struct Result: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static let path: String = {
        let h = NSHomeDirectory()
        return "\(h)/.local/bin:\(h)/.grok/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }()

    /// Writing to a pipe whose reader is gone (the child already exited) raises SIGPIPE, which kills the app.
    /// Ignored once, so the write fails with EPIPE instead.
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    private final class Box: @unchecked Sendable { var data = Data() }

    static func run(_ executable: URL, _ arguments: [String], stdin: String? = nil) async -> Result {
        await Task.detached(priority: .userInitiated) { runBlocking(executable, arguments, stdin: stdin) }.value
    }

    /// Blocks the calling thread until the command exits.
    private static func runBlocking(_ executable: URL, _ arguments: [String], stdin: String?) -> Result {
        _ = ignoreSIGPIPE
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        p.environment = env
        let out = Pipe(), err = Pipe(), input = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = input
        do { try p.run() } catch { return Result(status: -1, stdout: "", stderr: error.localizedDescription) }
        // stdin is written and stderr read on their own threads: a child that fills the stderr pipe
        // (64 KB) while we wait on stdout, or that reads stdin only after writing output, would deadlock.
        let group = DispatchGroup(), errBox = Box()
        let writer = input.fileHandleForWriting, errReader = err.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            if let stdin { try? writer.write(contentsOf: Data(stdin.utf8)) }  // throwing API: EPIPE is an error, not an exception
            try? writer.close()
        }
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            errBox.data = errReader.readDataToEndOfFile()
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, stdout: String(decoding: o, as: UTF8.self),
                      stderr: String(decoding: errBox.data, as: UTF8.self))
    }
}
