import Foundation

class FileSystemScanner {
    private let fileManager = FileManager.default
    
    // MARK: - Public Methods
    
    /// 扫描指定目录下的项目文件
    func scanForProjects(in directory: URL, language: ProjectLanguage) async throws -> [Project] {
        let projectFileName = language.projectFileName
        let projectPaths = try await findProjectFiles(named: projectFileName, in: directory)
        
        var projects: [Project] = []
        
        for projectPath in projectPaths {
            let projectDirectory = projectPath.deletingLastPathComponent()
            
            // 获取项目基本信息
            let projectName = projectDirectory.lastPathComponent
            let lastModified = try getLastModifiedDate(for: projectDirectory)
            
            let project = Project(
                name: projectName,
                path: projectDirectory,
                language: language,
                lastModified: lastModified,
                dependencies: [],
                cacheSize: 0
            )
            
            projects.append(project)
        }
        
        return projects
    }
    
    /// 扫描指定目录列表中的所有项目
    func scanProjects(in directories: [URL], for language: ProjectLanguage) async throws -> [Project] {
        var allProjects: [Project] = []
        
        for directory in directories {
            // 验证目录是否存在且可访问
            guard fileManager.fileExists(atPath: directory.path) else {
                print("目录不存在: \(directory.path)")
                continue
            }
            
            // 检查读取权限
            guard fileManager.isReadableFile(atPath: directory.path) else {
                print("无法读取目录: \(directory.path)")
                continue
            }
            
            do {
                let projects = try await scanForProjects(in: directory, language: language)
                allProjects.append(contentsOf: projects)
            } catch {
                // 记录错误但继续扫描其他目录
                print("扫描目录 \(directory.path) 时出错: \(error)")
            }
        }
        
        return allProjects
    }
    
    /// 获取建议的扫描目录（检查常见开发目录是否存在）
    func getSuggestedDirectories() -> [URL] {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            homeDirectory.appendingPathComponent("Developer"),
            homeDirectory.appendingPathComponent("Projects"),
            homeDirectory.appendingPathComponent("Code"),
            homeDirectory.appendingPathComponent("Workspace"),
            homeDirectory.appendingPathComponent("Documents"),
            homeDirectory.appendingPathComponent("Desktop")
        ]
        
        return candidates.filter { directory in
            fileManager.fileExists(atPath: directory.path) && 
            fileManager.isReadableFile(atPath: directory.path)
        }
    }
    
    /// 验证目录是否适合扫描
    func validateDirectory(_ directory: URL) -> DirectoryValidationResult {
        // 检查目录是否存在
        guard fileManager.fileExists(atPath: directory.path) else {
            return .invalid("目录不存在")
        }
        
        // 检查是否为目录
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .invalid("路径不是目录")
        }
        
        // 检查读取权限
        guard fileManager.isReadableFile(atPath: directory.path) else {
            return .invalid("无读取权限")
        }
        
        // 估算潜在项目数量（快速扫描）
        let projectCount = estimateProjectCount(in: directory)
        
        if projectCount == 0 {
            return .warning("该目录下未发现开发项目")
        } else {
            return .valid("发现约 \(projectCount) 个潜在项目")
        }
    }
    
    /// 计算目录大小
    func calculateDirectorySize(_ directory: URL) async throws -> Int64 {
        var totalSize: Int64 = 0
        
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                print("目录遍历错误: \(error)")
                return true // 继续遍历
            }
        ) else {
            throw FileSystemError.enumerationFailed
        }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            
            if resourceValues.isRegularFile == true {
                totalSize += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            }
        }
        
        return totalSize
    }
    
    // MARK: - Private Methods
    
    private func findProjectFiles(named fileName: String, in directory: URL) async throws -> [URL] {
        var projectFiles: [URL] = []
        
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .nameKey
        ]
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                // 忽略权限错误，继续扫描
                if (error as NSError).code != NSFileReadNoPermissionError {
                    print("文件扫描错误 \(url.path): \(error)")
                }
                return true
            }
        ) else {
            throw FileSystemError.enumerationFailed
        }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            
            if resourceValues.isDirectory == false && resourceValues.name == fileName {
                projectFiles.append(fileURL)
            }
        }
        
        return projectFiles
    }
    
    private func getLastModifiedDate(for directory: URL) throws -> Date {
        let resourceValues = try directory.resourceValues(forKeys: [.contentModificationDateKey])
        return resourceValues.contentModificationDate ?? Date()
    }
    
    /// 快速估算目录中的项目数量（用于验证提示）
    private func estimateProjectCount(in directory: URL) -> Int {
        var projectCount = 0
        let projectFiles = ["go.mod", "package.json", "requirements.txt", "Cargo.toml", "pyproject.toml"]
        
        // 快速扫描，最多扫描前100个文件
        var scannedCount = 0
        let maxScanCount = 100
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            scannedCount += 1
            if scannedCount > maxScanCount { break }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.nameKey, .isDirectoryKey])
                if resourceValues.isDirectory == false,
                   let fileName = resourceValues.name,
                   projectFiles.contains(fileName) {
                    projectCount += 1
                }
            } catch {
                continue
            }
        }
        
        return projectCount
    }
}

// MARK: - Error Types
enum FileSystemError: LocalizedError {
    case enumerationFailed
    case permissionDenied(String)
    case pathNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .enumerationFailed:
            return "文件系统遍历失败"
        case .permissionDenied(let path):
            return "访问路径权限不足: \(path)"
        case .pathNotFound(let path):
            return "路径不存在: \(path)"
        }
    }
}

// MARK: - Directory Validation
enum DirectoryValidationResult {
    case valid(String)      // 有效，附带描述信息
    case warning(String)    // 警告，可以使用但需要提示
    case invalid(String)    // 无效，不能使用
    
    var isUsable: Bool {
        switch self {
        case .valid, .warning:
            return true
        case .invalid:
            return false
        }
    }
    
    var message: String {
        switch self {
        case .valid(let msg), .warning(let msg), .invalid(let msg):
            return msg
        }
    }
    
    var icon: String {
        switch self {
        case .valid:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .invalid:
            return "xmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .valid:
            return "green"
        case .warning:
            return "orange"
        case .invalid:
            return "red"
        }
    }
}