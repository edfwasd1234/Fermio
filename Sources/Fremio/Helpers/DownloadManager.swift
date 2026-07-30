import Foundation
import Combine

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
}

struct DownloadTask: Identifiable, Codable {
    let id: String // uniquely identifies the download (e.g. tmdbId for movie, "tmdbId-season-episode" for show)
    let mediaId: String
    let title: String
    let type: MediaType
    let season: Int
    let episode: Int
    let posterPath: String?
    let backdropPath: String?
    let posterSymbol: String
    let posterColorHex: String
    let genre: String
    let rating: Double
    let releaseYear: Int
    let duration: String
    let description: String
    
    var progress: Double
    var status: DownloadStatus
    var speed: Double // Bytes per second
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var localPath: String?
    
    var timeRemainingString: String {
        guard status == .downloading, speed > 0, totalBytes > bytesDownloaded else {
            return status == .completed ? "Completed" : ""
        }
        let remainingBytes = totalBytes - bytesDownloaded
        let seconds = Double(remainingBytes) / speed
        if seconds < 60 {
            return "\(Int(seconds))s remaining"
        } else {
            let mins = Int(seconds / 60)
            let secs = Int(seconds) % 60
            return "\(mins)m \(secs)s remaining"
        }
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    
    @Published var tasks: [DownloadTask] = []
    
    private var session: URLSession!
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private var lastProgressUpdate: [String: Date] = [:]
    private var lastBytesDownloaded: [String: Int64] = [:]
    
    private override init() {
        super.init()
        // Background session so downloads continue while the app is suspended and
        // resume/deliver their results when it's relaunched.
        let config = URLSessionConfiguration.background(withIdentifier: "app.fremio.downloads")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        loadTasks()
        reconcileInterruptedTasks()
    }

    /// After a background session reconnects, tasks still running keep their
    /// `.downloading` status (their delegate callbacks will update them). Only
    /// tasks that are genuinely gone get marked failed.
    private func reconcileInterruptedTasks() {
        session.getAllTasks { sessionTasks in
            let activeIds = Set(sessionTasks.compactMap { $0.taskDescription })
            Task { @MainActor [weak self] in
                self?.markStaleDownloadsFailed(activeIds: activeIds)
            }
        }
    }

    private func markStaleDownloadsFailed(activeIds: Set<String>) {
        var changed = false
        for i in tasks.indices where tasks[i].status == .downloading {
            if !activeIds.contains(tasks[i].id) {
                tasks[i].status = .failed
                changed = true
            }
        }
        if changed { saveTasks() }
    }
    
    func startDownload(item: MediaItem, season: Int = 1, episode: Int = 1) {
        let taskId = item.type == .movie ? item.id : "\(item.id)-\(season)-\(episode)"
        
        // Avoid duplicate download
        if let existing = tasks.first(where: { $0.id == taskId }) {
            if existing.status == .completed {
                return
            } else if existing.status == .downloading {
                return
            } else {
                // Restart failed/pending
                tasks.removeAll(where: { $0.id == taskId })
            }
        }
        
        let newTask = DownloadTask(
            id: taskId,
            mediaId: item.id,
            title: item.type == .movie ? item.title : "\(item.title) - S\(season)E\(episode)",
            type: item.type,
            season: season,
            episode: episode,
            posterPath: item.posterPath,
            backdropPath: item.backdropPath,
            posterSymbol: item.posterSymbol,
            posterColorHex: item.posterColorHex,
            genre: item.genre,
            rating: item.rating,
            releaseYear: item.releaseYear,
            duration: item.duration,
            description: item.description,
            progress: 0.0,
            status: .pending,
            speed: 0.0,
            bytesDownloaded: 0,
            totalBytes: 0,
            localPath: nil
        )
        
        tasks.append(newTask)
        saveTasks()
        
        // Resolve stream link first
        Task {
            do {
                let streamUrl = try await StreamResolver.shared.resolveStream(
                    type: item.type,
                    tmdbId: item.id,
                    season: season,
                    episode: episode
                )
                
                await MainActor.run {
                    self.initiateDownload(taskId: taskId, url: streamUrl)
                }
            } catch {
                print("Failed to resolve stream link for download: \(error)")
                await MainActor.run {
                    self.failTask(taskId: taskId)
                }
            }
        }
    }
    
    private func initiateDownload(taskId: String, url: URL) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        
        // Same CDN-bypass headers playback uses; without them the origin 403s.
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://vidvault.ru/", forHTTPHeaderField: "Referer")

        let downloadTask = session.downloadTask(with: request)
        activeDownloads[taskId] = downloadTask
        downloadTask.taskDescription = taskId
        
        tasks[idx].status = .downloading
        lastProgressUpdate[taskId] = Date()
        lastBytesDownloaded[taskId] = 0
        
        downloadTask.resume()
        saveTasks()
    }
    
    func cancelDownload(taskId: String) {
        if let downloadTask = activeDownloads[taskId] {
            downloadTask.cancel()
            activeDownloads.removeValue(forKey: taskId)
        } else {
            // May be a background task from a previous launch we never re-adopted.
            session.getAllTasks { sessionTasks in
                for task in sessionTasks where task.taskDescription == taskId {
                    task.cancel()
                }
            }
        }
        tasks.removeAll(where: { $0.id == taskId })
        deleteLocalFile(taskId: taskId)
        saveTasks()
    }
    
    func deleteDownload(taskId: String) {
        tasks.removeAll(where: { $0.id == taskId })
        deleteLocalFile(taskId: taskId)
        saveTasks()
    }
    
    private func failTask(taskId: String) {
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].status = .failed
            saveTasks()
        }
    }
    
    func getLocalFileUrl(for task: DownloadTask) -> URL? {
        guard task.status == .completed, let path = task.localPath else { return nil }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fullURL = documentsURL.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: fullURL.path) ? fullURL : nil
    }
    
    private func deleteLocalFile(taskId: String) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent("Downloads/\(taskId).mp4")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Persistence
    
    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: "downloaded_tasks")
        }
    }
    
    private func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: "downloaded_tasks"),
           let decoded = try? JSONDecoder().decode([DownloadTask].self, from: data) {
            self.tasks = decoded
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskId = downloadTask.taskDescription else { return }
        
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            
            let now = Date()
            let lastUpdate = self.lastProgressUpdate[taskId] ?? now
            let timeDiff = now.timeIntervalSince(lastUpdate)
            
            if timeDiff >= 0.5 {
                let lastBytes = self.lastBytesDownloaded[taskId] ?? 0
                let bytesDiff = totalBytesWritten - lastBytes
                let speed = Double(bytesDiff) / timeDiff
                
                self.tasks[idx].speed = speed
                self.lastProgressUpdate[taskId] = now
                self.lastBytesDownloaded[taskId] = totalBytesWritten
            }
            
            self.tasks[idx].bytesDownloaded = totalBytesWritten
            self.tasks[idx].totalBytes = totalBytesExpectedToWrite
            self.tasks[idx].progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
            self.saveTasks()
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskId = downloadTask.taskDescription else { return }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = documentsURL.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        
        let relativePath = "Downloads/\(taskId).mp4"
        let destURL = documentsURL.appendingPathComponent(relativePath)
        
        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            
            Task { @MainActor in
                if let idx = self.tasks.firstIndex(where: { $0.id == taskId }) {
                    self.tasks[idx].status = .completed
                    self.tasks[idx].progress = 1.0
                    self.tasks[idx].localPath = relativePath
                    self.activeDownloads.removeValue(forKey: taskId)
                    self.saveTasks()
                }
            }
        } catch {
            print("Failed to save downloaded file: \(error)")
            Task { @MainActor in
                self.failTask(taskId: taskId)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskId = task.taskDescription else { return }
        if let error = error {
            print("Download task failed with error: \(error)")
            Task { @MainActor in
                self.failTask(taskId: taskId)
                self.activeDownloads.removeValue(forKey: taskId)
            }
        }
    }
}
