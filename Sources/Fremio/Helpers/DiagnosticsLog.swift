import Foundation
import Observation

/// App-wide diagnostics log. Every failure path in the app records here so the
/// user can inspect exactly what went wrong from Settings → Advanced Console.
///
/// The static `log`/`error`/`warning`/`info` entry points are `nonisolated`, so
/// they can be called from any thread or context (resolvers, URLSession delegate
/// callbacks, view code) without `await`. The actual store is `@MainActor` so
/// SwiftUI observes it cleanly. Entries are persisted to disk so failures from a
/// previous session (including ones just before a crash) survive relaunch.
@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    enum Level: String, Codable, CaseIterable, Sendable {
        case info
        case warning
        case error
    }

    struct Entry: Identifiable, Codable, Sendable {
        var id = UUID()
        let date: Date
        let level: Level
        let category: String
        let message: String
        let detail: String?
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 500
    private let fileName = "diagnostics_log.json"

    private init() {
        entries = load() ?? []
    }

    var errorCount: Int { entries.reduce(0) { $0 + ($1.level == .error ? 1 : 0) } }

    func append(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()

        // Optional automatic upload of errors to a user-configured endpoint.
        // NOTE: the uploader itself never logs (see `post`), so a failing upload
        // can't trigger another error that re-triggers an upload (no loop).
        if entry.level == .error, Self.autoSendEnabled, let endpoint = Self.remoteEndpoint {
            Task { _ = await Self.post(entries: [entry], to: endpoint) }
        }
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Non-isolated entry points (callable from anywhere)

    nonisolated static func log(_ level: Level, _ category: String, _ message: String, detail: String? = nil) {
        let entry = Entry(date: Date(), level: level, category: category, message: message, detail: detail)
        Task { @MainActor in shared.append(entry) }
        #if DEBUG
        print("[\(level.rawValue.uppercased())] \(category): \(message)" + (detail.map { " — \($0)" } ?? ""))
        #endif
    }

    nonisolated static func info(_ category: String, _ message: String, detail: String? = nil) {
        log(.info, category, message, detail: detail)
    }

    nonisolated static func warning(_ category: String, _ message: String, detail: String? = nil) {
        log(.warning, category, message, detail: detail)
    }

    nonisolated static func error(_ category: String, _ message: String, error: Error? = nil, detail: String? = nil) {
        var combined = detail
        if let error {
            let described = describe(error)
            combined = [detail, described].compactMap { $0 }.joined(separator: "\n")
        }
        log(.error, category, message, detail: combined)
    }

    /// Expands an error into every useful field we can pull off it.
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts: [String] = []
        parts.append("type: \(String(describing: Swift.type(of: error)))")
        parts.append("domain: \(ns.domain)  code: \(ns.code)")
        parts.append("description: \(ns.localizedDescription)")
        if let reason = ns.localizedFailureReason {
            parts.append("reason: \(reason)")
        }
        let extraUserInfo = ns.userInfo.filter { $0.key != NSLocalizedDescriptionKey }
        if !extraUserInfo.isEmpty {
            parts.append("userInfo: \(extraUserInfo)")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Remote reporting (user-configured endpoint)

    /// The HTTPS endpoint the log is POSTed to, if the user has set one in
    /// Settings. Any collector works (a self-hosted server, or a quick
    /// throwaway inbox like webhook.site).
    nonisolated static var remoteEndpoint: URL? {
        guard let raw = UserDefaults.standard.string(forKey: "diagnosticsEndpoint")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              (url.scheme == "http" || url.scheme == "https") else {
            return nil
        }
        return url
    }

    nonisolated static var autoSendEnabled: Bool {
        UserDefaults.standard.bool(forKey: "diagnosticsAutoSend")
    }

    private struct Payload: Codable {
        let generatedAt: Date
        let app: String
        let system: String
        let entries: [Entry]
    }

    /// Upload the entire current log. Returns whether the server accepted it.
    func uploadAll() async -> Bool {
        guard let endpoint = Self.remoteEndpoint else { return false }
        return await Self.post(entries: entries, to: endpoint)
    }

    /// Fire-and-forget POST of the given entries. Deliberately performs no
    /// logging of its own so a failed upload can't spawn more error entries.
    nonisolated static func post(entries: [Entry], to endpoint: URL) async -> Bool {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        let payload = Payload(
            generatedAt: Date(),
            app: "Fremio \(appVersion) (\(build))",
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let body = try? encoder.encode(payload) else { return false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await AppConfig.httpSession.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (200...299).contains(code)
        } catch {
            return false
        }
    }

    /// Full plain-text dump for the "Copy All" / share action.
    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries.map { entry -> String in
            var line = "[\(formatter.string(from: entry.date))] [\(entry.level.rawValue.uppercased())] \(entry.category): \(entry.message)"
            if let detail = entry.detail, !detail.isEmpty {
                line += "\n    " + detail.replacingOccurrences(of: "\n", with: "\n    ")
            }
            return line
        }.joined(separator: "\n\n")
    }

    // MARK: - Persistence

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent(fileName)
    }

    private func load() -> [Entry]? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Entry].self, from: data)
    }

    private func save() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
