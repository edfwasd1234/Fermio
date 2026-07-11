import Foundation

class StreamResolver {
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
        
        // Traverse nested dictionary robustly
        let mp4Data = json["mp4Data"] as? [String: Any]
        let downloadInfo = (mp4Data?["downloadInfo"] as? [String: Any]) ?? (mp4Data?["data"] as? [String: Any]) ?? mp4Data
        let dataField = (downloadInfo?["data"] as? [String: Any]) ?? downloadInfo
        
        guard let downloads = dataField?["downloads"] as? [[String: Any]], !downloads.isEmpty else {
            throw NSError(domain: "StreamResolver", code: 3, userInfo: [NSLocalizedDescriptionKey: "No video downloads available"])
        }
        
        // Filter and sort downloads by resolution descending to get highest quality first
        let parsedEntries: [(url: String, resolution: Int)] = downloads.compactMap { entry in
            guard let rawUrl = entry["url"] as? String, !rawUrl.isEmpty else { return nil }
            let format = entry["format"] as? String ?? "MP4"
            guard format.uppercased() == "MP4" else { return nil }
            
            let resVal: Int
            if let intRes = entry["resolution"] as? Int {
                resVal = intRes
            } else if let strRes = entry["resolution"] as? String, let intRes = Int(strRes.filter(\.isNumber)) {
                resVal = intRes
            } else {
                resVal = 0
            }
            return (rawUrl, resVal)
        }
        
        guard let selectedEntry = parsedEntries.sorted(by: { $0.resolution > $1.resolution }).first else {
            throw NSError(domain: "StreamResolver", code: 4, userInfo: [NSLocalizedDescriptionKey: "No suitable MP4 stream found"])
        }
        
        // 3. Construct proxy URL through vlaq11.site (mimicking encodeURIComponent)
        let encodedVideoUrl = encodeURIComponent(selectedEntry.url)
        let finalStreamString = "https://vlaq11.site/\(encodedVideoUrl)"
        
        guard let finalUrl = URL(string: finalStreamString) else {
            throw URLError(.badURL)
        }
        
        return finalUrl
    }
    
    private func encodeURIComponent(_ string: String) -> String {
        // Mimic JavaScript encodeURIComponent by escaping all non-alphanumeric and non-standard symbols
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }
}
