import Foundation
import CryptoKit

struct RefinementRegistry: Codable {
    struct Entry: Codable {
        let originalPath: String
        let refinedPath: String
        let metadataPath: String? // 🚀 V0.9.6.22: Path to JSON session data
        let lastModified: Date
    }
    
    private var mappings: [String: Entry] = [:] // Key: Original File MD5 Hash
    
    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("SlideReverse", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("registry.json")
    }
    
    static func load() -> RefinementRegistry {
        guard let data = try? Data(contentsOf: storageURL),
              let registry = try? JSONDecoder().decode(RefinementRegistry.self, from: data) else {
            return RefinementRegistry()
        }
        return registry
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.storageURL)
        }
    }
    
    mutating func register(original: URL, refined: URL, metadata: URL? = nil) {
        guard let hash = fileHash(for: original) else { return }
        mappings[hash] = Entry(
            originalPath: original.path, 
            refinedPath: refined.path, 
            metadataPath: metadata?.path, 
            lastModified: Date()
        )
        save()
    }
    
    func findEntry(for original: URL) -> Entry? {
        guard let hash = fileHash(for: original) else { return nil }
        return mappings[hash]
    }
    
    private func fileHash(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
