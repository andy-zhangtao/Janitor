# Janitor macOS App UI/UX Design Specification

## Design Philosophy

### Core Principles
- **Safety First**: Destructive actions require clear visual warnings and multiple confirmations
- **Progressive Disclosure**: Show overview first, then allow users to drill down into details
- **Native macOS Experience**: Leverage SwiftUI, SF Symbols, and macOS design patterns
- **Developer-Focused**: Understand technical concepts like dependency caching and project structures

## Main Interface Architecture

### Layout Structure: NavigationSplitView (Three-Column)
```
┌─────────────┬─────────────────────────┬─────────────────┐
│  Sidebar    │    Main Content Area    │  Detail Panel   │
│  (180pt)    │     (flexible width)    │    (300pt)      │
│             │                         │                 │
│ • Overview  │   Project List          │  Dependency     │
│ • Go        │       OR                │  Details        │
│ • Node.js   │   Cleanup Preview       │      OR         │
│ • Python    │       OR                │  Cleanup        │
│ • Rust      │   Scan Progress         │  Confirmation   │
│ • Settings  │                         │                 │
└─────────────┴─────────────────────────┴─────────────────┘
```

## Screen-by-Screen Design

### 1. Welcome/Overview Screen
**Purpose**: First impression, quick actions, system overview

**Visual Hierarchy**:
- Large app icon and title at top
- Prominent scan button (primary CTA)
- Quick stats in card format
- Language ecosystem overview

**Layout**:
```
┌─────────────────────────────────────────────────────────┐
│                    🧹 Janitor                          │
│              Keep Your Dev Environment Clean            │
│                                                        │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │  💾 61.4 GB     │  │  🔍 Quick Scan   │              │
│  │  Cleanable      │  │                 │              │
│  │  Space Found    │  │  [Start Scan]   │              │
│  └─────────────────┘  └─────────────────┘              │
│                                                        │
│  Development Projects Found:                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│  │    Go    │ │  Node.js │ │  Python  │ │   Rust   │   │
│  │ 📦 24.6GB│ │ 📦 73.5MB│ │ 📦 3.2GB │ │ 📦 1.1GB │   │
│  │ 15 proj  │ │ 8 proj   │ │ 12 proj  │ │ 3 proj   │   │
│  │ [Clean]✓ │ │ [Clean]✓ │ │ [Clean]✓ │ │ [Skip]   │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │
└─────────────────────────────────────────────────────────┘
```

**Interactive Elements**:
- Primary button: Large, blue "Start Scan" button
- Card buttons: Each language card is clickable for detailed view
- Toggle switches: Enable/disable cleanup for each language

### 2. Scanning Progress Screen
**Purpose**: Show real-time scanning progress with detailed feedback

**Visual Elements**:
- Circular progress indicator (center focus)
- Current activity description
- Hierarchical progress breakdown
- Pause/cancel controls

**Layout**:
```
┌─────────────────────────────────────────────────────────┐
│                                                        │
│                     ◐ 67%                            │
│                   Scanning...                         │
│                                                        │
│              Analyzing Go Dependencies                  │
│            /Users/dev/backend-service                  │
│                                                        │
│  Progress Details:                                     │
│  ✅ Completed: 15 Go Projects                          │
│  🔄 Processing: Node.js Projects                       │
│  ⏳ Pending: Python, Rust Projects                     │
│                                                        │
│              [Pause Scan]   [Cancel]                   │
└─────────────────────────────────────────────────────────┘
```

**Animation Guidelines**:
- Circular progress: Smooth 60fps animation
- Status updates: Fade transition between states
- File path: Truncate with ellipsis if too long

### 3. Cleanup Preview Screen
**Purpose**: Show categorized cleanup recommendations with safety levels

**Information Architecture**:
- Total savings prominently displayed
- Items grouped by safety level (safe, caution, manual review)
- Expandable sections for detailed inspection
- Clear action buttons

**Layout**:
```
┌─────────────────────────────────────────────────────────┐
│  🗑️ Cleanup Preview - Will Save 28.1 GB                │
│  ═══════════════════════════════════════════════════    │
│                                                        │
│  Safe to Clean (Recommended):                          │
│  ┌─ 🟢 Go Module Cache ──────────── 24.6 GB ─────── ✅ │
│  │   • 12 orphaned modules (projects deleted)          │
│  │   • 8 duplicate versions                            │
│  └─ Expand for details ▼                               │
│                                                        │
│  ┌─ 🟡 Node.js Cache ────────────── 73.5 MB ─────── ✅ │
│  │   • npm cache (unused for 6 months)                │
│  └─ Expand for details ▼                               │
│                                                        │
│  Requires Confirmation:                                 │
│  ┌─ 🟠 Python Virtual Envs ──────── 3.2 GB ─────── ⚪ │
│  │   • Contains recently modified projects             │
│  └─ Manual selection ▼                                 │
│                                                        │
│              [🔥 Start Cleanup]   [Advanced]           │
└─────────────────────────────────────────────────────────┘
```

**Color Coding**:
- Green (🟢): Safe to clean, recommended
- Yellow (🟡): Caution, check before cleaning  
- Orange (🟠): Requires manual review
- Red: Dangerous operations (rare, for system files)

### 4. Project List View (Language-Specific)
**Purpose**: Detailed view of projects for a specific language

**Table Structure**:
- Project name and path
- Last modified date
- Cache size
- Status indicators (active/orphaned)

**Layout**:
```
┌─────────────────────────────────────────────────────────┐
│  Go Projects (15) • Cache Usage: 1.2 GB                │
│  ┌─ Search: [________________] 🔍                       │
│  │                                                     │
│  ├─ 📦 backend-service           💾 180 MB             │
│  │   └─ /Users/dev/work/backend                        │
│  │   └─ Last modified: 2 days ago                      │
│  │                                                     │
│  ├─ 📦 data-processor           💾 95 MB               │
│  │   └─ /Users/dev/personal/processor                 │
│  │   └─ Last modified: 1 week ago                      │
│  │                                                     │
│  ├─ 📦 old-project              💾 320 MB              │
│  │   └─ /Users/dev/archive/old (deleted)              │
│  │   └─ ⚠️ Project missing, safe to clean              │
│  └─ ...                                               │
└─────────────────────────────────────────────────────────┘
```

### 5. Detail Panel (Context-Sensitive)
**Purpose**: Show relevant details based on current selection

**For Project Selection**:
```
┌─────────────────────────────────────────────────────────┐
│  backend-service                                       │
│  ════════════════════════════════════════════════════   │
│                                                        │
│  📍 Path: /Users/dev/work/backend                      │
│  📅 Modified: 2 days ago                               │
│  💾 Cache: 180 MB (12 dependencies)                    │
│                                                        │
│  Dependencies:                                         │
│  ├─ gin-gonic/gin v1.9.1        15 MB                 │
│  ├─ go-redis/redis v9.0.5       8 MB                  │
│  ├─ golang.org/x/crypto v0.10.0  22 MB                │
│  └─ ...                                               │
│                                                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │  [🗑️ Clean Project Cache]                       │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Interaction Patterns

### Navigation Flow
1. **Welcome** → Choose scan type → **Scanning** → **Results**
2. **Results** → Select language → **Project List** → **Project Details**
3. **Results** → **Cleanup Preview** → **Confirmation** → **Execution**

### Key Interactions
- **Primary Actions**: Large, prominent buttons (Start Scan, Clean, etc.)
- **Secondary Actions**: Smaller buttons or links (Cancel, Advanced, etc.)
- **Dangerous Actions**: Red color, confirmation dialogs
- **Toggle States**: Checkboxes and switches for enable/disable

### Keyboard Shortcuts
- `⌘R`: Refresh/Rescan
- `⌘⌫`: Clean selected items
- `⌘,`: Preferences
- `⌘F`: Search within current view
- `Space`: Quick preview of selected item

## Visual Design System

### Typography
- **Headlines**: SF Pro Display, Bold, 22pt
- **Body Text**: SF Pro Text, Regular, 13pt
- **Captions**: SF Pro Text, Regular, 11pt
- **Code/Paths**: SF Mono, Regular, 11pt

### Spacing
- **Section Margins**: 20pt
- **Card Padding**: 16pt
- **Button Padding**: 8pt vertical, 16pt horizontal
- **List Item Height**: 44pt minimum (touch target)

### Colors (System Colors)
- **Primary**: systemBlue
- **Success**: systemGreen
- **Warning**: systemOrange
- **Danger**: systemRed
- **Background**: systemBackground
- **Secondary Background**: secondarySystemBackground

### Icons (SF Symbols)
- **Scan**: magnifyingglass
- **Clean**: trash
- **Project**: folder
- **Cache**: externaldrive
- **Warning**: exclamationmark.triangle
- **Success**: checkmark.circle

## States and Feedback

### Loading States
- Skeleton screens during initial scan
- Progress indicators for long operations
- Pulse animation for active scanning

### Empty States
- No projects found: Friendly illustration + guidance
- Clean system: Celebration message
- Error state: Clear error message + retry option

### Error Handling
- Permission denied: Guide to system preferences
- File access error: Suggest running with elevated permissions
- Network issues: Offline mode indication

## Accessibility Considerations

### VoiceOver Support
- All interactive elements have descriptive labels
- Dynamic content changes are announced
- Progress updates are spoken

### Keyboard Navigation
- All functions accessible via keyboard
- Clear focus indicators
- Logical tab order

### Visual Accessibility
- High contrast mode support
- Dynamic Type support
- Color-blind friendly color choices
- Minimum 44pt touch targets

This design specification provides a comprehensive foundation for implementing Janitor's UI while maintaining consistency with macOS design patterns and ensuring excellent user experience for developers managing their local development environments.
