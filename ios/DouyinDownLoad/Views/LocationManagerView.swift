import SwiftUI
import UIKit

struct LocationManagerView: View {
    @StateObject private var viewModel = LocationManagerViewModel()
    @State private var editingLocation: SavedLocation?
    @State private var showEditor = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                Text("本功能为坐标管家。iOS 18 非越狱设备无法由 app 直接修改系统定位。请配合 iAnyGo / 3uTools / Xcode 等工具使用：长按坐标可复制 lat,lng 或导出 GPX 文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("我的坐标") {
                if viewModel.locations.isEmpty {
                    Text("还没有保存坐标，点右上角 + 新增")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(viewModel.locations) { loc in
                        row(for: loc)
                    }
                    .onDelete(perform: viewModel.delete(at:))
                }
            }
        }
        .navigationTitle("坐标管家")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingLocation = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            LocationEditorView(original: editingLocation) { saved in
                viewModel.upsert(saved)
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: shareItems)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func row(for loc: SavedLocation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc.name).font(.body)
            Text(loc.coordinateText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.delete(id: loc.id)
            } label: { Label("删除", systemImage: "trash") }
            Button {
                editingLocation = loc
                showEditor = true
            } label: { Label("编辑", systemImage: "pencil") }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = loc.coordinateText
                showToast("已复制 \(loc.coordinateText)")
            } label: {
                Label("复制 lat,lng", systemImage: "doc.on.doc")
            }
            Button {
                exportGPX(loc)
            } label: {
                Label("导出 GPX", systemImage: "square.and.arrow.up")
            }
            Button {
                editingLocation = loc
                showEditor = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                viewModel.delete(id: loc.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func exportGPX(_ loc: SavedLocation) {
        do {
            let url = try GPXExporter.writeToTempFile(loc)
            shareItems = [url]
            showShare = true
        } catch {
            showToast("导出失败：\(error.localizedDescription)")
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { toast = nil }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
