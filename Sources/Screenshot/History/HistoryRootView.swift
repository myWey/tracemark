import SwiftUI
import AppKit

public struct HistoryGroup: Identifiable {
    public let id = UUID()
    public let title: String
    public let records: [ScreenshotRecord]
}

func groupRecords(_ records: [ScreenshotRecord]) -> [HistoryGroup] {
    let calendar = Calendar.current
    var today: [ScreenshotRecord] = []
    var yesterday: [ScreenshotRecord] = []
    var earlier: [ScreenshotRecord] = []
    
    for r in records {
        if calendar.isDateInToday(r.timestamp) {
            today.append(r)
        } else if calendar.isDateInYesterday(r.timestamp) {
            yesterday.append(r)
        } else {
            earlier.append(r)
        }
    }
    
    var groups: [HistoryGroup] = []
    if !today.isEmpty {
        groups.append(HistoryGroup(title: LanguageManager.shared.localizedString(forKey: "今天"), records: today))
    }
    if !yesterday.isEmpty {
        groups.append(HistoryGroup(title: LanguageManager.shared.localizedString(forKey: "昨天"), records: yesterday))
    }
    if !earlier.isEmpty {
        groups.append(HistoryGroup(title: LanguageManager.shared.localizedString(forKey: "更早"), records: earlier))
    }
    return groups
}

public class DashboardRouter: ObservableObject {
    public static let shared = DashboardRouter()
    @Published public var selectedTab: DashboardRootView.DashboardTab? = .history
}

public struct DashboardRootView: View {
    @ObservedObject public var router = DashboardRouter.shared
    
    public enum DashboardTab: Hashable {
        case history
        case preferences
    }
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List(selection: $router.selectedTab) {
                NavigationLink(destination: HistoryContentView(), tag: DashboardTab.history, selection: $router.selectedTab) {
                    Label(LanguageManager.shared.localizedString(forKey: "历史记录"), systemImage: "clock")
                }
                NavigationLink(destination: PreferencesView(), tag: DashboardTab.preferences, selection: $router.selectedTab) {
                    Label(LanguageManager.shared.localizedString(forKey: "偏好设置"), systemImage: "gear")
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 150)
            
            // Default view for large screens
            HistoryContentView()
        }
        .frame(minWidth: 850, minHeight: 500)
    }
}

public struct HistoryContentView: View {
    @ObservedObject var viewModel = HistoryViewModel()
    
    public init() {}
    
    var groups: [HistoryGroup] {
        groupRecords(viewModel.records)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("历史记录")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    viewModel.loadRecords()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Timeline Scroll
            if viewModel.records.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                        .padding(.bottom, 8)
                    Text("暂无截图历史")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(groups) { group in
                            HStack(alignment: .top, spacing: 16) {
                                // 左侧时间轴节点与连线
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 10, height: 10)
                                        .background(
                                            Circle()
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                                        )
                                        .padding(.top, 6)
                                    
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 2)
                                }
                                .frame(width: 24)
                                
                                // 右侧内容：组标题与卡片网格
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(group.title)
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    let columns = [
                                        GridItem(.adaptive(minimum: 300, maximum: 340), spacing: 16)
                                    ]
                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(group.records) { record in
                                            HistoryItemView(record: record, viewModel: viewModel)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
    }
}

class HistoryViewModel: ObservableObject {
    @Published var records: [ScreenshotRecord] = []
    
    init() {
        loadRecords()
        NotificationCenter.default.addObserver(self, selector: #selector(handleHistoryUpdate), name: .HistoryDidUpdate, object: nil)
    }
    
    @objc private func handleHistoryUpdate() {
        loadRecords()
    }
    
    func loadRecords() {
        self.records = HistoryManager.shared.records
    }
    
    func deleteRecord(_ id: UUID) {
        HistoryManager.shared.removeRecord(id: id)
    }
}

struct HistoryItemView: View {
    let record: ScreenshotRecord
    let viewModel: HistoryViewModel
    @State private var image: NSImage?
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail container
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 160, height: 90)
                
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 90)
                        .cornerRadius(6)
                        .clipped()
                } else {
                    ProgressView()
                }
                
                // Hover overlay
                if isHovering {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 160, height: 90)
                    
                    HStack(spacing: 8) {
                        // Copy
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("复制到剪贴板")
                        
                        // Finder
                        Button(action: showInFinder) {
                            Image(systemName: "folder")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("在 Finder 中显示")
                        
                        // Pin
                        Button(action: pinRecord) {
                            Image(systemName: "pin")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("贴图置顶")
                        
                        // Re-edit
                        Button(action: reEditRecord) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("重新编辑标注")
                    }
                }
            }
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hover
                }
            }
            
            // Text Details & Actions
            VStack(alignment: .leading, spacing: 6) {
                Text(formatDate(record.timestamp))
                    .font(.system(size: 13, weight: .medium))
                
                Text(formatFileSize(record.fileSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isHovering {
                    Button(action: {
                        viewModel.deleteRecord(record.id)
                    }) {
                        Label("删除", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .frame(height: 90)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let img = HistoryManager.shared.image(for: record.fileName)
            DispatchQueue.main.async {
                self.image = img
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func copyToClipboard() {
        guard let img = image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([img])
    }
    
    private func showInFinder() {
        let url = HistoryManager.shared.fileURL(for: record.fileName)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func pinRecord() {
        let url = HistoryManager.shared.fileURL(for: record.fileName)
        if let nsImage = NSImage(contentsOf: url),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            PinManager.shared.pin(image: cgImage)
        }
    }
    
    private func reEditRecord() {
        let originalFileName = record.fileName.replacingOccurrences(of: ".png", with: "_original.png")
        let originalURL = HistoryManager.shared.fileURL(for: originalFileName)
        
        let fileManager = FileManager.default
        let urlToLoad = fileManager.fileExists(atPath: originalURL.path) ? originalURL : HistoryManager.shared.fileURL(for: record.fileName)
        
        guard let nsImage = NSImage(contentsOf: urlToLoad),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ [HistoryItem] 无法加载再编辑底图")
            return
        }
        
        let initialAnnotations = record.annotations ?? []
        
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenAnnotationCanvas"),
            object: nil,
            userInfo: [
                "image": cgImage,
                "annotations": initialAnnotations,
                "recordId": record.id
            ]
        )
    }
}

