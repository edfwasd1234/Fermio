import Foundation
import AVFoundation
import AVKit

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
            // Attempt resolving from independent Flux alternate server APIs directly!
            if let fallbackUrl = try? await resolveFromFluxFallback(type: type, tmdbId: tmdbId, season: season, episode: episode) {
                return fallbackUrl
            }
            // Fallback to Cineby.at API
            if let fallbackUrl = try? await resolveFromCinebyFallback(type: type, tmdbId: tmdbId, season: season, episode: episode) {
                return fallbackUrl
            }
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
    
    private func resolveFromFluxFallback(type: MediaType, tmdbId: String, season: Int, episode: Int) async throws -> URL {
        // 1. Fetch IMDb ID from TMDB
        guard let imdbId = await fetchImdbId(tmdbId: tmdbId, type: type) else {
            throw NSError(domain: "StreamResolver", code: 5, userInfo: [NSLocalizedDescriptionKey: "IMDb ID not found"])
        }
        
        // 2. Query Flux 1 direct API (streamdata.vaplayer.ru)
        let typeString = type == .movie ? "movie" : "tv"
        var urlString = "https://streamdata.vaplayer.ru/api.php?imdb=\(imdbId)&type=\(typeString)"
        if type == .show {
            urlString += "&season=\(season)&episode=\(episode)"
        }
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://nextgencloudfabric.com/", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["data"] as? [String: Any],
              let streamUrls = responseData["stream_urls"] as? [String],
              let firstStreamUrl = streamUrls.first else {
            throw NSError(domain: "StreamResolver", code: 6, userInfo: [NSLocalizedDescriptionKey: "No streams found in Flux 1 alternate API"])
        }
        
        // 3. Route through vlaq11.site proxy (like primary streams)
        let encodedVideoUrl = encodeURIComponent(firstStreamUrl)
        let finalStreamString = "https://vlaq11.site/\(encodedVideoUrl)"
        
        guard let finalUrl = URL(string: finalStreamString) else {
            throw URLError(.badURL)
        }
        
        return finalUrl
    }
    
    private func resolveFromCinebyFallback(type: MediaType, tmdbId: String, season: Int, episode: Int) async throws -> URL {
        guard let details = await fetchTMDBDetails(tmdbId: tmdbId, type: type) else {
            throw NSError(domain: "StreamResolver", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch TMDb details"])
        }
        
        guard let seedUrl = URL(string: "https://api.wingsdatabase.com/seed?mediaId=\(tmdbId)") else {
            throw URLError(.badURL)
        }
        
        var seedRequest = URLRequest(url: seedUrl)
        seedRequest.setValue("https://www.cineby.at/", forHTTPHeaderField: "Referer")
        seedRequest.setValue("https://www.cineby.at", forHTTPHeaderField: "Origin")
        seedRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (seedData, _) = try await URLSession.shared.data(for: seedRequest)
        guard let seedJson = try? JSONSerialization.jsonObject(with: seedData) as? [String: Any],
              let seed = seedJson["seed"] as? String else {
            throw NSError(domain: "StreamResolver", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch seed from wingsdatabase"])
        }
        
        let inputToHash = "\(tmdbId)486ae1ce6fdbe63b60bd1704541fcf0"
        let hashValue = cHash(inputToHash)
        let hashids = Hashids()
        let b35ebba4 = hashids.encodeHex(hashValue)
        
        let encodedTitle = encodeURIComponent(details.title)
        let typeString = type == .movie ? "movie" : "tv"
        let sourcesUrlString = "https://api.wingsdatabase.com/mbx/sources-with-title?title=\(encodedTitle)&mediaType=\(typeString)&year=\(details.year)&totalSeasons=\(details.totalSeasons)&episodeId=\(episode)&seasonId=\(season)&tmdbId=\(tmdbId)&imdbId=\(details.imdbId)&enc=2&seed=\(seed)&b35ebba4=\(b35ebba4)"
        
        guard let sourcesUrl = URL(string: sourcesUrlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: sourcesUrl)
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")
        request.setValue("\"Not A(BiT;KB\";v=\"99\", \"Chromium\";v=\"121\"", forHTTPHeaderField: "sec-ch-ua")
        request.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue("\"Windows\"", forHTTPHeaderField: "sec-ch-ua-platform")
        request.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("cross-site", forHTTPHeaderField: "sec-fetch-site")
        request.setValue("https://www.cineby.at/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.cineby.at", forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (sourcesData, _) = try await URLSession.shared.data(for: request)
        
        guard let encryptedBase64 = String(data: sourcesData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !encryptedBase64.isEmpty else {
            throw NSError(domain: "StreamResolver", code: 12, userInfo: [NSLocalizedDescriptionKey: "Empty response from wingsdatabase"])
        }
        
        let decryptedJsonString: String
        do {
            decryptedJsonString = try CinebyDecrypter.decrypt(encryptedBase64: encryptedBase64, seed: seed, mediaId: Int(tmdbId) ?? 0)
        } catch {
            if let plainJson = try? JSONSerialization.jsonObject(with: sourcesData) as? [String: Any],
               let sources = plainJson["sources"] as? [[String: Any]], sources.isEmpty {
                throw NSError(domain: "StreamResolver", code: 13, userInfo: [NSLocalizedDescriptionKey: "No sources found on Cineby fallback"])
            }
            throw error
        }
        
        guard let decryptedData = decryptedJsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
              let sources = json["sources"] as? [[String: Any]] else {
            throw NSError(domain: "StreamResolver", code: 14, userInfo: [NSLocalizedDescriptionKey: "Failed to parse decrypted sources JSON"])
        }
        
        var mp4UrlString: String? = nil
        for source in sources {
            if let fileUrl = source["file"] as? String, !fileUrl.isEmpty {
                if fileUrl.contains("/mp4/") || fileUrl.lowercased().hasSuffix(".mp4") || (source["type"] as? String)?.lowercased() == "mp4" {
                    mp4UrlString = fileUrl
                    break
                }
            }
        }
        
        guard let finalRawUrl = mp4UrlString else {
            throw NSError(domain: "StreamResolver", code: 15, userInfo: [NSLocalizedDescriptionKey: "No MP4 stream found on Cineby fallback"])
        }
        
        let encodedVideoUrl = encodeURIComponent(finalRawUrl)
        let finalStreamString = "https://vlaq11.site/\(encodedVideoUrl)"
        
        guard let finalUrl = URL(string: finalStreamString) else {
            throw URLError(.badURL)
        }
        
        return finalUrl
    }
    
    private func cHash(_ input: String) -> String {
        let keyXor = 95
        return input.compactMap { $0.asciiValue }
            .map { String(format: "%02x", Int($0) ^ keyXor) }
            .joined()
    }
    
    struct TMDBMovieData {
        let title: String
        let year: Int
        let imdbId: String
        let totalSeasons: Int
    }
    
    private func fetchTMDBDetails(tmdbId: String, type: MediaType) async -> TMDBMovieData? {
        let apiKey = UserDefaults.standard.string(forKey: "tmdbApiKey") ?? "3d421899d5ce93db8ad4ae4591ccc130"
        let path = type == .movie ? "movie/\(tmdbId)" : "tv/\(tmdbId)"
        let urlString = "https://api.themoviedb.org/3/\(path)?api_key=\(apiKey)&append_to_response=external_ids"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let title = (json["title"] as? String) ?? (json["name"] as? String) ?? (json["original_title"] as? String) ?? ""
                
                let dateStr = (type == .movie ? json["release_date"] as? String : json["first_air_date"] as? String) ?? ""
                let year: Int
                if let firstPart = dateStr.split(separator: "-").first, let parsedYear = Int(firstPart) {
                    year = parsedYear
                } else {
                    year = 2000
                }
                
                let imdbId = (json["imdb_id"] as? String) ?? ((json["external_ids"] as? [String: Any])?["imdb_id"] as? String) ?? ""
                let totalSeasons = (json["number_of_seasons"] as? Int) ?? 0
                
                return TMDBMovieData(title: title, year: year, imdbId: imdbId, totalSeasons: totalSeasons)
            }
        } catch {
            print("Failed to fetch TMDB details for \(tmdbId): \(error)")
        }
        return nil
    }
    
    private func fetchImdbId(tmdbId: String, type: MediaType) async -> String? {
        let apiKey = UserDefaults.standard.string(forKey: "tmdbApiKey") ?? "3d421899d5ce93db8ad4ae4591ccc130"
        let urlString: String
        if type == .movie {
            urlString = "https://api.themoviedb.org/3/movie/\(tmdbId)?api_key=\(apiKey)"
        } else {
            urlString = "https://api.themoviedb.org/3/tv/\(tmdbId)/external_ids?api_key=\(apiKey)"
        }
        
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json["imdb_id"] as? String
            }
        } catch {
            print("Failed to fetch IMDb ID: \(error)")
        }
        return nil
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
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }
    
    private func getFinalStreamUrl(from url: URL, referer: String) async -> (url: URL, referer: String) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        
        class RedirectHandler: NSObject, URLSessionTaskDelegate {
            func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
                completionHandler(nil)
            }
        }
        
        let session = URLSession(configuration: .default, delegate: RedirectHandler(), delegateQueue: nil)
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (httpResponse.statusCode == 302 || httpResponse.statusCode == 301),
               let locationStr = httpResponse.allHeaderFields["Location"] as? String ?? httpResponse.allHeaderFields["location"] as? String,
               let locationUrl = URL(string: locationStr) {
                
                if locationStr.contains("//.wcostream.com") {
                    return (url, referer)
                }
                
                return (locationUrl, referer)
            }
        } catch {
            print("Failed to pre-resolve stream redirect: \(error)")
        }
        
        return (url, referer)
    }
    
    /// Resolves an Anime to a player item with native Subbed (Japanese) and Dubbed (English) audio tracks.
    func resolveAnimeComposition(title: String, season: Int, episode: Int) async throws -> AVPlayerItem {
        let streams = try await WCOTVResolver.shared.resolveAnimeStreams(title: title, season: season, episode: episode)
        
        let subbedOption = streams.filter { $0.language == "Subbed" }.sorted(by: { $0.quality > $1.quality }).first
        let dubbedOption = streams.filter { $0.language == "Dubbed" }.sorted(by: { $0.quality > $1.quality }).first
        
        guard let subbed = subbedOption else {
            if let dubbed = dubbedOption {
                let (resolvedUrl, resolvedReferer) = await getFinalStreamUrl(from: dubbed.url, referer: dubbed.referer)
                let headers: [String: String] = [
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                    "Referer": resolvedReferer
                ]
                let asset = AVURLAsset(url: resolvedUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                return AVPlayerItem(asset: asset)
            }
            throw NSError(domain: "StreamResolver", code: 20, userInfo: [NSLocalizedDescriptionKey: "No streams found for this anime episode on WCO.tv"])
        }
        
        let (subbedUrl, subbedReferer) = await getFinalStreamUrl(from: subbed.url, referer: subbed.referer)
        let subbedHeaders: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Referer": subbedReferer
        ]
        let subbedAsset = AVURLAsset(url: subbedUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": subbedHeaders])
        
        guard let dubbed = dubbedOption else {
            return AVPlayerItem(asset: subbedAsset)
        }
        
        let (dubbedUrl, dubbedReferer) = await getFinalStreamUrl(from: dubbed.url, referer: dubbed.referer)
        let dubbedHeaders: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Referer": dubbedReferer
        ]
        let dubbedAsset = AVURLAsset(url: dubbedUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": dubbedHeaders])
        
        let composition = AVMutableComposition()
        
        // Load properties synchronously to maximize compatibility across compiler versions
        let subbedTracks = subbedAsset.tracks
        let dubbedTracks = dubbedAsset.tracks
        let duration = subbedAsset.duration
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        
        // Add Video Track (from Subbed video)
        if let subbedVideo = subbedTracks.first(where: { $0.mediaType == .video }),
           let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compVideo.insertTimeRange(timeRange, of: subbedVideo, at: .zero)
        }
        
        // Add Subbed (Japanese) Audio Track
        if let subbedAudio = subbedTracks.first(where: { $0.mediaType == .audio }),
           let compAudio1 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compAudio1.insertTimeRange(timeRange, of: subbedAudio, at: .zero)
            compAudio1.extendedLanguageTag = "ja-JP"
        }
        
        // Add Dubbed (English) Audio Track
        if let dubbedAudio = dubbedTracks.first(where: { $0.mediaType == .audio }),
           let compAudio2 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let dubbedDuration = dubbedAsset.duration
            let dubbedTimeRange = CMTimeRange(start: .zero, duration: dubbedDuration)
            try compAudio2.insertTimeRange(dubbedTimeRange, of: dubbedAudio, at: .zero)
            compAudio2.extendedLanguageTag = "en-US"
        }
        
        return AVPlayerItem(asset: composition)
    }
}
