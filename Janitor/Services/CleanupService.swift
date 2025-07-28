import Foundation

class CleanupService {
    private let commandExecutor = CommandExecutor()
    private let fileManager = FileManager.default
    
    // MARK: - 清理操作类型
    
    enum CleanupOperation {
        case projectCache(Project)          // 清理单个项目缓存
        case globalCache(ProjectLanguage)   // 清理全局语言缓存
        case customDirectory(URL)           // 清理自定义目录
        case dependencyPrune(Project)       // 清理无用依赖
    }
    
    enum CleanupResult {
        case success(String, Int64)  // 消息和释放的字节数
        case failure(String)         // 错误消息
        case skipped(String)         // 跳过原因
    }
    
    // MARK: - 主要清理方法
    
    /// 执行清理操作
    func performCleanup(_ operation: CleanupOperation) async -> CleanupResult {
        do {
            switch operation {
            case .projectCache(let project):
                return await cleanProjectCache(project)
            case .globalCache(let language):
                return await cleanGlobalCache(language)
            case .customDirectory(let directory):
                return await cleanCustomDirectory(directory)
            case .dependencyPrune(let project):
                return await pruneDependencies(project)
            }
        } catch {
            return .failure("清理失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 项目级别清理
    
    private func cleanProjectCache(_ project: Project) async -> CleanupResult {
        let sizeBefore = project.cacheSize
        
        switch project.language {
        case .go:
            return await cleanGoProjectCache(project, sizeBefore: sizeBefore)
        case .nodejs:
            return await cleanNodeProjectCache(project, sizeBefore: sizeBefore)
        case .python:
            return await cleanPythonProjectCache(project, sizeBefore: sizeBefore)
        case .rust:
            return await cleanRustProjectCache(project, sizeBefore: sizeBefore)
        }
    }
    
    private func cleanGoProjectCache(_ project: Project, sizeBefore: Int64) async -> CleanupResult {
        var totalSaved: Int64 = 0
        var operations: [String] = []
        
        // 清理vendor目录
        let vendorPath = project.path.appendingPathComponent("vendor")
        if fileManager.fileExists(atPath: vendorPath.path) {
            do {
                let vendorSize = try await calculateDirectorySize(vendorPath)
                try fileManager.removeItem(at: vendorPath)
                totalSaved += vendorSize
                operations.append("删除vendor目录")
            } catch {
                return .failure("无法删除vendor目录: \(error.localizedDescription)")
            }
        }
        
        // 执行go mod download重新下载依赖（可选）
        if operations.isEmpty {
            return .skipped("没有发现可清理的Go缓存")
        }
        
        let message = "清理Go项目缓存: \(operations.joined(separator: ", "))"
        return .success(message, totalSaved)
    }
    
    private func cleanNodeProjectCache(_ project: Project, sizeBefore: Int64) async -> CleanupResult {
        let nodeModulesPath = project.path.appendingPathComponent("node_modules")
        
        guard fileManager.fileExists(atPath: nodeModulesPath.path) else {
            return .skipped("没有发现node_modules目录")
        }
        
        do {
            let nodeModulesSize = try await calculateDirectorySize(nodeModulesPath)
            try fileManager.removeItem(at: nodeModulesPath)
            
            let message = "删除node_modules目录"
            return .success(message, nodeModulesSize)
        } catch {
            return .failure("无法删除node_modules: \(error.localizedDescription)")
        }
    }
    
    private func cleanPythonProjectCache(_ project: Project, sizeBefore: Int64) async -> CleanupResult {
        var totalSaved: Int64 = 0
        var operations: [String] = []
        
        let cachePaths = [
            ("__pycache__", project.path.appendingPathComponent("__pycache__")),
            (".pytest_cache", project.path.appendingPathComponent(".pytest_cache")),
            (".mypy_cache", project.path.appendingPathComponent(".mypy_cache")),
            (".tox", project.path.appendingPathComponent(".tox"))
        ]
        
        for (name, path) in cachePaths {
            if fileManager.fileExists(atPath: path.path) {
                do {
                    let size = try await calculateDirectorySize(path)
                    try fileManager.removeItem(at: path)
                    totalSaved += size
                    operations.append("删除\(name)")
                } catch {
                    continue
                }
            }
        }
        
        // 递归清理所有__pycache__目录
        let pycacheSize = await cleanAllPycacheDirectories(in: project.path)
        if pycacheSize > 0 {
            totalSaved += pycacheSize
            operations.append("清理递归__pycache__")
        }
        
        if operations.isEmpty {
            return .skipped("没有发现可清理的Python缓存")
        }
        
        let message = "清理Python项目缓存: \(operations.joined(separator: ", "))"
        return .success(message, totalSaved)
    }
    
    private func cleanRustProjectCache(_ project: Project, sizeBefore: Int64) async -> CleanupResult {
        let targetPath = project.path.appendingPathComponent("target")
        
        guard fileManager.fileExists(atPath: targetPath.path) else {
            return .skipped("没有发现target目录")
        }
        
        do {
            let targetSize = try await calculateDirectorySize(targetPath)
            try fileManager.removeItem(at: targetPath)
            
            let message = "删除target目录"
            return .success(message, targetSize)
        } catch {
            return .failure("无法删除target目录: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 全局缓存清理
    
    private func cleanGlobalCache(_ language: ProjectLanguage) async -> CleanupResult {
        do {
            switch language {
            case .go:
                let result = try await commandExecutor.cleanGoModCache()
                if result.isSuccess {
                    return .success("清理Go全局模块缓存", 0) // 大小未知
                } else {
                    return .failure("Go模块缓存清理失败: \(result.error)")
                }
                
            case .nodejs:
                let result = try await commandExecutor.cleanNpmCache()
                if result.isSuccess {
                    return .success("清理npm全局缓存", 0)
                } else {
                    return .failure("npm缓存清理失败: \(result.error)")
                }
                
            case .python:
                let result = try await commandExecutor.cleanPipCache()
                if result.isSuccess {
                    return .success("清理pip全局缓存", 0)
                } else {
                    return .failure("pip缓存清理失败: \(result.error)")
                }
                
            case .rust:
                // Rust没有全局清理命令，返回跳过
                return .skipped("Rust不支持全局缓存清理")
            }
        } catch {
            return .failure("命令执行失败: \(error.localizedDescription)")
        }
    }
    
    private func cleanCustomDirectory(_ directory: URL) async -> CleanupResult {
        guard fileManager.fileExists(atPath: directory.path) else {
            return .failure("目录不存在: \(directory.path)")
        }
        
        do {
            let size = try await calculateDirectorySize(directory)
            try fileManager.removeItem(at: directory)
            
            let message = "删除目录: \(directory.lastPathComponent)"
            return .success(message, size)
        } catch {
            return .failure("无法删除目录: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 依赖清理
    
    private func pruneDependencies(_ project: Project) async -> CleanupResult {
        do {
            switch project.language {
            case .go:
                let result = try await commandExecutor.goModTidy(in: project.path)
                if result.isSuccess {
                    return .success("执行go mod tidy", 0)
                } else {
                    return .failure("go mod tidy失败: \(result.error)")
                }
                
            case .nodejs:
                let result = try await commandExecutor.npmPrune(in: project.path)
                if result.isSuccess {
                    return .success("执行npm prune", 0)
                } else {
                    return .failure("npm prune失败: \(result.error)")
                }
                
            case .python, .rust:
                return .skipped("\(project.language.rawValue)不支持依赖清理")
            }
        } catch {
            return .failure("命令执行失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 辅助方法
    
    private func calculateDirectorySize(_ directory: URL) async throws -> Int64 {
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
                return true
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
    
    private func cleanAllPycacheDirectories(in directory: URL) async -> Int64 {
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
                    try fileManager.removeItem(at: fileURL)
                    totalSize += size
                    
                    enumerator.skipDescendants()
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
}