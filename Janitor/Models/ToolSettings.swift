import Foundation

class ToolSettings: ObservableObject {
    @Published var toolPaths: [String: String] = [:]
    @Published var autoDetect: [String: Bool] = [:]
    
    private let supportedTools = ["go", "npm", "pip", "cargo"]
    
    init() {
        loadSettings()
        setupDefaults()
    }
    
    // MARK: - 设置管理
    
    func setupDefaults() {
        for tool in supportedTools {
            if toolPaths[tool] == nil {
                toolPaths[tool] = ""
            }
            if autoDetect[tool] == nil {
                autoDetect[tool] = true
            }
        }
    }
    
    func setToolPath(_ tool: String, path: String) {
        toolPaths[tool] = path
        autoDetect[tool] = false
        saveSettings()
    }
    
    func enableAutoDetect(_ tool: String) {
        autoDetect[tool] = true
        toolPaths[tool] = ""
        saveSettings()
    }
    
    func disableAutoDetect(_ tool: String) {
        autoDetect[tool] = false
        // 保持现有路径不变，如果没有路径则设为空字符串
        if toolPaths[tool] == nil {
            toolPaths[tool] = ""
        }
        saveSettings()
    }
    
    func getToolDisplayPath(_ tool: String) -> String {
        if autoDetect[tool] == true {
            return "自动检测"
        }
        return toolPaths[tool] ?? ""
    }
    
    func isAutoDetectEnabled(_ tool: String) -> Bool {
        return autoDetect[tool] ?? true
    }
    
    // MARK: - 获取工具配置
    
    func getConfiguredTools() -> [String: String] {
        var configured: [String: String] = [:]
        
        for tool in supportedTools {
            if let isAuto = autoDetect[tool], isAuto {
                configured[tool] = "auto"
            } else if let path = toolPaths[tool], !path.isEmpty {
                configured[tool] = path
            }
        }
        
        return configured
    }
    
    // MARK: - 持久化
    
    private func saveSettings() {
        UserDefaults.standard.set(toolPaths, forKey: "ToolPaths")
        UserDefaults.standard.set(autoDetect, forKey: "AutoDetect")
    }
    
    private func loadSettings() {
        if let paths = UserDefaults.standard.object(forKey: "ToolPaths") as? [String: String] {
            toolPaths = paths
        }
        
        if let auto = UserDefaults.standard.object(forKey: "AutoDetect") as? [String: Bool] {
            autoDetect = auto
        }
    }
    
    // MARK: - 工具信息
    
    func getToolInfo(_ tool: String) -> ToolInfo? {
        return ToolInfo.getInfo(for: tool)
    }
    
    func getSupportedTools() -> [String] {
        return supportedTools
    }
}

// MARK: - 工具信息结构

struct ToolInfo {
    let name: String
    let displayName: String
    let iconName: String
    let description: String
    let commonPaths: [String]
    
    static func getInfo(for tool: String) -> ToolInfo? {
        switch tool {
        case "go":
            return ToolInfo(
                name: "go",
                displayName: "Go",
                iconName: "swift",
                description: "Go 编程语言工具链",
                commonPaths: [
                    "/usr/local/go/bin/go",
                    "/opt/homebrew/bin/go",
                    "/usr/local/bin/go"
                ]
            )
        case "npm":
            return ToolInfo(
                name: "npm",
                displayName: "npm",
                iconName: "shippingbox.fill",
                description: "Node.js 包管理器",
                commonPaths: [
                    "/usr/local/bin/npm",
                    "/opt/homebrew/bin/npm",
                    "/usr/bin/npm"
                ]
            )
        case "pip":
            return ToolInfo(
                name: "pip",
                displayName: "pip",
                iconName: "snake.fill",
                description: "Python 包管理器",
                commonPaths: [
                    "/usr/local/bin/pip",
                    "/opt/homebrew/bin/pip",
                    "/usr/bin/pip",
                    "/usr/local/bin/pip3",
                    "/opt/homebrew/bin/pip3"
                ]
            )
        case "cargo":
            return ToolInfo(
                name: "cargo",
                displayName: "Cargo",
                iconName: "crate.fill",
                description: "Rust 包管理器和构建工具",
                commonPaths: [
                    "~/.cargo/bin/cargo",
                    "/usr/local/bin/cargo",
                    "/opt/homebrew/bin/cargo"
                ]
            )
        default:
            return nil
        }
    }
}