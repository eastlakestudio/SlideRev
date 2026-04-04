import SwiftUI
import AppKit

/// 🚀 V39.7: Intelligent Tiered Image Cache (L1 Memory + L2 Disk)
/// Automatically manages resources based on system memory pressure.
class SlideImageCache {
    static let shared = SlideImageCache()
    
    private let memCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL?
    
    private init() {
        // Prepare L1 Cache Policy
        memCache.countLimit = 15 // Keep about 15 high-res slides in RAM max
        memCache.totalCostLimit = 400 * 1024 * 1024 // 400MB threshold for memory pressure
        
        // Prepare L2 Disk Cache (Temporary Directory for the session)
        let cacheDir = fileManager.temporaryDirectory.appendingPathComponent("SlideRev_ImageCache")
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.diskCacheURL = cacheDir
    }
    
    // MARK: - API
    
    /// Store an image with an optional cost (size in bytes)
    func store(_ image: NSImage, for key: String) {
        // Always store in RAM first for speed
        memCache.setObject(image, forKey: key as NSString, cost: image.approximateSizeInBytes)
        
        // Asynchronously offload to disk to ensure Moment 2 is "Instant" next time
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, let url = self.diskPath(for: key) else { return }
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                // Using high-quality JPEG for disk cache to balance speed and space
                let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                try? data?.write(to: url)
            }
        }
    }
    
    /// Retrieve image synchronously: Memory (L1) -> Disk (L2) -> Nil
    func retrieveSync(for key: String) -> NSImage? {
        // Try Memory (L1)
        if let cached = memCache.object(forKey: key as NSString) {
            return cached
        }
        
        // Try Disk (L2) - Synchronous read
        if let url = self.diskPath(for: key), 
           self.fileManager.fileExists(atPath: url.path),
           let image = NSImage(contentsOf: url) {
            // Re-promote to Memory
            self.memCache.setObject(image, forKey: key as NSString, cost: image.approximateSizeInBytes)
            return image
        }
        
        return nil
    }

    /// Retrieve image: Memory -> Disk -> Nil
    func retrieve(for key: String, completion: @escaping (NSImage?) -> Void) {
        // Try Memory (L1) - Synchronous
        if let cached = memCache.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        
        // Try Disk (L2) - Asynchronous
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let image = self.retrieveSync(for: key) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(image) }
        }
    }
    
    func remove(for key: String) {
        memCache.removeObject(forKey: key as NSString)
        if let url = diskPath(for: key) {
            try? fileManager.removeItem(at: url)
        }
    }
    
    func clearAll() {
        memCache.removeAllObjects()
        if let url = diskCacheURL {
            try? fileManager.removeItem(at: url)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Helpers
    
    private func diskPath(for key: String) -> URL? {
        let safeKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return diskCacheURL?.appendingPathComponent("\(safeKey).jpg")
    }
}

extension NSImage {
    var approximateSizeInBytes: Int {
        let width = size.width
        let height = size.height
        return Int(width * height * 4) // Approx RGBA buffer
    }
}
