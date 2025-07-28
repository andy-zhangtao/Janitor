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
    
    // MARK: - Computed Properties
    var projectsByLanguage: [ProjectLanguage: [Project]] {
        Dictionary(grouping: projects) { $0.language }
    }
    
    var formattedTotalCacheSize: String {
        ByteCountFormatter.string(fromByteCount: totalCacheSize, countStyle: .file)
    }
    
    var canStartScan: Bool {
        !isScanning
    }
    
    // MARK: - Public Methods
    func startScan() {
        guard !isScanning else { return }
        
        Task {
            isScanning = true
            scanProgress = 0.0
            errorMessage = nil
            projects.removeAll()
            
            do {
                currentScanActivity = "开始扫描项目..."
                try await performScan()
                currentScanActivity = "扫描完成"
                scanProgress = 1.0
            } catch {
                errorMessage = "扫描失败: \(error.localizedDescription)"
                print("Scan error: \(error)")
            }
            
            isScanning = false
        }
    }
    
    func refreshProject(_ project: Project) {
        // TODO: 重新扫描单个项目
    }
    
    func clearErrorMessage() {
        errorMessage = nil
    }
    
    // MARK: - Private Methods
    private func performScan() async throws {
        // 扫描所有支持的语言
        let languages = ProjectLanguage.allCases
        let progressStep = 1.0 / Double(languages.count)
        
        for (index, language) in languages.enumerated() {
            currentScanActivity = "扫描 \(language.rawValue) 项目..."
            scanProgress = Double(index) * progressStep
            
            let languageProjects = try await scanProjectsForLanguage(language)
            projects.append(contentsOf: languageProjects)
            
            // 模拟扫描耗时
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }
        
        // 计算总缓存大小
        totalCacheSize = projects.reduce(0) { $0 + $1.cacheSize }
    }
    
    private func scanProjectsForLanguage(_ language: ProjectLanguage) async throws -> [Project] {
        // TODO: 实现具体的语言项目扫描逻辑
        // 现在返回模拟数据用于测试
        return generateMockProjects(for: language)
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