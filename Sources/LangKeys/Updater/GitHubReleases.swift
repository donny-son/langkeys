import Foundation

/// A published release that carries an asset this app can install.
struct GitHubRelease {
    let version: AppVersion
    /// Markdown release notes, shown as plain text in the update prompt.
    let notes: String
    let pageURL: URL
    let archiveURL: URL
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case noReleaseAsset(String)
    case unreadableVersion(String)
    case notAnAppBundle
    case notWritable(URL)
    case unpackFailed(String)
    case appMissingFromArchive
    case hostNotSigned
    case signatureRejected(String)
    case gatekeeperRejected(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "GitHub replied with HTTP \(code)."
        case .noReleaseAsset(let tag):
            return "Release \(tag) has no downloadable app archive."
        case .unreadableVersion(let tag):
            return "Could not read a version number out of the tag “\(tag)”."
        case .notAnAppBundle:
            return "LangKeys is not running from an .app bundle, so it cannot update itself."
        case .notWritable(let url):
            return "No permission to replace \(url.path). Move LangKeys to /Applications, or "
                + "download the update yourself."
        case .unpackFailed(let message):
            return "The download could not be unpacked. \(message)"
        case .appMissingFromArchive:
            return "The download did not contain LangKeys.app."
        case .hostNotSigned:
            return "This build of LangKeys is ad-hoc signed (a local build), so an update "
                + "cannot be verified against it. Install a release build to get updates."
        case .signatureRejected(let message):
            return "The downloaded update is not signed by the same developer as this copy of "
                + "LangKeys, so it was discarded. \(message)"
        case .gatekeeperRejected(let message):
            return "macOS refused the downloaded update. \(message)"
        }
    }
}

/// The releases feed. Unauthenticated GitHub API calls are limited to 60 an hour per IP,
/// which a once-a-day check never comes close to.
enum GitHubReleases {
    static let repository = "donny-son/langkeys"

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(repository)/releases/latest")!
    }

    static func latest() async throws -> GitHubRelease {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects API calls without a User-Agent.
        request.setValue("LangKeys/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.badResponse(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(Payload.self, from: data)

        guard let version = AppVersion(payload.tagName) else {
            throw UpdateError.unreadableVersion(payload.tagName)
        }
        // The DMG is for people dragging it to /Applications by hand; the updater wants the
        // zip, which unpacks without mounting anything.
        guard
            let asset = payload.assets.first(where: {
                $0.name.hasSuffix(".zip") && $0.name.localizedCaseInsensitiveContains("langkeys")
            }),
            let archiveURL = URL(string: asset.browserDownloadUrl)
        else {
            throw UpdateError.noReleaseAsset(payload.tagName)
        }

        return GitHubRelease(
            version: version,
            notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            pageURL: URL(string: payload.htmlUrl) ?? releasesPageURL,
            archiveURL: archiveURL)
    }

    // MARK: - Wire format

    private struct Payload: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
    }
}
