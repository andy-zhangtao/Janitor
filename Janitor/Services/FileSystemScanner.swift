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
    
    /// 扫描用户主目录下的所有项目
    func scanAllProjects(for language: ProjectLanguage) async throws -> [Project] {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let commonDirectories = [
            homeDirectory.appendingPathComponent("Documents"),
            homeDirectory.appendingPathComponent("Desktop"),
            homeDirectory.appendingPathComponent("Developer"),
            homeDirectory.appendingPathComponent("Projects"),
            homeDirectory.appendingPathComponent("Code"),
            homeDirectory.appendingPathComponent("Workspace")
        ]
        
        var allProjects: [Project] = []
        
        for directory in commonDirectories {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            
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