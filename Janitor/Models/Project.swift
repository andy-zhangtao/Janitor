import Foundation

struct Project: Identifiable, Hashable, Codable {
    let id = UUID()
    let name: String
    let path: URL
    let language: ProjectLanguage
    let lastModified: Date
    var dependencies: [Dependency] = []
    var cacheSize: Int64 = 0 // 字节
    
    var isActive: Bool {
        // 判断项目是否活跃（最近30天内修改过）
        Date().timeIntervalSince(lastModified) < 30 * 24 * 3600
    }
    
    var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }
    
    var formattedLastModified: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }
}

enum ProjectLanguage: String, CaseIterable, Codable {
    case go = "Go"
    case nodejs = "Node.js"
    case python = "Python"
    case rust = "Rust"
    
    var iconName: String {
        switch self {
        case .go: return "cube.fill"
        case .nodejs: return "leaf.fill"
        case .python: return "snake.fill"
        case .rust: return "gear.fill"
        }
    }
    
    var projectFileName: String {
        switch self {
        case .go: return "go.mod"
        case .nodejs: return "package.json"
        case .python: return "requirements.txt"
        case .rust: return "Cargo.toml"
        }
    }
    
    var cacheDirectory: String {
        switch self {
        case .go: return "pkg/mod"
        case .nodejs: return ".npm"
        case .python: return "pip/cache"
        case .rust: return ".cargo"
        }
    }
}