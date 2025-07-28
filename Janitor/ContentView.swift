import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = JanitorViewModel()
    
    var body: some View {
        NavigationSplitView {
            // 侧边栏
            SidebarView(viewModel: viewModel)
        } content: {
            // 主要内容区域
            MainContentView(viewModel: viewModel)
        } detail: {
            // 详情面板
            DetailView(viewModel: viewModel)
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("扫描错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") {
                viewModel.clearErrorMessage()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .alert("开发环境诊断", isPresented: $viewModel.showingDiagnosis) {
            Button("确定") {
                viewModel.showingDiagnosis = false
            }
        } message: {
            if let result = viewModel.diagnosisResult {
                Text(result)
            }
        }
        .onAppear {
            viewModel.initializeScanDirectories()
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        List {
            Section("Overview") {
                NavigationLink("Dashboard") {
                    DashboardView(viewModel: viewModel)
                }
            }
            
            Section("Languages") {
                ForEach(ProjectLanguage.allCases, id: \.self) { language in
                    NavigationLink(destination: LanguageView(language: language, viewModel: viewModel)) {
                        HStack {
                            Image(systemName: language.iconName)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(language.rawValue)
                                if let projects = viewModel.projectsByLanguage[language] {
                                    Text("\(projects.count) projects")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            
            Section("Settings") {
                NavigationLink("扫描目录配置") {
                    SettingsView(viewModel: viewModel)
                }
                
                NavigationLink("开发工具配置") {
                    ToolConfigurationView(viewModel: viewModel)
                }
                
                Button("诊断开发环境") {
                    viewModel.diagnoseEnvironment()
                }
            }
        }
        .navigationTitle("Janitor")
        .frame(minWidth: 180)
    }
}

struct MainContentView: View {
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        VStack {
            if viewModel.isScanning {
                ScanProgressView(viewModel: viewModel)
            } else {
                DashboardContentView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DashboardContentView: View {
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        VStack {
            Image(systemName: "trash.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding()
            
            Text("🧹 Janitor")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Keep Your Dev Environment Clean")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)
            
            HStack(spacing: 20) {
                VStack {
                    Text("💾 \(viewModel.formattedTotalCacheSize)")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Cleanable Space")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                VStack {
                    Button("🔍 Start Scan") {
                        viewModel.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.canStartScan)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            if !viewModel.projects.isEmpty {
                Text("Found \(viewModel.projects.count) projects across \(viewModel.projectsByLanguage.keys.count) languages")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top)
            } else if viewModel.scanDirectories.isEmpty {
                VStack(spacing: 8) {
                    Text("请先选择要扫描的目录")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    NavigationLink("配置扫描目录") {
                        DirectorySelectionView(viewModel: viewModel)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top)
            } else {
                Text("Click 'Start Scan' to analyze your development environment")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top)
            }
        }
    }
}

struct ScanProgressView: View {
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.scanProgress)
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(2.0)
            
            Text("Scanning...")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(viewModel.currentScanActivity)
                .font(.body)
                .foregroundColor(.secondary)
            
            Text("\(Int(viewModel.scanProgress * 100))% Complete")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

struct DetailView: View {
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        VStack {
            if let selectedProject = viewModel.selectedProject {
                ProjectDetailView(project: selectedProject, viewModel: viewModel)
            } else {
                Text("Select a project to view details")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 300)
    }
}

struct ProjectDetailView: View {
    let project: Project
    @ObservedObject var viewModel: JanitorViewModel
    @State private var showingCleanConfirmation = false
    @State private var showingPruneConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: project.language.iconName)
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(project.language.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Path", value: project.path.path)
                DetailRow(label: "Last Modified", value: project.formattedLastModified)
                DetailRow(label: "Cache Size", value: project.formattedCacheSize)
                DetailRow(label: "Status", value: project.isActive ? "Active" : "Inactive")
                DetailRow(label: "Dependencies", value: "\(project.dependencies.count) packages")
            }
            
            Divider()
            
            // 清理操作按钮
            VStack(alignment: .leading, spacing: 8) {
                Text("清理操作")
                    .font(.headline)
                
                HStack {
                    if project.cacheSize > 0 {
                        Button("清理缓存") {
                            showingCleanConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    if project.language == .go || project.language == .nodejs {
                        Button("清理依赖") {
                            showingPruneConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .alert("确认清理缓存", isPresented: $showingCleanConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                viewModel.cleanProjectCache(project)
            }
        } message: {
            Text("确定要清理 \(project.name) 的缓存吗？\n将释放约 \(project.formattedCacheSize) 的空间。")
        }
        .alert("确认清理依赖", isPresented: $showingPruneConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                viewModel.pruneDependencies(project)
            }
        } message: {
            Text("确定要清理 \(project.name) 的无用依赖吗？\n这将执行 \(project.language == .go ? "go mod tidy" : "npm prune") 命令。")
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

struct DashboardView: View {
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        DashboardContentView(viewModel: viewModel)
    }
}

struct LanguageView: View {
    let language: ProjectLanguage
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        VStack {
            if let projects = viewModel.projectsByLanguage[language], !projects.isEmpty {
                ProjectListView(projects: projects, viewModel: viewModel)
            } else {
                EmptyProjectsView(language: language, viewModel: viewModel)
            }
        }
        .navigationTitle("\(language.rawValue) Projects")
    }
}

struct ProjectListView: View {
    let projects: [Project]
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        List(projects) { project in
            ProjectRowView(project: project, viewModel: viewModel)
                .onTapGesture {
                    viewModel.selectedProject = project
                }
        }
    }
}

struct ProjectRowView: View {
    let project: Project
    @ObservedObject var viewModel: JanitorViewModel
    @State private var showingCleanConfirmation = false
    
    var body: some View {
        HStack {
            Image(systemName: project.language.iconName)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(project.name)
                    .font(.headline)
                Text(project.path.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(project.formattedCacheSize)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(project.formattedLastModified)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 清理按钮
            if project.cacheSize > 0 {
                Button("清理") {
                    showingCleanConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .alert("确认清理", isPresented: $showingCleanConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                viewModel.cleanProjectCache(project)
            }
        } message: {
            Text("确定要清理 \(project.name) 的缓存吗？\n将释放约 \(project.formattedCacheSize) 的空间。")
        }
    }
}

struct EmptyProjectsView: View {
    let language: ProjectLanguage
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        VStack {
            Image(systemName: language.iconName)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .padding()
            
            Text("No \(language.rawValue) Projects Found")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Run a scan to discover \(language.rawValue) projects in your system")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Start Scan") {
                viewModel.startScan()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStartScan)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: JanitorViewModel
    
    var body: some View {
        DirectorySelectionView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}