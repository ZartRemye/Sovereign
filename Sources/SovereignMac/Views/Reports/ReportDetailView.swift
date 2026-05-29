import SwiftUI

struct ReportDetailView: View {
    let report: HealthReport
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.title)
                        .font(AppTypography.title)
                    Text("生成时间: \(formatDate(report.generatedAt)) · 来源: \(report.source)")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                HStack(spacing: AppSpacing.md) {
                    Button("复制 Markdown") {
                        copyMarkdown()
                    }
                    .buttonStyle(.bordered)

                    Button("导出为 .md") {
                        exportMarkdown()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("关闭") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()

            Divider()

            // Report content
            ScrollView {
                Text(markdownToAttributed(report.markdownContent))
                    .font(AppTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 650, height: 600)
        .alert("已复制", isPresented: $showCopiedAlert) {
            Button("好") {}
        } message: {
            Text("Markdown 内容已复制到剪贴板")
        }
    }

    private func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.markdownContent, forType: .string)
        showCopiedAlert = true
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(report.title.replacingOccurrences(of: " ", with: "_")).md"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? report.markdownContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    /// Simple markdown → AttributedString (handles **bold**, ## headings, | tables)
    private func markdownToAttributed(_ markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown)
        } catch {
            return AttributedString(markdown)
        }
    }
}
