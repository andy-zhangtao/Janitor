import Foundation

class CommandExecutor {
    
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
        
        // 配置进程
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
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
            throw CommandError.executionFailed(result)
        }
        
        return result
    }
    
    /// 检查命令是否存在
    func commandExists(_ command: String) async -> Bool {
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
    
    /// 获取Node.js包信息
    func getNpmPackages(in projectPath: URL) async throws -> [String] {
        let result = try await executeCommand(
            "npm",
            arguments: ["list", "--depth=0", "--json"],
            workingDirectory: projectPath
        )
        
        // 解析JSON输出
        guard let data = result.output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = json["dependencies"] as? [String: Any] else {
            return []
        }
        
        return Array(dependencies.keys)
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
        }
    }
}