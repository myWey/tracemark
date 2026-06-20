import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct HistoryGroup: Identifiable {
    public var id: String { title }
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

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

public struct DashboardRootView: View {
    @ObservedObject public var router = DashboardRouter.shared
    
    public enum DashboardTab: Hashable {
        case history
        case preferences
    }
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 8) {
                SidebarButton(title: LanguageManager.shared.localizedString(forKey: "历史记录"), icon: "clock", isSelected: router.selectedTab == .history || router.selectedTab == .none) {
                    router.selectedTab = .history
                }
                SidebarButton(title: LanguageManager.shared.localizedString(forKey: "偏好设置"), icon: "gear", isSelected: router.selectedTab == .preferences) {
                    router.selectedTab = .preferences
                }
                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 10)
            .frame(width: 160)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Detail
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                if router.selectedTab == .history || router.selectedTab == .none {
                    HistoryContentView()
                } else if router.selectedTab == .preferences {
                    PreferencesView()
                }
            }
        }
        .frame(minWidth: 850, minHeight: 500)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    if let data = data, let urlString = String(data: data, encoding: .utf8), let url = URL(string: urlString) {
                        if let nsImage = NSImage(contentsOf: url), let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: .openAnnotationCanvas,
                                    object: nil,
                                    userInfo: ["image": cgImage]
                                )
                            }
                        }
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let data = data, let nsImage = NSImage(data: data), let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .openAnnotationCanvas,
                                object: nil,
                                userInfo: ["image": cgImage]
                            )
                        }
                    }
                }
                return true
            }
            return false
        }
    }
}

public struct HistoryContentView: View {
    @StateObject var viewModel = HistoryViewModel()
    @State private var showingClearAlert = false
    
    public init() {}
    
    var groups: [HistoryGroup] {
        groupRecords(viewModel.records)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(LanguageManager.shared.localizedString(forKey: "历史记录"))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                Button(LanguageManager.shared.localizedString(forKey: viewModel.isManageMode ? "完成" : "批量管理")) {
                    withAnimation {
                        viewModel.isManageMode.toggle()
                        if !viewModel.isManageMode {
                            viewModel.selectedRecords.removeAll()
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                
                Button(action: {
                    viewModel.loadRecords()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ZStack(alignment: .bottom) {
                if viewModel.records.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                            .padding(.bottom, 8)
                        Text(LanguageManager.shared.localizedString(forKey: "暂无截图历史"))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(groups) { group in
                                HStack(alignment: .top, spacing: 16) {
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
                                    
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(group.title)
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        
                                        let columns = [
                                            GridItem(.adaptive(minimum: 160, maximum: 160), spacing: 20)
                                        ]
                                        LazyVGrid(columns: columns, spacing: 20) {
                                            ForEach(group.records) { record in
                                                HistoryItemView(record: record, viewModel: viewModel)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .padding(.bottom, viewModel.isManageMode ? 80 : 0)
                    }
                }
                
                if viewModel.isManageMode {
                    HStack(spacing: 16) {
                        Button(LanguageManager.shared.localizedString(forKey: "取消")) {
                            withAnimation {
                                viewModel.isManageMode = false
                                viewModel.selectedRecords.removeAll()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        
                        Button(LanguageManager.shared.localizedString(forKey: "Clear_All")) {
                            showingClearAlert = true
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                        
                        Button(LanguageManager.shared.localizedString(forKey: "Delete_Selected")) {
                            for id in viewModel.selectedRecords {
                                HistoryManager.shared.removeRecord(id: id)
                            }
                            viewModel.selectedRecords.removeAll()
                            viewModel.isManageMode = false
                            ToastManager.shared.showToast(message: LanguageManager.shared.localizedString(forKey: "已删除选中的记录"))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(viewModel.selectedRecords.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .disabled(viewModel.selectedRecords.isEmpty)
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
                    .shadow(radius: 5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .alert(isPresented: $showingClearAlert) {
                        Alert(
                            title: Text(LanguageManager.shared.localizedString(forKey: "Confirm_Clear")),
                            message: Text(LanguageManager.shared.localizedString(forKey: "Clear_All_Message")),
                            primaryButton: .destructive(Text(LanguageManager.shared.localizedString(forKey: "Clear"))) {
                                for record in viewModel.records {
                                    HistoryManager.shared.removeRecord(id: record.id)
                                }
                                viewModel.selectedRecords.removeAll()
                                viewModel.isManageMode = false
                                ToastManager.shared.showToast(message: LanguageManager.shared.localizedString(forKey: "Cleared_All_History"))
                            },
                            secondaryButton: .cancel(Text(LanguageManager.shared.localizedString(forKey: "Cancel")))
                        )
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
    }
}

class HistoryViewModel: ObservableObject {
    @Published var records: [ScreenshotRecord] = []
    @Published var isManageMode: Bool = false
    @Published var selectedRecords: Set<UUID> = []
    
    init() {
        loadRecords()
        NotificationCenter.default.addObserver(self, selector: #selector(handleHistoryUpdate), name: .HistoryDidUpdate, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleHistoryUpdate() {
        loadRecords()
    }
    
    func loadRecords() {
        self.records = HistoryManager.shared.records
        let existingIds = Set(records.map { $0.id })
        selectedRecords.formIntersection(existingIds)
        if records.isEmpty {
            isManageMode = false
        }
    }
    
    func deleteRecord(_ id: UUID) {
        HistoryManager.shared.removeRecord(id: id)
    }
    
    func clearAll() {
        records.forEach { HistoryManager.shared.removeRecord(id: $0.id) }
        selectedRecords.removeAll()
        isManageMode = false
    }
    
    func deleteSelected() {
        selectedRecords.forEach { HistoryManager.shared.removeRecord(id: $0) }
        selectedRecords.removeAll()
        isManageMode = false
    }
    
    func toggleSelection(_ id: UUID) {
        if selectedRecords.contains(id) {
            selectedRecords.remove(id)
        } else {
            selectedRecords.insert(id)
        }
    }
}

struct HistoryItemView: View {
    let record: ScreenshotRecord
    @ObservedObject var viewModel: HistoryViewModel
    @State private var image: NSImage?
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .onDrag {
                            let url = HistoryManager.shared.getSavedImageURL(for: record)
                            let provider = NSItemProvider()
                            provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [.openInPlace], visibility: .all) { completion in
                                completion(url, true, nil)
                                return nil
                            }
                            return provider
                        }
                } else {
                    ProgressView()
                }
                
                if isHovering && !viewModel.isManageMode {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 160, height: 90)
                    
                    HStack(spacing: 8) {
                        Spacer()
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("复制截图")
                        
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
                        Spacer()
                    }
                    .frame(width: 160, height: 90, alignment: .center)
                }
                
                if viewModel.isManageMode {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.selectedRecords.contains(record.id) ? Color.blue.opacity(0.3) : Color.black.opacity(0.1))
                        .frame(width: 160, height: 90)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: viewModel.selectedRecords.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(viewModel.selectedRecords.contains(record.id) ? .white : .white.opacity(0.8))
                                .background(Circle().fill(viewModel.selectedRecords.contains(record.id) ? Color.blue : Color.black.opacity(0.3)))
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hover
                }
            }
            .onTapGesture {
                if viewModel.isManageMode {
                    viewModel.toggleSelection(record.id)
                }
            }
            
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDate(record.timestamp))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(formatFileSize(record.fileSize))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !viewModel.isManageMode {
                    Button(action: {
                        viewModel.deleteRecord(record.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isHovering ? Color.red.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(isHovering ? .red : .secondary)
                    .help("删除")
                }
            }
        }
        .frame(width: 160)
        .padding(.vertical, 4)
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Load a 320px thumbnail instead of the full size image to prevent frame drops
            let img = HistoryManager.shared.thumbnail(for: record.fileName, maxSize: 320)
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
        let url = HistoryManager.shared.fileURL(for: record.fileName)
        guard let fullImage = NSImage(contentsOf: url) else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let pbItem = NSPasteboardItem()
        if let tiffData = fullImage.tiffRepresentation {
            pbItem.setData(tiffData, forType: .tiff)
        }
        
        pasteboard.writeObjects([pbItem])
        
        DispatchQueue.main.async {
            ToastManager.shared.showToast(message: LanguageManager.shared.localizedString(forKey: "已复制到剪贴板"))
        }
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
            AppLogger.history.error("❌ [HistoryItem] 无法加载再编辑底图")
            return
        }
        
        let initialAnnotations = record.annotations ?? []
        AnnotationManager.shared.showAnnotationCanvas(for: cgImage, initialAnnotations: initialAnnotations, recordId: record.id)
    }
}
