import AppKit
import Foundation
import Observation

/// Updates the app from GitHub Releases: download the release zip, verify it, swap the bundle, relaunch.
@Observable
final class Updater {
    enum State: Equatable {
        case idle, checking, upToDate, available(String), downloading, installing, failed(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var asset: URL?
    @ObservationIgnored private(set) var releasePage: URL?

    static let repo = "davidkrammer/imagegenkit"
    static var api: URL {
        #if DEBUG
        // `-debugUpdateAPI <url>`: a local mock release (testing the updater end to end).
        if let s = UserDefaults.standard.string(forKey: "debugUpdateAPI"), let url = URL(string: s) { return url }
        #endif
        return URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }
    static let homepage = URL(string: "https://github.com/\(repo)")!
    /// Donations: PayPal works without an account; GitHub Sponsors does one-time or monthly.
    static let donatePayPal = URL(string: "https://www.paypal.com/donate/?business=hello%40strics.at&currency_code=EUR&item_name=ImageGenKit")!
    static let donateGitHub = URL(string: "https://github.com/sponsors/davidkrammer")!

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var updateAvailable: Bool { if case .available = state { true } else { false } }

    func check(quiet: Bool = false) async {
        if !quiet { state = .checking }
        var req = URLRequest(url: Self.api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else {
                state = quiet ? .idle : .upToDate
                return
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            releasePage = (obj["html_url"] as? String).flatMap(URL.init(string:))
            let assets = obj["assets"] as? [[String: Any]] ?? []
            asset = assets.compactMap { a -> URL? in
                guard let name = a["name"] as? String, name.hasSuffix(".zip"), name.contains("ImageGenKit") else { return nil }
                return (a["browser_download_url"] as? String).flatMap(URL.init(string:))
            }.first
            state = Installer.compare(version, currentVersion) > 0 ? .available(version) : (quiet ? .idle : .upToDate)
            #if DEBUG
            if updateAvailable, UserDefaults.standard.bool(forKey: "debugInstallUpdate") { await install() }  // updater test
            #endif
        } catch {
            state = quiet ? .idle : .failed("Couldn't reach GitHub")
        }
    }

    /// Downloads and installs the update, then relaunches.
    func install() async {
        guard let asset else {
            if let releasePage { NSWorkspace.shared.open(releasePage) }
            return
        }
        state = .downloading
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "imagegenkit-update-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (tmp, resp) = try await URLSession.shared.download(from: asset)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Download failed") }
            let zip = work.appending(path: "update.zip")
            try fm.moveItem(at: tmp, to: zip)
            state = .installing
            guard await Shell.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, work.path]).status == 0
            else { throw UpdateError("Couldn't unzip") }
            guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw UpdateError("No app in the download") }
            try await verify(newApp)

            let current = Bundle.main.bundleURL
            let folder = current.deletingLastPathComponent()
            guard !current.path.contains("/AppTranslocation/") else { throw UpdateError("Move ImageGenKit to Applications first") }
            guard fm.isWritableFile(atPath: folder.path) else {
                throw UpdateError("Can’t replace the app here. Get it on GitHub.")
            }
            _ = await Shell.run(URL(fileURLWithPath: "/usr/bin/xattr"), ["-dr", "com.apple.quarantine", newApp.path])
            // Copy the new app next to the old one first (the temp folder can be on another volume), so the
            // swap below is a rename and the old app is only touched once the new one is complete.
            let staged = folder.appending(path: ".ImageGenKit-update-\(UUID().uuidString.prefix(8)).app")
            do { try fm.moveItem(at: newApp, to: staged) } catch {
                try? fm.removeItem(at: staged)
                throw UpdateError("Couldn't copy the update next to the app")
            }
            var trashed: NSURL?
            do { try fm.trashItem(at: current, resultingItemURL: &trashed) } catch {
                try? fm.removeItem(at: staged)
                throw error
            }
            do {
                try fm.moveItem(at: staged, to: current)
            } catch {
                if let trashed = trashed as URL? { try? fm.moveItem(at: trashed, to: current) }  // put the old one back
                try? fm.removeItem(at: staged)
                throw error
            }
            try? fm.removeItem(at: work)  // terminating below skips the defer
            relaunch(current)
        } catch {
            state = .failed((error as? UpdateError)?.message ?? error.localizedDescription)
        }
    }

    /// Same bundle id, valid signature, and the same Team ID as this copy when it has one.
    private func verify(_ app: URL) async throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("Not an ImageGenKit build")
        }
        // The zip itself must be newer (a mislabeled release asset must not downgrade the app).
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard Installer.compare(version, currentVersion) > 0 else { throw UpdateError("The download isn't a newer version") }
        let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
        guard await Shell.run(codesign, ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            throw UpdateError("Signature check failed")
        }
        let mine = await teamID(Bundle.main.bundleURL)
        if let mine, await teamID(app) != mine { throw UpdateError("Signed by someone else") }
    }

    private func teamID(_ app: URL) async -> String? {
        let r = await Shell.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["-dv", app.path])
        let line = (r.stderr + r.stdout).split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }
        let id = line.map { String($0.dropFirst("TeamIdentifier=".count)) }
        return id == "not set" ? nil : id
    }

    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait (up to 60 s) until this process has quit: `open` while it is still running would only
        // activate the old instance, which then quits and the update never starts.
        p.arguments = ["-c", "for i in $(seq 300); do /bin/kill -0 \"$1\" 2>/dev/null || break; sleep 0.2; done; /usr/bin/open \"$0\"",
                       app.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? p.run()
        NSApp.terminate(nil)
    }
}

private struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
