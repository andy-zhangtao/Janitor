import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            // 侧边栏
            SidebarView()
        } content: {
            // 主要内容区域
            MainContentView()
        } detail: {
            // 详情面板
            DetailView()
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct SidebarView: View {
    var body: some View {
        List {
            Section("Overview") {
                NavigationLink("Dashboard") {
                    DashboardView()
                }
            }
            
            Section("Languages") {
                NavigationLink("Go") {
                    LanguageView(language: "Go")
                }
                NavigationLink("Node.js") {
                    LanguageView(language: "Node.js")
                }
                NavigationLink("Python") {
                    LanguageView(language: "Python")
                }
                NavigationLink("Rust") {
                    LanguageView(language: "Rust")
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
                    Text("💾 0 GB")
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
                        // TODO: 实现扫描功能
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Text("Select a language from the sidebar to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DetailView: View {
    var body: some View {
        VStack {
            Text("Select an item to view details")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 300)
    }
}

struct DashboardView: View {
    var body: some View {
        VStack {
            Text("Dashboard")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            
            Text("This will show overall statistics and quick actions")
                .foregroundColor(.secondary)
        }
    }
}

struct LanguageView: View {
    let language: String
    
    var body: some View {
        VStack {
            Text("\(language) Projects")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            
            Text("This will show \(language) specific projects and dependencies")
                .foregroundColor(.secondary)
        }
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