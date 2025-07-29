import Foundation
import SwiftUI

@MainActor
class JanitorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var projects: [Project] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var currentScanActivity: String = ""
    @Published var selectedLanguage: ProjectLanguage? = nil
    @Published var selectedProject: Project? = nil
    @Published var totalCacheSize: Int64 = 0
    @Published var errorMessage: String? = nil
    @Published var scanDirectories: [URL] = []
    
    // MARK: - Private Properties
    private let scanner = FileSystemScanner()
    private let cleanupService = CleanupService()
    private let commandExecutor = CommandExecutor()
    
    // MARK: - Computed Properties
    var projectsByLanguage: [ProjectLanguage: [Project]] {
        Dictionary(grouping: projects) { $0.language }
    }
    
    var formattedTotalCacheSize: String {
        ByteCountFormatter.string(fromByteCount: totalCacheSize, countStyle: .file)
    }
    
    var canStartScan: Bool {
        !isScanning && !scanDirectories.isEmpty
    }
    
    // MARK: - Public Methods
    
    /// 添加扫描目录
    func addScanDirectory(_ url: URL) {
        if !scanDirectories.contains(url) {
            scanDirectories.append(url)
            saveScanDirectories()
        }
    }
    
    /// 移除扫描目录
    func removeScanDirectory(_ url: URL) {
        scanDirectories.removeAll { $0 == url }
        saveScanDirectories()
    }
    
    /// 开始扫描
    func startScan() {
        guard !isScanning && !scanDirectories.isEmpty else { return }
        
        Task {
            await MainActor.run {
                isScanning = true
                scanProgress = 0.0
                errorMessage = nil
                projects.removeAll()
                totalCacheSize = 0
                currentScanActivity = "准备开始扫描..."
            }
            
            do {
                try await performScan()
            } catch {
                await MainActor.run {
                    errorMessage = "扫描失败: \(error.localizedDescription)"
                    currentScanActivity = "扫描失败"
                }
                print("Scan error: \(error)")
            }
            
            await MainActor.run {
                isScanning = false
            }
        }
    }
    
    func refreshProject(_ project: Project) {
        // TODO: 重新扫描单个项目
    }
    
    func clearErrorMessage() {
        errorMessage = nil
    }
    
    /// 初始化扫描目录（应用启动时调用）
    func initializeScanDirectories() {
        loadScanDirectories()
        
        // 如果没有保存的目录，使用建议目录
        if scanDirectories.isEmpty {
            let suggested = scanner.getSuggestedDirectories()
            if !suggested.isEmpty {
                // 默认选择第一个建议目录
                scanDirectories = [suggested[0]]
                saveScanDirectories()
            }
        }
    }
    
    // MARK: - Private Methods
    private func performScan() async throws {
        // 扫描所有支持的语言
        let languages = ProjectLanguage.allCases
        let progressStep = 1.0 / Double(languages.count)
        
        for (index, language) in languages.enumerated() {
            await MainActor.run {
                currentScanActivity = "扫描 \(language.rawValue) 项目..."
                scanProgress = Double(index) * progressStep
            }
            
            let languageProjects = try await scanProjectsForLanguage(language)
            
            await MainActor.run {
                projects.append(contentsOf: languageProjects)
            }
            
            // 模拟扫描耗时以显示进度
            try await Task.sleep(nanoseconds: 800_000_000) // 0.8秒
        }
        
        await MainActor.run {
            // 计算总缓存大小
            totalCacheSize = projects.reduce(0) { $0 + $1.cacheSize }
            currentScanActivity = "扫描完成，共发现 \(projects.count) 个项目"
            scanProgress = 1.0
        }
    }
    
    private func scanProjectsForLanguage(_ language: ProjectLanguage) async throws -> [Project] {
        // 使用真实的扫描逻辑
        return try await scanner.scanProjects(in: scanDirectories, for: language)
    }
    
    // MARK: - Mock Data (临时用于开发测试)
    private func generateMockProjects(for language: ProjectLanguage) -> [Project] {
        let mockProjects: [Project] = [
            Project(
                name: "backend-service",
                path: URL(fileURLWithPath: "/Users/dev/work/backend-service"),
                language: language,
                lastModified: Date().addingTimeInterval(-2 * 24 * 3600), // 2天前
                dependencies: [],
                cacheSize: 180 * 1024 * 1024 // 180MB
            ),
            Project(
                name: "data-processor",
                path: URL(fileURLWithPath: "/Users/dev/personal/data-processor"),
                language: language,
                lastModified: Date().addingTimeInterval(-7 * 24 * 3600), // 1周前
                dependencies: [],
                cacheSize: 95 * 1024 * 1024 // 95MB
            )
        ]
        
        // 根据语言类型调整项目数量
        switch language {
        case .go:
            return mockProjects
        case .nodejs:
            return Array(mockProjects.prefix(1))
        case .python:
            return mockProjects
        case .rust:
            return Array(mockProjects.prefix(1))
        }
    }
    
    // MARK: - Persistence
    
    private func saveScanDirectories() {
        let urls = scanDirectories.map { $0.absoluteString }
        UserDefaults.standard.set(urls, forKey: "ScanDirectories")
    }
    
    private func loadScanDirectories() {
        guard let urlStrings = UserDefaults.standard.array(forKey: "ScanDirectories") as? [String] else {
            return
        }
        
        scanDirectories = urlStrings.compactMap { URL(string: $0) }
    }
    
    // MARK: - 清理功能
    
    /// 清理单个项目缓存
    func cleanProjectCache(_ project: Project) {
        Task {
            let result = await cleanupService.performCleanup(.projectCache(project))
            
            await MainActor.run {
                switch result {
                case .success(let message, let savedBytes):
                    // 更新项目缓存大小
                    if let index = projects.firstIndex(where: { $0.id == project.id }) {
                        var updatedProject = projects[index]
                        // 创建新的项目实例，因为Project是struct
                        let newProject = Project(
                            name: updatedProject.name,
                            path: updatedProject.path,
                            language: updatedProject.language,
                            lastModified: updatedProject.lastModified,
                            dependencies: updatedProject.dependencies,
                            cacheSize: max(0, updatedProject.cacheSize - savedBytes)
                        )
                        projects[index] = newProject
                        
                        // 更新总缓存大小
                        totalCacheSize = max(0, totalCacheSize - savedBytes)
                    }
                    
                    print("清理成功: \(message), 释放: \(ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file))")
                    
                case .failure(let error):
                    errorMessage = error
                    
                case .skipped(let reason):
                    print("跳过清理: \(reason)")
                }
            }
        }
    }
    
    /// 清理全局语言缓存
    func cleanGlobalCache(for language: ProjectLanguage) {
        Task {
            let result = await cleanupService.performCleanup(.globalCache(language))
            
            await MainActor.run {
                switch result {
                case .success(let message, _):
                    print("清理成功: \(message)")
                    
                case .failure(let error):
                    errorMessage = error
                    
                case .skipped(let reason):
                    print("跳过清理: \(reason)")
                }
            }
        }
    }
    
    /// 清理项目依赖
    func pruneDependencies(_ project: Project) {
        Task {
            let result = await cleanupService.performCleanup(.dependencyPrune(project))
            
            await MainActor.run {
                switch result {
                case .success(let message, _):
                    print("依赖清理成功: \(message)")
                    // 重新扫描项目以获取更新的依赖信息
                    refreshProject(project)
                    
                case .failure(let error):
                    errorMessage = error
                    
                case .skipped(let reason):
                    print("跳过依赖清理: \(reason)")
                }
            }
        }
    }
    
    /// 批量清理选中的项目
    func cleanSelectedProjects(_ projects: [Project]) {
        Task {
            var totalSaved: Int64 = 0
            var successCount = 0
            var failureCount = 0
            
            for project in projects {
                let result = await cleanupService.performCleanup(.projectCache(project))
                
                switch result {
                case .success(_, let savedBytes):
                    totalSaved += savedBytes
                    successCount += 1
                    
                case .failure(_):
                    failureCount += 1
                    
                case .skipped(_):
                    break
                }
            }
            
            await MainActor.run {
                totalCacheSize = max(0, totalCacheSize - totalSaved)
                
                let message = "批量清理完成: \(successCount)个成功, \(failureCount)个失败, 释放\(ByteCountFormatter.string(fromByteCount: totalSaved, countStyle: .file))"
                print(message)
            }
        }
    }
    
    @Published var diagnosisResult: String? = nil
    @Published var showingDiagnosis = false
    
    /// 诊断开发环境
    func diagnoseEnvironment() {
        Task {
            let diagnosis = await commandExecutor.diagnoseEnvironment()
            
            await MainActor.run {
                var message = "开发环境诊断结果:\n\n"
                for (tool, status) in diagnosis.sorted(by: { $0.key < $1.key }) {
                    if tool != "PATH" {
                        message += "\(tool): \(status)\n"
                    }
                }
                
                diagnosisResult = message
                showingDiagnosis = true
                print(message)
            }
        }
    }
}

// MARK: - Error Types
enum JanitorError: LocalizedError {
    case scanFailed(String)
    case permissionDenied
    case invalidPath(String)
    
    var errorDescription: String? {
        switch self {
        case .scanFailed(let reason):
            return "扫描失败: \(reason)"
        case .permissionDenied:
            return "权限不足，请检查文件访问权限"
        case .invalidPath(let path):
            return "无效路径: \(path)"
        }
    }
}