import AppKit
import Security

/// Downloads a release, checks that it is genuinely a newer copy of this same app, and swaps
/// it in place.
///
/// TLS proves the bytes came from GitHub, not that they are trustworthy — an account or token
/// compromise would serve a signed-looking download over a perfectly good HTTPS connection.
/// The signature check below is what actually gates the install: the update must be signed by
/// the same Developer ID team as the copy already running, and must satisfy Gatekeeper, which
/// means Apple notarized it.
enum UpdateInstaller {
    /// Downloads and installs `release`, then relaunches. Does not return on success.
    static func installAndRelaunch(_ release: GitHubRelease) async throws {
        let installedApp = Bundle.main.bundleURL
        guard installedApp.pathExtension == "app" else { throw UpdateError.notAnAppBundle }

        let container = installedApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: container.path) else {
            throw UpdateError.notWritable(installedApp)
        }

        // A staging directory on the same volume as the app, so the final swap is a rename
        // rather than a copy.
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installedApp,
            create: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let archive = try await download(release.archiveURL, into: staging)
        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try run(
            "/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path],
            as: UpdateError.unpackFailed)

        guard let newApp = try appBundle(in: unpacked) else {
            throw UpdateError.appMissingFromArchive
        }

        try verifySignature(of: newApp)
        try verifyGatekeeper(newApp)

        // The archive came from the internet, so everything in it carries a quarantine flag.
        // Clearing it keeps macOS from re-litigating an update we have already verified.
        _ = try? run("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", newApp.path], as: nil)

        _ = try FileManager.default.replaceItemAt(installedApp, withItemAt: newApp)
        try await relaunch(installedApp)
    }

    // MARK: - Download

    private static func download(_ url: URL, into directory: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("LangKeys/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120

        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.badResponse(http.statusCode)
        }
        let destination = directory.appendingPathComponent("LangKeys.zip")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// The zip holds LangKeys.app, either at the top level or one directory down.
    private static func appBundle(in directory: URL) throws -> URL? {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        if let app = entries.first(where: { $0.pathExtension == "app" }) { return app }
        for entry in entries {
            let nested = try FileManager.default.contentsOfDirectory(
                at: entry, includingPropertiesForKeys: nil)
            if let app = nested.first(where: { $0.pathExtension == "app" }) { return app }
        }
        return nil
    }

    // MARK: - Verification

    /// The Developer ID team of the running app. Nil for an ad-hoc signature, i.e. a local
    /// `./build.sh` build, which has no identity to match an update against.
    private static func runningTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        // SecCodeCopySigningInformation takes a static code; a dynamic one is accepted here
        // and is how you ask the running process about its own signature.
        let status = SecCodeCopySigningInformation(
            unsafeBitCast(code, to: SecStaticCode.self),
            SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess,
            let dictionary = info as? [String: Any],
            let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        else { return nil }
        return team
    }

    private static func verifySignature(of app: URL) throws {
        guard let team = runningTeamIdentifier() else { throw UpdateError.hostNotSigned }
        let identifier = Bundle.main.bundleIdentifier ?? "so.dou.langkeys"

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else {
            throw UpdateError.signatureRejected("The bundle carries no signature.")
        }

        // Apple's own anchor, the same bundle identifier, the same team, and a leaf issued
        // under the Developer ID CA — an update signed by anyone else fails to match.
        let text = """
            anchor apple generic \
            and identifier "\(identifier)" \
            and certificate leaf[subject.OU] = "\(team)" \
            and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
            """
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess
        else {
            throw UpdateError.signatureRejected("The signing requirement could not be built.")
        }

        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var error: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &error)
        guard status == errSecSuccess else {
            let message =
                (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String }
                ?? "OSStatus \(status)"
            throw UpdateError.signatureRejected(message)
        }
    }

    /// Gatekeeper's own assessment, which is what confirms the download was notarized. The
    /// ticket is stapled into the bundle, so this holds up with no network.
    private static func verifyGatekeeper(_ app: URL) throws {
        try run("/usr/sbin/spctl", ["--assess", "--type", "exec", app.path]) {
            UpdateError.gatekeeperRejected($0)
        }
    }

    // MARK: - Relaunch

    @MainActor
    private static func relaunch(_ app: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        // Without this, LaunchServices would just reactivate the process about to quit.
        configuration.createsNewApplicationInstance = true
        try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        NSApp.terminate(nil)
    }

    // MARK: - Subprocesses

    @discardableResult
    private static func run(
        _ launchPath: String, _ arguments: [String], as failure: ((String) -> UpdateError)?
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        if process.terminationStatus != 0, let failure {
            throw failure(text.isEmpty ? "\(launchPath) exited \(process.terminationStatus)" : text)
        }
        return text
    }
}
