import Foundation

class FileSystemScanner {
    private let fileManager = FileManager.default
    private let commandExecutor = CommandExecutor()
    
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
            
            // 分析项目依赖
            let dependencies = await analyzeDependencies(for: language, in: projectDirectory)
            let cacheSize = await calculateCacheSize(for: language, in: projectDirectory)
            
            let project = Project(
                name: projectName,
                path: projectDirectory,
                language: language,
                lastModified: lastModified,
                dependencies: dependencies,
                cacheSize: cacheSize
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
        var scannedCount = 0
        let maxScanCount = 5000 // 限制扫描文件数量，避免过长时间
        let startTime = Date()
        let maxScanTime: TimeInterval = 10.0 // 最大扫描时间10秒
        
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
            scannedCount += 1
            
            // 检查扫描限制
            if scannedCount > maxScanCount {
                print("⚠️ 达到最大扫描文件数限制 (\(maxScanCount))，停止扫描")
                break
            }
            
            if Date().timeIntervalSince(startTime) > maxScanTime {
                print("⚠️ 达到最大扫描时间限制 (\(maxScanTime)秒)，停止扫描")
                break
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                
                if resourceValues.isDirectory == false && resourceValues.name == fileName {
                    projectFiles.append(fileURL)
                    print("✅ 发现项目文件: \(fileURL.path)")
                }
            } catch {
                // 忽略单个文件的错误
                continue
            }
        }
        
        print("📊 扫描统计: 检查了 \(scannedCount) 个文件，发现 \(projectFiles.count) 个 \(fileName) 项目")
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
    
    /// 分析项目依赖
    private func analyzeDependencies(for language: ProjectLanguage, in projectDirectory: URL) async -> [Dependency] {
        switch language {
        case .go:
            return await analyzeGoDependencies(in: projectDirectory)
        case .nodejs:
            return await analyzeNodeDependencies(in: projectDirectory)
        case .python:
            return await analyzePythonDependencies(in: projectDirectory)
        case .rust:
            return await analyzeRustDependencies(in: projectDirectory)
        }
    }
    
    /// 计算项目缓存大小
    private func calculateCacheSize(for language: ProjectLanguage, in projectDirectory: URL) async -> Int64 {
        switch language {
        case .go:
            return await calculateGoCacheSize(in: projectDirectory)
        case .nodejs:
            return await calculateNodeCacheSize(in: projectDirectory)
        case .python:
            return await calculatePythonCacheSize(in: projectDirectory)
        case .rust:
            return await calculateRustCacheSize(in: projectDirectory)
        }
    }
    
    // MARK: - Go项目分析
    
    private func analyzeGoDependencies(in projectDirectory: URL) async -> [Dependency] {
        do {
            // 检查go命令是否存在
            guard await commandExecutor.commandExists("go") else {
                return []
            }
            
            let modules = try await commandExecutor.getGoModules(in: projectDirectory)
            var dependencies: [Dependency] = []
            
            for moduleString in modules {
                // 解析模块字符串，格式: module_name version [replace]
                let components = moduleString.components(separatedBy: " ")
                guard components.count >= 2 else { continue }
                
                let name = components[0]
                let version = components[1]
                
                // 跳过主模块（通常第一行）
                if moduleString.contains("=>") || name == projectDirectory.lastPathComponent {
                    continue
                }
                
                let dependency = Dependency(
                    name: name,
                    version: version,
                    size: 0, // 稍后计算
                    cachePath: nil,
                    isOrphaned: false
                )
                dependencies.append(dependency)
            }
            
            return dependencies
        } catch {
            print("获取Go模块列表失败: \(error)")
            return []
        }
    }
    
    private func calculateGoCacheSize(in projectDirectory: URL) async -> Int64 {
        do {
            // 获取Go模块缓存路径
            _ = try await commandExecutor.getGoModCache()
            
            // 计算项目相关的缓存大小
            // 这里简化处理，实际应该只计算项目使用的模块
            let vendorPath = projectDirectory.appendingPathComponent("vendor")
            if fileManager.fileExists(atPath: vendorPath.path) {
                return try await calculateDirectorySize(vendorPath)
            }
            
            // 如果没有vendor目录，估算缓存大小
            return 50 * 1024 * 1024 // 50MB估算值
        } catch {
            return 0
        }
    }
    
    // MARK: - Node.js项目分析
    
    private func analyzeNodeDependencies(in projectDirectory: URL) async -> [Dependency] {
        do {
            // 检查npm命令是否存在
            guard await commandExecutor.commandExists("npm") else {
                return []
            }
            
            let packages = try await commandExecutor.getNpmPackages(in: projectDirectory)
            return packages.map { package in
                Dependency(
                    name: package.name,
                    version: package.version,
                    size: 0,
                    cachePath: nil,
                    isOrphaned: false
                )
            }
        } catch {
            print("获取npm包列表失败: \(error)")
            return []
        }
    }
    
    private func calculateNodeCacheSize(in projectDirectory: URL) async -> Int64 {
        let nodeModulesPath = projectDirectory.appendingPathComponent("node_modules")
        if fileManager.fileExists(atPath: nodeModulesPath.path) {
            do {
                return try await calculateDirectorySize(nodeModulesPath)
            } catch {
                return 0
            }
        }
        return 0
    }
    
    // MARK: - Python项目分析
    
    private func analyzePythonDependencies(in projectDirectory: URL) async -> [Dependency] {
        var dependencies: [Dependency] = []
        
        // 检查requirements.txt
        let requirementsPath = projectDirectory.appendingPathComponent("requirements.txt")
        if fileManager.fileExists(atPath: requirementsPath.path) {
            dependencies.append(contentsOf: await parseRequirementsTxt(at: requirementsPath))
        }
        
        // 检查pyproject.toml
        let pyprojectPath = projectDirectory.appendingPathComponent("pyproject.toml")
        if fileManager.fileExists(atPath: pyprojectPath.path) {
            dependencies.append(contentsOf: await parsePyprojectToml(at: pyprojectPath))
        }
        
        return dependencies
    }
    
    private func parseRequirementsTxt(at path: URL) async -> [Dependency] {
        do {
            let content = try String(contentsOf: path)
            var dependencies: [Dependency] = []
            
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }
                
                // 解析包名和版本 (例: package>=1.0.0)
                let components = trimmed.components(separatedBy: CharacterSet(charactersIn: ">=<~!"))
                let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let version = components.count > 1 ? components[1] : "unknown"
                
                let dependency = Dependency(
                    name: name,
                    version: version,
                    size: 0,
                    cachePath: nil,
                    isOrphaned: false
                )
                dependencies.append(dependency)
            }
            
            return dependencies
        } catch {
            return []
        }
    }
    
    private func parsePyprojectToml(at path: URL) async -> [Dependency] {
        // 简化实现：需要TOML解析器来正确处理
        // 这里先返回空数组，之后可以添加真正的TOML解析
        return []
    }
    
    private func calculatePythonCacheSize(in projectDirectory: URL) async -> Int64 {
        var totalSize: Int64 = 0
        
        // 检查项目级别的缓存目录
        let projectCachePaths = [
            projectDirectory.appendingPathComponent("__pycache__"),
            projectDirectory.appendingPathComponent(".pytest_cache"),
            projectDirectory.appendingPathComponent("venv"),
            projectDirectory.appendingPathComponent(".venv"),
            projectDirectory.appendingPathComponent(".mypy_cache"),
            projectDirectory.appendingPathComponent(".tox")
        ]
        
        for cachePath in projectCachePaths {
            if fileManager.fileExists(atPath: cachePath.path) {
                do {
                    totalSize += try await calculateDirectorySize(cachePath)
                } catch {
                    continue
                }
            }
        }
        
        // 递归查找所有__pycache__目录
        do {
            let pycacheSize = try await findAllPycacheDirectories(in: projectDirectory)
            totalSize += pycacheSize
        } catch {
            print("查找__pycache__目录失败: \(error)")
        }
        
        return totalSize
    }
    
    /// 递归查找所有__pycache__目录并计算大小
    private func findAllPycacheDirectories(in directory: URL) async throws -> Int64 {
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                
                if resourceValues.isDirectory == true && resourceValues.name == "__pycache__" {
                    let size = try await calculateDirectorySize(fileURL)
                    totalSize += size
                    
                    // 跳过该目录的子内容
                    enumerator.skipDescendants()
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    // MARK: - Rust项目分析
    
    private func analyzeRustDependencies(in projectDirectory: URL) async -> [Dependency] {
        let cargoPath = projectDirectory.appendingPathComponent("Cargo.toml")
        guard fileManager.fileExists(atPath: cargoPath.path) else {
            return []
        }
        
        // 简化实现：解析Cargo.toml需要TOML解析器
        // 这里先返回一些模拟数据
        return []
    }
    
    private func calculateRustCacheSize(in projectDirectory: URL) async -> Int64 {
        do {
            // 使用命令行工具获取更快的大小计算
            return try await commandExecutor.getRustTargetSize(in: projectDirectory)
        } catch {
            // 如果命令行失败，回退到目录遍历
            let targetPath = projectDirectory.appendingPathComponent("target")
            if fileManager.fileExists(atPath: targetPath.path) {
                do {
                    return try await calculateDirectorySize(targetPath)
                } catch {
                    return 0
                }
            }
            return 0
        }
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

