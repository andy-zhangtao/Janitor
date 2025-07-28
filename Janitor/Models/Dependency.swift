import Foundation

struct Dependency: Identifiable, Hashable, Codable {
    let id = UUID()
    let name: String
    let version: String
    let size: Int64 // 字节
    let cachePath: URL?
    let isOrphaned: Bool // 是否为孤立依赖
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var displayName: String {
        "\(name) v\(version)"
    }
}

struct CacheEntry: Identifiable, Hashable, Codable {
    let id = UUID()
    let path: URL
    let size: Int64
    let language: ProjectLanguage
    let lastAccessed: Date
    let isOrphaned: Bool
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var formattedLastAccessed: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastAccessed, relativeTo: Date())
    }
}