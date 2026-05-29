import Foundation
import Compression

/// Handles ZIP files from Apple Health export.
/// Extracts and finds export.xml, then delegates to AppleHealthExportParser.
final class AppleHealthZipImporter {
    private var onProgress: ((Double, String) -> Void)?
    private var isCancelled = false

    func importZip(
        at url: URL,
        progress: ((Double, String) -> Void)? = nil,
        cancellation: (() -> Bool)? = nil
    ) async throws -> ImportParseResult {
        self.onProgress = progress

        // Step 1: Create temp directory for extraction
        progress?(0.0, "准备解压...")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sovereign_import_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Step 2: Extract ZIP
        progress?(0.1, "正在解压...")
        try await extractZip(at: url, to: tempDir)

        if isCancelled || cancellation?() == true { throw ImportError(message: "导入已取消", underlyingError: nil) }

        // Step 3: Find export.xml
        progress?(0.5, "查找 export.xml...")
        guard let xmlURL = findExportXML(in: tempDir) else {
            throw ImportError(message: "未在 ZIP 中找到 export.xml 文件", underlyingError: nil)
        }

        // Step 4: Parse XML
        progress?(0.6, "解析数据...")
        guard let parser = AppleHealthExportParser(fileURL: xmlURL) else {
            throw ImportError(message: "无法读取 export.xml", underlyingError: nil)
        }

        parser.onProgress = { [weak self] p in
            self?.onProgress?(0.6 + p * 0.35, "解析中...")
        }

        if cancellation?() == true { parser.isCancelled = true }

        let result = parser.parse()

        progress?(1.0, "完成")
        return result
    }

    private func findExportXML(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == "export.xml" {
                return fileURL
            }
        }

        return nil
    }

    private func extractZip(at url: URL, to destination: URL) async throws {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", url.path, "-d", destination.path]

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ImportError(
                        message: "解压失败 (exit code: \(process.terminationStatus))",
                        underlyingError: nil
                    ))
                }
            } catch {
                continuation.resume(throwing: ImportError(
                    message: "解压失败: \(error.localizedDescription)",
                    underlyingError: error
                ))
            }
        }
        #else
        throw ImportError(message: "ZIP 解压仅支持 macOS", underlyingError: nil)
        #endif
    }

    func cancel() {
        isCancelled = true
    }
}
