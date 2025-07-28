import Foundation

class CommandExecutor {
    private let toolSettings = ToolSettings()
    
    /// 执行系统命令并返回输出
    func executeCommand(
        _ command: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        timeout: TimeInterval = 30.0
    ) async throws -> CommandResult {
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        // 获取完整的PATH环境变量
        let fullPath = await getFullEnvironmentPath()
        
        // 尝试找到命令的完整路径
        let commandPath: String
        if let foundPath = await findCommandPath(command) {
            commandPath = foundPath
            print("🎯 使用命令路径: \(commandPath)")
        } else {
            // 如果找不到，回退到使用 /usr/bin/env
            commandPath = "/usr/bin/env"
            process.arguments = [command] + arguments
            print("⚠️ 回退到 /usr/bin/env，命令: \(command)")
        }
        
        // 配置进程
        if commandPath != "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: commandPath)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        // 设置完整的环境变量
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = fullPath
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        
        // 添加开发工具特定的环境变量
        if environment["GOPATH"] == nil {
            environment["GOPATH"] = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go").path
        }
        if environment["GOROOT"] == nil && FileManager.default.fileExists(atPath: "/usr/local/go") {
            environment["GOROOT"] = "/usr/local/go"
        }
        
        process.environment = environment
        
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        
        // 启动进程
        try process.run()
        
        // 创建超时任务
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                process.terminate()
                throw CommandError.timeout
            }
        }
        
        // 等待进程完成
        let completionTask = Task {
            process.waitUntilExit()
            timeoutTask.cancel()
        }
        
        // 等待任一任务完成
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await timeoutTask.value }
            group.addTask { try await completionTask.value }
            
            // 等待第一个完成的任务
            try await group.next()
            group.cancelAll()
        }
        
        // 读取输出
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        let result = CommandResult(
            exitCode: process.terminationStatus,
            output: output,
            error: error,
            command: command,
            arguments: arguments
        )
        
        // 检查是否成功执行
        if process.terminationStatus != 0 {
            // 检查是否是权限问题
            if result.error.contains("Operation not permitted") || result.error.contains("Permission denied") {
                throw CommandError.permissionDenied(command, result.error)
            } else {
                throw CommandError.executionFailed(result)
            }
        }
        
        return result
    }
    
    /// 检查命令是否存在
    func commandExists(_ command: String) async -> Bool {
        // 首先尝试直接查找
        if let _ = await findCommandPath(command) {
            return true
        }
        
        // 如果直接查找失败，使用which命令
        do {
            let result = try await executeCommand("which", arguments: [command])
            return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }
    
    /// 获取Go模块列表
    func getGoModules(in projectPath: URL) async throws -> [String] {
        let result = try await executeCommand(
            "go",
            arguments: ["list", "-m", "all"],
            workingDirectory: projectPath
        )
        
        return result.output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
    }
    
    /// 获取Go模块缓存路径
    func getGoModCache() async throws -> URL {
        let result = try await executeCommand("go", arguments: ["env", "GOMODCACHE"])
        let cachePath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cachePath.isEmpty else {
            throw CommandError.invalidOutput("GOMODCACHE路径为空")
        }
        
        return URL(fileURLWithPath: cachePath)
    }
    
    /// 获取npm全局缓存路径
    func getNpmCachePath() async throws -> URL {
        let result = try await executeCommand("npm", arguments: ["config", "get", "cache"])
        let cachePath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cachePath.isEmpty else {
            throw CommandError.invalidOutput("npm缓存路径为空")
        }
        
        return URL(fileURLWithPath: cachePath)
    }
    
    /// 获取Node.js包信息
    func getNpmPackages(in projectPath: URL) async throws -> [(name: String, version: String)] {
        let result = try await executeCommand(
            "npm",
            arguments: ["list", "--depth=0", "--json"],
            workingDirectory: projectPath
        )
        
        // 解析JSON输出
        guard let data = result.output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = json["dependencies"] as? [String: [String: Any]] else {
            return []
        }
        
        return dependencies.compactMap { (name, info) in
            let version = info["version"] as? String ?? "unknown"
            return (name: name, version: version)
        }
    }
    
    /// 获取pip缓存路径
    func getPipCachePath() async throws -> URL {
        let result = try await executeCommand("pip", arguments: ["cache", "dir"])
        let cachePath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cachePath.isEmpty else {
            throw CommandError.invalidOutput("pip缓存路径为空")
        }
        
        return URL(fileURLWithPath: cachePath)
    }
    
    /// 获取Cargo缓存路径
    func getCargoCachePath() async throws -> URL {
        // Cargo使用环境变量CARGO_HOME，默认为~/.cargo
        let result = try await executeCommand("cargo", arguments: ["--version"])
        // 检查cargo是否可用
        guard result.isSuccess else {
            throw CommandError.commandNotFound("cargo")
        }
        
        // 返回默认的cargo路径
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".cargo")
    }
    
    /// 获取Rust目标目录大小（项目级别的缓存）
    func getRustTargetSize(in projectPath: URL) async throws -> Int64 {
        let targetPath = projectPath.appendingPathComponent("target")
        guard FileManager.default.fileExists(atPath: targetPath.path) else {
            return 0
        }
        
        // 使用du命令快速计算大小
        let result = try await executeCommand(
            "du",
            arguments: ["-s", "-k", targetPath.path]
        )
        
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = output.components(separatedBy: "\t")
        guard let sizeString = components.first,
              let sizeKB = Int64(sizeString) else {
            return 0
        }
        
        return sizeKB * 1024 // 转换为字节
    }
    
    // MARK: - 清理命令
    
    /// 清理Go模块缓存
    func cleanGoModCache() async throws -> CommandResult {
        return try await executeCommand("go", arguments: ["clean", "-modcache"])
    }
    
    /// 执行go mod tidy
    func goModTidy(in projectPath: URL) async throws -> CommandResult {
        return try await executeCommand(
            "go", 
            arguments: ["mod", "tidy"], 
            workingDirectory: projectPath
        )
    }
    
    /// 清理npm缓存
    func cleanNpmCache() async throws -> CommandResult {
        return try await executeCommand("npm", arguments: ["cache", "clean", "--force"])
    }
    
    /// 执行npm prune
    func npmPrune(in projectPath: URL) async throws -> CommandResult {
        return try await executeCommand(
            "npm", 
            arguments: ["prune"], 
            workingDirectory: projectPath
        )
    }
    
    /// 清理pip缓存
    func cleanPipCache() async throws -> CommandResult {
        return try await executeCommand("pip", arguments: ["cache", "purge"])
    }
    
    /// 清理cargo缓存
    func cleanCargo(in projectPath: URL) async throws -> CommandResult {
        return try await executeCommand(
            "cargo", 
            arguments: ["clean"], 
            workingDirectory: projectPath
        )
    }
    
    /// 删除目录（安全删除）
    func removeDirectory(at path: URL) async throws -> CommandResult {
        // 使用rm -rf进行删除，但添加安全检查
        guard path.path.contains("/") && !path.path.hasPrefix("/System") && !path.path.hasPrefix("/usr") else {
            throw CommandError.invalidOutput("拒绝删除系统目录: \(path.path)")
        }
        
        return try await executeCommand("rm", arguments: ["-rf", path.path])
    }
    
    // MARK: - 环境配置
    
    /// 获取完整的PATH环境变量
    private func getFullEnvironmentPath() async -> String {
        // 常见的工具安装路径
        let commonPaths = [
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/opt/homebrew/bin",        // Apple Silicon Homebrew
            "/opt/homebrew/sbin",       // Apple Silicon Homebrew sbin
            "/usr/local/homebrew/bin",  // Intel Homebrew
            "/usr/local/go/bin",        // Go官方安装路径
            "/usr/local/node/bin",      // Node.js官方安装路径
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go/bin").path,  // GOPATH/bin
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin").path, // Cargo bin
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path, // Python local bin
            "/usr/local/lib/node_modules/.bin", // npm global bin
        ]
        
        // 获取系统PATH
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        
        // 尝试从用户shell配置中读取PATH
        let userShellPath = await getUserShellPath()
        
        // 合并所有路径，优先级：用户配置 > 用户shell > 系统PATH > 常见路径
        var allPathComponents: [String] = []
        
        if !systemPath.isEmpty {
            allPathComponents.append(systemPath)
        }
        
        if !userShellPath.isEmpty {
            allPathComponents.append(userShellPath)
        }
        
        allPathComponents.append(contentsOf: commonPaths)
        
        let allPaths = allPathComponents.joined(separator: ":")
        
        print("🔍 构建的完整PATH: \(allPaths)")
        return allPaths
    }
    
    /// 尝试从用户shell配置中获取PATH
    private func getUserShellPath() async -> String {
        // 尝试读取用户的shell配置文件
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let shellConfigFiles = [
            ".zshrc",
            ".bash_profile", 
            ".bashrc",
            ".profile"
        ]
        
        for configFile in shellConfigFiles {
            let configPath = homeDir.appendingPathComponent(configFile)
            if FileManager.default.fileExists(atPath: configPath.path) && 
               FileManager.default.isReadableFile(atPath: configPath.path) {
                do {
                    let content = try String(contentsOf: configPath, encoding: .utf8)
                    // 简单的PATH提取（可以更复杂）
                    if let pathMatch = extractPathFromShellConfig(content) {
                        print("📝 从 \(configFile) 找到PATH: \(pathMatch)")
                        return pathMatch
                    }
                } catch {
                    print("⚠️ 无法读取 \(configFile): \(error.localizedDescription)")
                    continue
                }
            }
        }
        
        return ""
    }
    
    /// 从shell配置内容中提取PATH
    private func extractPathFromShellConfig(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 跳过注释行
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }
            
            // 查找PATH导出语句
            if trimmed.contains("PATH=") && (trimmed.hasPrefix("export PATH=") || trimmed.hasPrefix("PATH=")) {
                // 提取PATH值
                if let equalIndex = trimmed.firstIndex(of: "=") {
                    let pathValue = String(trimmed[trimmed.index(after: equalIndex)...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    
                    // 展开环境变量（简单处理$PATH和$HOME）
                    let expandedPath = pathValue
                        .replacingOccurrences(of: "$PATH", with: ProcessInfo.processInfo.environment["PATH"] ?? "")
                        .replacingOccurrences(of: "$HOME", with: FileManager.default.homeDirectoryForCurrentUser.path)
                    
                    if !expandedPath.isEmpty && expandedPath != pathValue {
                        return expandedPath
                    }
                }
            }
        }
        
        return nil
    }
    
    /// 查找命令的完整路径
    func findCommandPath(_ command: String) async -> String? {
        // 首先检查用户配置的路径
        if !toolSettings.isAutoDetectEnabled(command) {
            if let userPath = toolSettings.toolPaths[command], !userPath.isEmpty {
                if FileManager.default.isExecutableFile(atPath: userPath) {
                    return userPath
                }
            }
        }
        
        // 然后使用默认搜索路径
        let searchPaths = [
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/local/go/bin/\(command)",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go/bin/\(command)").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/\(command)").path,
        ]
        
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    /// 诊断开发环境工具安装情况
    func diagnoseEnvironment() async -> [String: String] {
        var diagnosis: [String: String] = [:]
        
        let tools = ["go", "npm", "pip", "cargo"]
        
        // 获取系统PATH信息
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fullPath = await getFullEnvironmentPath()
        
        diagnosis["系统PATH"] = systemPath.isEmpty ? "❌ 空" : "✅ \(systemPath)"
        diagnosis["完整PATH"] = fullPath
        
        for tool in tools {
            var toolInfo = ""
            
            // 检查用户是否配置了特定路径
            if !toolSettings.isAutoDetectEnabled(tool) {
                if let userPath = toolSettings.toolPaths[tool], !userPath.isEmpty {
                    if FileManager.default.isExecutableFile(atPath: userPath) {
                        toolInfo += "🎯 用户配置: \(userPath) ✅"
                    } else {
                        toolInfo += "🎯 用户配置: \(userPath) ❌ (文件不存在)"
                    }
                }
            }
            
            // 检查自动检测结果
            if let foundPath = await findCommandPath(tool) {
                if toolInfo.isEmpty {
                    toolInfo = "✅ 自动找到: \(foundPath)"
                } else {
                    toolInfo += "\n💡 自动检测: \(foundPath)"
                }
                
                // 检查工具版本
                if let version = await getToolVersion(tool, at: foundPath) {
                    toolInfo += " (版本: \(version))"
                }
            } else {
                if toolInfo.isEmpty {
                    toolInfo = "❌ 未找到"
                    
                    // 提供可能的安装位置提示
                    let possiblePaths = await suggestToolPaths(tool)
                    if !possiblePaths.isEmpty {
                        toolInfo += "\n💡 可能位置: \(possiblePaths.joined(separator: ", "))"
                    }
                } else {
                    toolInfo += "\n❌ 自动检测失败"
                }
            }
            
            diagnosis[tool] = toolInfo
        }
        
        return diagnosis
    }
    
    /// 获取工具版本信息
    private func getToolVersion(_ tool: String, at path: String) async -> String? {
        do {
            let result: CommandResult
            
            switch tool {
            case "go":
                result = try await executeCommand(path, arguments: ["version"])
            case "npm":
                result = try await executeCommand(path, arguments: ["--version"])
            case "pip":
                result = try await executeCommand(path, arguments: ["--version"])
            case "cargo":
                result = try await executeCommand(path, arguments: ["--version"])
            default:
                return nil
            }
            
            if result.isSuccess {
                // 简单提取版本号
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = output.components(separatedBy: .newlines)
                return lines.first?.components(separatedBy: " ").dropFirst().first
            }
        } catch {
            // 版本检测失败不是大问题
        }
        
        return nil
    }
    
    /// 为工具建议可能的安装路径
    private func suggestToolPaths(_ tool: String) async -> [String] {
        let possiblePaths: [String]
        
        switch tool {
        case "go":
            possiblePaths = [
                "/opt/homebrew/bin/go",
                "/usr/local/go/bin/go",
                "/usr/local/bin/go",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go/bin/go").path
            ]
        case "npm":
            possiblePaths = [
                "/opt/homebrew/bin/npm",
                "/usr/local/bin/npm",
                "/usr/local/node/bin/npm"
            ]
        case "pip":
            possiblePaths = [
                "/opt/homebrew/bin/pip3",
                "/usr/local/bin/pip3",
                "/usr/bin/python3 -m pip"
            ]
        case "cargo":
            possiblePaths = [
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/cargo").path,
                "/opt/homebrew/bin/cargo",
                "/usr/local/bin/cargo"
            ]
        default:
            return []
        }
        
        return possiblePaths.filter { path in
            FileManager.default.isExecutableFile(atPath: path) ||
            (path.contains("python3 -m pip") && FileManager.default.fileExists(atPath: "/usr/bin/python3"))
        }
    }
}

// MARK: - Data Structures

struct CommandResult {
    let exitCode: Int32
    let output: String
    let error: String
    let command: String
    let arguments: [String]
    
    var isSuccess: Bool {
        exitCode == 0
    }
    
    var fullCommand: String {
        ([command] + arguments).joined(separator: " ")
    }
}

// MARK: - Error Types

enum CommandError: LocalizedError {
    case timeout
    case executionFailed(CommandResult)
    case invalidOutput(String)
    case commandNotFound(String)
    case permissionDenied(String, String)
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "命令执行超时"
        case .executionFailed(let result):
            return "命令执行失败: \(result.fullCommand)\n错误: \(result.error)"
        case .invalidOutput(let message):
            return "命令输出格式无效: \(message)"
        case .commandNotFound(let command):
            return "命令未找到: \(command)"
        case .permissionDenied(let command, let error):
            return "权限不足，无法执行命令: \(command)\n\n这可能是因为macOS安全限制。\n请尝试以下解决方案：\n1. 在系统设置 > 隐私与安全性 > 完全磁盘访问权限中添加Janitor\n2. 或者关闭应用的沙盒模式\n\n详细错误: \(error)"
        }
    }
}