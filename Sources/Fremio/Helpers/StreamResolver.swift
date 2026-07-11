import Foundation

final class StreamResolver: Sendable {
    static let shared = StreamResolver()
    
    private init() {}
    
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let origin = "https://vidvault.ru"
    private let referer = "https://vidvault.ru/"
    
    /// Resolves a TMDB ID to a direct MP4 streaming URL proxied via vlaq11.site.
    /// - Parameters:
    ///   - type: The media type (.movie or .show)
    ///   - tmdbId: The TMDB ID string
    ///   - season: The season number (default is 1)
    ///   - episode: The episode number (default is 1)
    /// - Returns: A URL for the direct proxy stream
    func resolveStream(type: MediaType, tmdbId: String, season: Int = 1, episode: Int = 1) async throws -> URL {
        // 1. Fetch token from get-token
        guard let tokenUrl = URL(string: "https://vidvault.ru/api/get-token") else {
            throw URLError(.badURL)
        }
        
        var tokenRequest = URLRequest(url: tokenUrl)
        tokenRequest.httpMethod = "GET"
        tokenRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        tokenRequest.setValue(origin, forHTTPHeaderField: "Origin")
        tokenRequest.setValue(referer, forHTTPHeaderField: "Referer")
        
        let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
        
        guard let httpTokenResponse = tokenResponse as? HTTPURLResponse, httpTokenResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let tokenJson = try? JSONSerialization.jsonObject(with: tokenData, options: []) as? [String: Any],
              let token = tokenJson["t"] as? String else {
            throw NSError(domain: "StreamResolver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse token"])
        }
        
        // 2. Query download proxy with TMDB ID
        guard let proxyUrl = URL(string: "https://vidvault.ru/api/download-proxy") else {
            throw URLError(.badURL)
        }
        
        let tmdbIdInt = Int(tmdbId) ?? 0
        let payload: [String: Any] = [
            "type": type == .movie ? "movie" : "tv",
            "tmdbId": tmdbIdInt,
            "season": season,
            "episode": episode
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        var proxyRequest = URLRequest(url: proxyUrl)
        proxyRequest.httpMethod = "POST"
        proxyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        proxyRequest.setValue(token, forHTTPHeaderField: "x-request-token")
        proxyRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        proxyRequest.setValue(origin, forHTTPHeaderField: "Origin")
        proxyRequest.setValue(referer, forHTTPHeaderField: "Referer")
        proxyRequest.httpBody = bodyData
        
        let (proxyData, proxyResponse) = try await URLSession.shared.data(for: proxyRequest)
        
        guard let httpProxyResponse = proxyResponse as? HTTPURLResponse, httpProxyResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: proxyData, options: []) as? [String: Any] else {
            throw NSError(domain: "StreamResolver", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse proxy response"])
        }
        
        // Traverse nested dictionary for Flux 1 (mp4Data), Flux 2 (mkvV2Data/mkvData), and Flux 3 (mkvV3Data)
        var flux1Entries: [(url: String, resolution: Int)] = []
        if let mp4Data = json["mp4Data"] as? [String: Any] {
            let downloadInfo = (mp4Data["downloadInfo"] as? [String: Any]) ?? (mp4Data["data"] as? [String: Any]) ?? mp4Data
            let dataField = (downloadInfo["data"] as? [String: Any]) ?? downloadInfo
            
            let sourceList = (dataField["downloads"] as? [[String: Any]]) ?? (dataField["streams"] as? [[String: Any]])
            if let entries = sourceList {
                for entry in entries {
                    if let rawUrl = entry["url"] as? String, !rawUrl.isEmpty {
                        let resVal = parseResolution(entry["resolution"])
                        flux1Entries.append((rawUrl, resVal))
                    }
                }
            }
        }
        
        // Try Flux 2 (mkvV2Data or mkvData)
        var flux2Entries: [(url: String, resolution: Int)] = []
        let mkvKeys = ["mkvV2Data", "mkvData"]
        for key in mkvKeys {
            if let mkvVal = json[key] {
                if let mkvArray = mkvVal as? [[String: Any]] {
                    for entry in mkvArray {
                        if let url = entry["url"] as? String, !url.isEmpty {
                            let resVal = parseResolution(entry["quality"] ?? entry["resolution"])
                            flux2Entries.append((url, resVal))
                        }
                    }
                } else if let mkvDict = mkvVal as? [String: Any] {
                    if let files = mkvDict["files"] as? [[String: Any]] {
                        for file in files {
                            if let url = file["url"] as? String, !url.isEmpty {
                                let resVal = parseResolution(file["quality"] ?? file["resolution"])
                                flux2Entries.append((url, resVal))
                            }
                        }
                    } else if let url = mkvDict["url"] as? String, !url.isEmpty {
                        let resVal = parseResolution(mkvDict["quality"] ?? mkvDict["resolution"])
                        flux2Entries.append((url, resVal))
                    }
                }
            }
        }
        
        // Try Flux 3 (mkvV3Data)
        var flux3Entries: [(url: String, resolution: Int)] = []
        if let mkvV3Data = json["mkvV3Data"] as? [String: Any] {
            if let downloads = mkvV3Data["downloads"] as? [[String: Any]] {
                for download in downloads {
                    if let qualities = download["qualities"] as? [[String: Any]] {
                        for quality in qualities {
                            let resVal = parseResolution(quality["quality"] ?? quality["resolution"])
                            if let episodes = quality["episodes"] as? [[String: Any]] {
                                for episodeEntry in episodes {
                                    if let url = episodeEntry["url"] as? String, !url.isEmpty {
                                        flux3Entries.append((url, resVal))
                                    }
                                }
                            }
                        }
                    } else if let url = download["url"] as? String, !url.isEmpty {
                        let resVal = parseResolution(download["quality"] ?? download["resolution"])
                        flux3Entries.append((url, resVal))
                    }
                }
            }
        }
        
        // Select first available server in order: Flux 1 -> Flux 2 -> Flux 3
        var selectedEntry: (url: String, resolution: Int)? = nil
        if !flux1Entries.isEmpty {
            selectedEntry = flux1Entries.sorted(by: { $0.resolution > $1.resolution }).first
        } else if !flux2Entries.isEmpty {
            selectedEntry = flux2Entries.sorted(by: { $0.resolution > $1.resolution }).first
        } else if !flux3Entries.isEmpty {
            selectedEntry = flux3Entries.sorted(by: { $0.resolution > $1.resolution }).first
        }
        
        guard let finalRawUrl = selectedEntry?.url else {
            throw NSError(domain: "StreamResolver", code: 4, userInfo: [NSLocalizedDescriptionKey: "not found, please wait a little more for our team to put it on here."])
        }
        
        // 3. Construct proxy URL through vlaq11.site (mimicking encodeURIComponent)
        let encodedVideoUrl = encodeURIComponent(finalRawUrl)
        let finalStreamString = "https://vlaq11.site/\(encodedVideoUrl)"
        
        guard let finalUrl = URL(string: finalStreamString) else {
            throw URLError(.badURL)
        }
        
        return finalUrl
    }
    
    private func parseResolution(_ value: Any?) -> Int {
        if let intRes = value as? Int {
            return intRes
        } else if let strRes = value as? String, let intRes = Int(strRes.filter(\.isNumber)) {
            return intRes
        }
        return 0
    }
    
    private func encodeURIComponent(_ string: String) -> String {
        // Mimic JavaScript encodeURIComponent by escaping all non-alphanumeric and non-standard symbols
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }
}
