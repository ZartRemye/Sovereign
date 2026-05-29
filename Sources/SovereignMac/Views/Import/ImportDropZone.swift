import SwiftUI
import UniformTypeIdentifiers

struct ImportDropZone: View {
    @Binding var isDragging: Bool
    var isImporting: Bool
    var onFileSelected: (URL) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundColor(isDragging ? .accentColor : .secondary.opacity(0.3))
                .frame(height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isDragging ? Color.accentColor.opacity(0.05) : Color.secondary.opacity(0.03))
                )

            if isImporting {
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在导入...")
                        .font(AppTypography.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 36))
                        .foregroundColor(isDragging ? .accentColor : .secondary)

                    Text("拖放 Apple Health 导出文件到此处")
                        .font(AppTypography.headline)

                    Text("支持 export.xml 和 Apple Health 导出的 ZIP 文件")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)

                    Button("选择文件...") {
                        selectFile()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, AppSpacing.sm)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml, .init(filenameExtension: "zip") ?? .archive]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                onFileSelected(url)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        onFileSelected(url)
                    }
                }
            }
        }
    }
}
