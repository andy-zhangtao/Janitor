import SwiftUI
import AppKit

struct DirectorySelectionView: View {
    @ObservedObject var viewModel: JanitorViewModel
    @State private var showingDirectoryPicker = false
    @State private var validationResults: [URL: DirectoryValidationResult] = [:]
    
    private let scanner = FileSystemScanner()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("选择扫描目录")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("选择要扫描的开发项目根目录，Janitor将递归搜索其中的项目文件。")
                .font(.body)
                .foregroundColor(.secondary)
            
            Divider()
            
            // 建议目录
            if !suggestedDirectories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("建议目录:")
                        .font(.headline)
                    
                    ForEach(suggestedDirectories, id: \.self) { directory in
                        SuggestedDirectoryRow(
                            directory: directory,
                            isSelected: viewModel.scanDirectories.contains(directory),
                            validationResult: validationResults[directory],
                            onToggle: { isSelected in
                                if isSelected {
                                    viewModel.addScanDirectory(directory)
                                } else {
                                    viewModel.removeScanDirectory(directory)
                                }
                            }
                        )
                    }
                }
                
                Divider()
            }
            
            // 自定义目录
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("自定义目录:")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("添加目录...") {
                        showDirectoryPicker()
                    }
                    .buttonStyle(.borderless)
                }
                
                if !customDirectories.isEmpty {
                    ForEach(customDirectories, id: \.self) { directory in
                        CustomDirectoryRow(
                            directory: directory,
                            validationResult: validationResults[directory],
                            onRemove: {
                                viewModel.removeScanDirectory(directory)
                            }
                        )
                    }
                } else {
                    Text("暂无自定义目录")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack {
                Button("重新验证") {
                    validateAllDirectories()
                }
                .disabled(viewModel.scanDirectories.isEmpty)
                
                Spacer()
                
                Button("开始扫描") {
                    viewModel.startScan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartScan)
            }
        }
        .padding()
        .onAppear {
            loadSuggestedDirectories()
        }
    }
    
    // MARK: - Computed Properties
    
    private var suggestedDirectories: [URL] {
        scanner.getSuggestedDirectories()
    }
    
    private var customDirectories: [URL] {
        let suggested = Set(suggestedDirectories)
        return viewModel.scanDirectories.filter { !suggested.contains($0) }
    }
    
    private var canStartScan: Bool {
        !viewModel.scanDirectories.isEmpty && 
        !viewModel.isScanning &&
        viewModel.scanDirectories.allSatisfy { directory in
            validationResults[directory]?.isUsable ?? false
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSuggestedDirectories() {
        let suggested = suggestedDirectories
        
        Task {
            for directory in suggested {
                let result = scanner.validateDirectory(directory)
                await MainActor.run {
                    validationResults[directory] = result
                }
            }
        }
    }
    
    private func validateAllDirectories() {
        Task {
            for directory in viewModel.scanDirectories {
                let result = scanner.validateDirectory(directory)
                await MainActor.run {
                    validationResults[directory] = result
                }
            }
        }
    }
    
    private func showDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择要扫描的项目根目录"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 验证目录
                let result = scanner.validateDirectory(url)
                
                DispatchQueue.main.async {
                    self.validationResults[url] = result
                    
                    if result.isUsable {
                        self.viewModel.addScanDirectory(url)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct SuggestedDirectoryRow: View {
    let directory: URL
    let isSelected: Bool
    let validationResult: DirectoryValidationResult?
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { onToggle($0) }
            ))
            .toggleStyle(CheckboxToggleStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(directory.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(directory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let result = validationResult {
                ValidationIndicator(result: result)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CustomDirectoryRow: View {
    let directory: URL
    let validationResult: DirectoryValidationResult?
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(directory.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(directory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let result = validationResult {
                ValidationIndicator(result: result)
            }
            
            Button("移除") {
                onRemove()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

struct ValidationIndicator: View {
    let result: DirectoryValidationResult
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: result.icon)
                .foregroundColor(colorForResult(result))
            
            Text(result.message)
                .font(.caption)
                .foregroundColor(colorForResult(result))
        }
    }
    
    private func colorForResult(_ result: DirectoryValidationResult) -> Color {
        switch result {
        case .valid:
            return .green
        case .warning:
            return .orange
        case .invalid:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    DirectorySelectionView(viewModel: JanitorViewModel())
        .frame(width: 600, height: 500)
}