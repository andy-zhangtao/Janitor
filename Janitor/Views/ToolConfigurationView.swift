import SwiftUI
import AppKit

struct ToolConfigurationView: View {
    @StateObject private var toolSettings = ToolSettings()
    @ObservedObject var viewModel: JanitorViewModel
    @State private var showingFilePicker = false
    @State private var selectedTool: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("开发工具配置")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("配置各个开发工具的路径，或选择自动检测。")
                .font(.body)
                .foregroundColor(.secondary)
            
            Divider()
            
            // 工具列表
            VStack(alignment: .leading, spacing: 12) {
                ForEach(toolSettings.getSupportedTools(), id: \.self) { tool in
                    ToolConfigurationRow(
                        tool: tool,
                        toolSettings: toolSettings,
                        onSelectPath: {
                            selectedTool = tool
                            showingFilePicker = true
                        }
                    )
                }
            }
            
            Divider()
            
            // 诊断和快速设置按钮
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("🔍 诊断开发环境") {
                        viewModel.diagnoseEnvironment()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("⚡ 快速检测工具") {
                        quickDetectTools()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    Button("重置为默认") {
                        resetToDefaults()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                
                Text("💡 如果诊断显示工具未找到，请使用\"快速检测工具\"或手动指定路径")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.executable, .unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result, for: selectedTool)
        }
    }
    
    private func resetToDefaults() {
        for tool in toolSettings.getSupportedTools() {
            toolSettings.enableAutoDetect(tool)
        }
    }
    
    private func quickDetectTools() {
        Task {
            let commandExecutor = CommandExecutor()
            
            for tool in toolSettings.getSupportedTools() {
                // 只为那些当前未配置或配置有问题的工具进行快速检测
                let shouldDetect: Bool
                
                if toolSettings.isAutoDetectEnabled(tool) {
                    shouldDetect = true
                } else if let userPath = toolSettings.toolPaths[tool], !userPath.isEmpty {
                    shouldDetect = !FileManager.default.isExecutableFile(atPath: userPath)
                } else {
                    shouldDetect = true
                }
                
                if shouldDetect {
                    if let foundPath = await commandExecutor.findCommandPath(tool) {
                        await MainActor.run {
                            toolSettings.setToolPath(tool, path: foundPath)
                        }
                    }
                }
            }
            
            // 检测完成后显示诊断信息
            await MainActor.run {
                viewModel.diagnoseEnvironment()
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>, for tool: String) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                toolSettings.setToolPath(tool, path: url.path)
            }
        case .failure(let error):
            print("文件选择错误: \(error)")
        }
    }
}

struct ToolConfigurationRow: View {
    let tool: String
    @ObservedObject var toolSettings: ToolSettings
    let onSelectPath: () -> Void
    
    @State private var testResult: String? = nil
    @State private var isTestingTool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = toolSettings.getToolInfo(tool) {
                HStack {
                    Image(systemName: info.iconName)
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.displayName)
                            .font(.headline)
                        Text(info.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("自动检测", isOn: Binding(
                            get: { toolSettings.isAutoDetectEnabled(tool) },
                            set: { enabled in
                                if enabled {
                                    toolSettings.enableAutoDetect(tool)
                                } else {
                                    toolSettings.disableAutoDetect(tool)
                                }
                            }
                        ))
                        .toggleStyle(CheckboxToggleStyle())
                        
                        if !toolSettings.isAutoDetectEnabled(tool) {
                            HStack {
                                Text("路径:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextField("选择工具路径", text: Binding(
                                    get: { toolSettings.toolPaths[tool] ?? "" },
                                    set: { toolSettings.setToolPath(tool, path: $0) }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Button("浏览...") {
                                    onSelectPath()
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Text("将自动在系统PATH中查找")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                    
                    Spacer()
                    
                    // 测试按钮
                    VStack(alignment: .trailing, spacing: 4) {
                        Button(isTestingTool ? "测试中..." : "🧪 测试") {
                            testTool()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTestingTool)
                        
                        if let result = testResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("✅") ? .green : .red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(.leading, 24)
                
                // 常见路径提示
                if !toolSettings.isAutoDetectEnabled(tool) {
                    if let info = toolSettings.getToolInfo(tool) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("常见路径:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 24)
                            
                            ForEach(info.commonPaths, id: \.self) { path in
                                HStack {
                                    Text("• \(path)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 32)
                                    
                                    Spacer()
                                    
                                    if FileManager.default.fileExists(atPath: path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)) {
                                        Button("使用此路径") {
                                            let expandedPath = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                                            toolSettings.setToolPath(tool, path: expandedPath)
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Divider()
                    .padding(.top, 8)
            }
        }
    }
    
    private func testTool() {
        isTestingTool = true
        testResult = nil
        
        Task {
            let commandExecutor = CommandExecutor()
            
            do {
                // 检查工具是否存在
                let exists = await commandExecutor.commandExists(tool)
                
                if exists {
                    // 尝试获取版本信息来进一步验证
                    let version = await getToolVersion(tool, commandExecutor: commandExecutor)
                    
                    await MainActor.run {
                        if let version = version {
                            testResult = "✅ 可用 (版本: \(version))"
                        } else {
                            testResult = "✅ 工具存在但无法获取版本"
                        }
                        isTestingTool = false
                    }
                } else {
                    await MainActor.run {
                        if toolSettings.isAutoDetectEnabled(tool) {
                            testResult = "❌ 自动检测失败\n工具未安装或不在PATH中"
                        } else {
                            let userPath = toolSettings.toolPaths[tool] ?? ""
                            testResult = "❌ 路径无效\n\(userPath)"
                        }
                        isTestingTool = false
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ 测试失败: \(error.localizedDescription)"
                    isTestingTool = false
                }
            }
        }
    }
    
    private func getToolVersion(_ tool: String, commandExecutor: CommandExecutor) async -> String? {
        do {
            let result: CommandResult
            
            switch tool {
            case "go":
                result = try await commandExecutor.executeCommand("go", arguments: ["version"])
            case "npm":
                result = try await commandExecutor.executeCommand("npm", arguments: ["--version"])
            case "pip":
                result = try await commandExecutor.executeCommand("pip", arguments: ["--version"])
            case "cargo":
                result = try await commandExecutor.executeCommand("cargo", arguments: ["--version"])
            default:
                return nil
            }
            
            if result.isSuccess {
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = output.components(separatedBy: .newlines)
                
                // 提取版本号
                print("🔍 解析版本号 - 工具: \(tool), 输出: \(output)")
                switch tool {
                case "go":
                    // go version go1.21.0 darwin/arm64
                    let components = lines.first?.components(separatedBy: " ") ?? []
                    print("🔍 Go 版本解析 - 组件: \(components)")
                    if components.count >= 3 {
                        let versionWithPrefix = components[2]
                        let version = versionWithPrefix.replacingOccurrences(of: "go", with: "")
                        print("🔍 Go 版本解析结果: \(version)")
                        return version
                    }
                case "npm":
                    // 直接是版本号
                    return lines.first
                case "pip":
                    // pip 23.0.1 from /usr/local/lib/python3.11/site-packages/pip
                    let components = lines.first?.components(separatedBy: " ") ?? []
                    if components.count >= 2 {
                        return components[1]
                    }
                case "cargo":
                    // cargo 1.70.0 (ec8a8a0ca 2023-04-25)
                    let components = lines.first?.components(separatedBy: " ") ?? []
                    if components.count >= 2 {
                        return components[1]
                    }
                default:
                    return lines.first
                }
            }
        } catch {
            print("获取版本失败: \(error)")
        }
        
        return nil
    }
}

#Preview {
    ToolConfigurationView(viewModel: JanitorViewModel())
        .frame(width: 600, height: 500)
}