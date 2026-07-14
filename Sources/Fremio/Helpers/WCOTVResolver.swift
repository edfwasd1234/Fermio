import Foundation

struct WCOTVStreamOption: Identifiable, Codable {
    var id: String { language + "-" + quality }
    let url: URL
    let referer: String
    let language: String // "Subbed" or "Dubbed"
    let quality: String // "1080p", "720p", "480p"
}

struct WCOTVResponse: Codable {
    let enc: String?
    let hd: String?
    let fhd: String?
    let server: String?
    let cdn: String?
}

final class WCOTVResolver: Sendable {
    static let shared = WCOTVResolver()
    private init() {}
    
    private let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"
    private let baseUrl = "https://www.wco.tv"
    
    func resolveAnimeStreams(title: String, season: Int, episode: Int) async throws -> [WCOTVStreamOption] {
        // 1. Search for show slugs
        let showSlugs = await searchAnimeSlugs(title: title)
        
        var allSlugs = showSlugs
        if allSlugs.isEmpty {
            // Fallback slug generation
            let fallback = title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
            allSlugs = [fallback, "\(fallback)-dubbed", "\(fallback)-subbed", "\(fallback)-english-dubbed"]
        }
        
        // 2. Fetch episode page URLs (Sub vs Dub) from all matching show slugs
        var allLinkInfos: [WCOTVLinkInfo] = []
        for slug in allSlugs {
            let linkInfos = await fetchEpisodeUrls(showSlug: slug, episodeNumber: episode)
            allLinkInfos.append(contentsOf: linkInfos)
        }
        
        // 3. Extract streams for each available option
        var allStreams: [WCOTVStreamOption] = []
        for info in allLinkInfos {
            let streams = await extractStreams(episodePageUrlString: info.url, lang: info.lang)
            allStreams.append(contentsOf: streams)
        }
        
        return allStreams
    }
    
    private func searchAnimeSlugs(title: String) async -> [String] {
        guard let searchUrl = URL(string: "https://www.wco.tv/search") else { return [] }
        var request = URLRequest(url: searchUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://www.wco.tv/", forHTTPHeaderField: "Referer")
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        
        let postData = "catara=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title)&konuara=series"
        request.httpBody = postData.data(using: .utf8)
        
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        
        // Match anime slugs /anime/([^/"'\s]+)
        guard let regex = try? NSRegularExpression(pattern: "/anime/([^/\"'\\s]+)", options: []) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        
        var slugs: [String] = []
        var seen = Set<String>()
        for match in matches {
            if let range = Range(match.range(at: 1), in: html) {
                let slug = String(html[range]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !seen.contains(slug) {
                    seen.insert(slug)
                    slugs.append(slug)
                }
            }
        }
        return Array(slugs.prefix(6))
    }
    
    struct WCOTVLinkInfo {
        let url: String
        let lang: String
    }
    
    private func fetchEpisodeUrls(showSlug: String, episodeNumber: Int) async -> [WCOTVLinkInfo] {
        guard let url = URL(string: "https://www.wco.tv/anime/\(showSlug)/") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        
        guard let regex = try? NSRegularExpression(pattern: "<a\\s+href=[\"']([^\"']+)[\"'][^>]*>([^<]*)", options: []) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        
        var options: [WCOTVLinkInfo] = []
        
        for match in matches {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { continue }
            let href = String(html[hrefRange])
            let text = String(html[textRange])
            
            let combined = "\(href.lowercased()) \(text.lowercased())"
            guard combined.contains("episode") else { continue }
            
            // Numerical check for episode number to handle leading zeros (e.g. 01 matching 1)
            var parsedEpisodeNum: Double? = nil
            if let epRegex = try? NSRegularExpression(pattern: "episode[- ]?(\\d+(?:\\.\\d+)?)", options: [.caseInsensitive]) {
                let nsCombined = NSRange(combined.startIndex..<combined.endIndex, in: combined)
                if let match = epRegex.firstMatch(in: combined, options: [], range: nsCombined),
                   let range = Range(match.range(at: 1), in: combined),
                   let num = Double(combined[range]) {
                    parsedEpisodeNum = num
                }
            }
            
            if parsedEpisodeNum == nil {
                if let numRegex = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)", options: []) {
                    let nsText = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = numRegex.firstMatch(in: text, options: [], range: nsText),
                       let range = Range(match.range(at: 1), in: text),
                       let num = Double(text[range]) {
                        parsedEpisodeNum = num
                    }
                }
            }
            
            if let parsedNum = parsedEpisodeNum, abs(parsedNum - Double(episodeNumber)) < 0.01 {
                let isDub = combined.contains("dub") || combined.contains("dubbed")
                let lang = isDub ? "Dubbed" : "Subbed"
                options.append(WCOTVLinkInfo(url: href, lang: lang))
            }
        }
        return options
    }
    
    private func extractStreams(episodePageUrlString: String, lang: String) async -> [WCOTVStreamOption] {
        var pageUrlStr = episodePageUrlString
        if !pageUrlStr.hasPrefix("http") {
            pageUrlStr = "https://www.wco.tv/" + pageUrlStr.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard let url = URL(string: pageUrlStr) else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.wco.tv/", forHTTPHeaderField: "Referer")
        
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        
        guard let pmx = decodeWCOTVobfuscation(html: html) else { return [] }
        guard let iframeSrc = extractIframeSrc(pmx: pmx) else { return [] }
        guard let getvidInfo = buildGetVidLinkUrl(iframeSrc: iframeSrc) else { return [] }
        
        var getvidRequest = URLRequest(url: getvidInfo.url)
        getvidRequest.setValue(ua, forHTTPHeaderField: "User-Agent")
        getvidRequest.setValue(getvidInfo.referer, forHTTPHeaderField: "Referer")
        getvidRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        
        guard let (vidData, _) = try? await URLSession.shared.data(for: getvidRequest),
              let vidResponse = try? JSONDecoder().decode(WCOTVResponse.self, from: vidData) else {
            return []
        }
        
        let server = vidResponse.server ?? vidResponse.cdn
        guard let serverUrlStr = server, !serverUrlStr.isEmpty else { return [] }
        
        var streams: [WCOTVStreamOption] = []
        
        if let fhdToken = vidResponse.fhd, !fhdToken.isEmpty {
            if let streamUrl = URL(string: "\(serverUrlStr)/getvid?evid=\(fhdToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fhdToken)") {
                streams.append(WCOTVStreamOption(url: streamUrl, referer: iframeSrc, language: lang, quality: "1080p"))
            }
        }
        if let hdToken = vidResponse.hd, !hdToken.isEmpty {
            if let streamUrl = URL(string: "\(serverUrlStr)/getvid?evid=\(hdToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hdToken)") {
                streams.append(WCOTVStreamOption(url: streamUrl, referer: iframeSrc, language: lang, quality: "720p"))
            }
        }
        if let encToken = vidResponse.enc, !encToken.isEmpty {
            if let streamUrl = URL(string: "\(serverUrlStr)/getvid?evid=\(encToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? encToken)") {
                streams.append(WCOTVStreamOption(url: streamUrl, referer: iframeSrc, language: lang, quality: "480p"))
            }
        }
        
        return streams
    }
    
    private func decodeWCOTVobfuscation(html: String) -> String? {
        guard let oreRegex = try? NSRegularExpression(pattern: "var ([A-Za-z]+)\\s*=\\s*\\[([\\s\\S]*?)\\];\\s*\\1\\.forEach", options: []) else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let oreMatch = oreRegex.firstMatch(in: html, options: [], range: nsRange) else { return nil }
        
        guard let arrayContentRange = Range(oreMatch.range(at: 2), in: html) else { return nil }
        let arrayContent = String(html[arrayContentRange])
        
        var constant = 51973287
        if let constRegex = try? NSRegularExpression(pattern: "\\)\\s*-\\s*(\\d{6,})\\s*\\)", options: []),
           let constMatch = constRegex.firstMatch(in: html, options: [], range: nsRange),
           let constRange = Range(constMatch.range(at: 1), in: html),
           let constVal = Int(html[constRange]) {
            constant = constVal
        }
        
        guard let tokenRegex = try? NSRegularExpression(pattern: "\"([A-Za-z0-9+/=]+)\"", options: []) else { return nil }
        let tokenNsRange = NSRange(arrayContent.startIndex..<arrayContent.endIndex, in: arrayContent)
        let tokenMatches = tokenRegex.matches(in: arrayContent, options: [], range: tokenNsRange)
        
        var PMx = ""
        for match in tokenMatches {
            guard let tokenRange = Range(match.range(at: 1), in: arrayContent) else { continue }
            let token = String(arrayContent[tokenRange])
            
            guard let decodedData = Data(base64Encoded: token) else { continue }
            let decodedStr = String(decoding: decodedData, as: UTF8.self)
            let digits = decodedStr.filter { $0.isNumber }
            if let digitVal = Int(digits) {
                let code = digitVal - constant
                if code > 0 && code < 0x110000, let unicodeChar = UnicodeScalar(code) {
                    PMx.append(Character(unicodeChar))
                }
            }
        }
        return PMx
    }
    
    private func extractIframeSrc(pmx: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "src=[\"']([^\"']+embed\\.wcostream\\.com[^\"']+)[\"']", options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(pmx.startIndex..<pmx.endIndex, in: pmx)
        if let match = regex.firstMatch(in: pmx, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: pmx) {
            return String(pmx[range])
        }
        
        guard let fallbackRegex = try? NSRegularExpression(pattern: "<iframe[^>]+src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return nil }
        if let match = fallbackRegex.firstMatch(in: pmx, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: pmx) {
            return String(pmx[range])
        }
        return nil
    }
    
    private func buildGetVidLinkUrl(iframeSrc: String) -> (url: URL, referer: String)? {
        guard let components = URLComponents(string: iframeSrc),
              let fileParam = components.queryItems?.first(where: { $0.name == "file" })?.value else {
            return nil
        }
        let filePath = fileParam.replacingOccurrences(of: ".flv", with: ".mp4", options: .caseInsensitive)
        let encodedPath = filePath.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? String($0) }.joined(separator: "/")
        let getvidlinkUrlString = "https://embed.wcostream.com/inc/embed/getvidlink.php?v=neptun/\(encodedPath)&embed=neptun&fullhd=1"
        
        guard let url = URL(string: getvidlinkUrlString) else { return nil }
        return (url, iframeSrc)
    }
}
