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
                NavigationLink("Preferences") {
                    SettingsView()
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
                ProjectDetailView(project: selectedProject)
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
            }
            
            Spacer()
        }
        .padding()
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
            ProjectRowView(project: project)
                .onTapGesture {
                    viewModel.selectedProject = project
                }
        }
    }
}

struct ProjectRowView: View {
    let project: Project
    
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
        }
        .padding(.vertical, 4)
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
    var body: some View {
        VStack {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            
            Text("This will show application preferences")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}