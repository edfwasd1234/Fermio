import Foundation

/// Client for the FerAnime resolver backend's `/api/resolve` endpoint, which
/// searches a ranked list of sources (wcotv → animegg → animeheaven → anizone)
/// and returns the first directly-playable stream. Used for the WCO.tv-style
/// anime/cartoon server, replacing the native path that Cloudflare now blocks.
enum BackendResolver {

    private struct ResolveResponse: Codable {
        let ok: Bool
        let source: String?
        let matched: String?
        let language: String?
        let streams: [Stream]?
        let tried: [Tried]?
    }

    private struct Stream: Codable {
        let quality: String?
        let label: String?
        let type: String?
        let url: String
        let headers: [String: String]?
    }

    private struct Tried: Codable {
        let src: String
        let ok: Bool?
        let reason: String?
    }

    /// Resolves playable stream options via the backend. Returns options mapped
    /// into `WCOTVStreamOption` so they flow through the player's existing
    /// quality/language picker and auto-fallback machinery.
    static func resolve(title: String, season: Int, episode: Int, dub: Bool) async throws -> [WCOTVStreamOption] {
        guard let base = AppConfig.resolverBackendURL else {
            throw NSError(domain: "BackendResolver", code: 1, userInfo: [NSLocalizedDescriptionKey: "No resolver backend URL set. Add one in Settings → Streaming Backend."])
        }

        var components = URLComponents(url: base.appendingPathComponent("api").appendingPathComponent("resolve"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "episode", value: String(episode)),
            URLQueryItem(name: "dub", value: dub ? "1" : "0")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await AppConfig.httpSession.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        let decoded: ResolveResponse
        do {
            decoded = try JSONDecoder().decode(ResolveResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            DiagnosticsLog.error("Backend", "Bad response from resolver (HTTP \(status))", error: error, detail: "url: \(url.absoluteString)\nbody: \(body)")
            throw error
        }

        guard decoded.ok, let streams = decoded.streams, !streams.isEmpty else {
            let triedSummary = (decoded.tried ?? []).map { "\($0.src): \($0.ok == true ? "ok" : ($0.reason ?? "failed"))" }.joined(separator: "\n")
            DiagnosticsLog.error("Backend", "No source could resolve \(title)", detail: "S\(season)E\(episode) dub=\(dub)\ntried:\n\(triedSummary)")
            throw NSError(domain: "BackendResolver", code: 2, userInfo: [NSLocalizedDescriptionKey: "No source had this title. Tried: \((decoded.tried ?? []).map { $0.src }.joined(separator: ", "))."])
        }

        let language = decoded.language ?? (dub ? "Dubbed" : "Subbed")
        let options: [WCOTVStreamOption] = streams.compactMap { stream in
            let type = (stream.type ?? "").lowercased()
            // Only direct-playable stream types; skip iframe/embed players.
            guard type == "mp4" || type == "hls" || type == "" else { return nil }
            guard let streamURL = URL(string: stream.url) else { return nil }
            let quality = stream.quality ?? stream.label ?? "auto"
            let referer = stream.headers?["Referer"] ?? stream.headers?["referer"] ?? ""
            return WCOTVStreamOption(url: streamURL, referer: referer, language: language, quality: quality)
        }

        if options.isEmpty {
            DiagnosticsLog.error("Backend", "Resolver returned only non-playable (embed) streams for \(title)", detail: "source: \(decoded.source ?? "?")")
            throw NSError(domain: "BackendResolver", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only embed streams were available, which can't be played directly."])
        }

        DiagnosticsLog.info("Backend", "Resolved \(title) S\(season)E\(episode) via \(decoded.source ?? "?")", detail: "matched: \(decoded.matched ?? "?")  options: \(options.count)")
        return options
    }
}
