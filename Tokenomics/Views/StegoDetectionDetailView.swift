import SwiftUI
import UniformTypeIdentifiers

/// Claude Desktop 隐写术 / 浏览器注入检测 —— 详情页。
///
/// 展示：
///   - 顶部：等级徽章 + 摘要文字 + 上次扫描时间 + 立即重新扫描按钮
///   - 浏览器注入命中表（P1+P2）
///   - Prompt Unicode 命中表（P3+P4）
///   - 底部工具区：导入 mitmproxy 日志、导出 JSON 报告、签名版本号
struct StegoDetectionDetailView: View {
    @EnvironmentObject var app: AppState

    @State private var isImporting: Bool = false
    @State private var isExporting: Bool = false
    @State private var lastError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                browserSection
                Divider()
                promptSection
                Divider()
                footer
            }
            .padding(20)
        }
        .navigationTitle(L10n.tr("stego.detail.title"))
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .init(filenameExtension: "har") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: StegoReportDocument(data: app.stegoProbe.latestReport?.exportJSON() ?? Data()),
            contentType: .json,
            defaultFilename: "claude-stego-report.json"
        ) { _ in }
        .alert(item: Binding(
            get: { lastError.map { ErrorMessage(text: $0) } },
            set: { _ in lastError = nil }
        )) { err in
            Alert(title: Text(L10n.tr("stego.detail.import.error")), message: Text(err.text))
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                severityBadge
                Spacer()
                if let ts = app.stegoProbe.latestReport?.generatedAt {
                    Text(String(format: L10n.tr("stego.detail.header.generated.fmt"), Self.tsFmt.string(from: ts)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(app.stegoProbe.latestReport?.summary ?? L10n.tr("stego.detail.header.never"))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if app.stegoProbe.isScanning {
                ProgressView(value: max(0, min(app.stegoProbe.progress, 1)))
            }

            HStack {
                Button {
                    Task { await app.stegoProbe.runFullScan() }
                } label: {
                    Label(L10n.tr("stego.detail.rescan"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.stegoProbe.isScanning)

                Button {
                    isImporting = true
                } label: {
                    Label(L10n.tr("stego.detail.import.mitm"), systemImage: "square.and.arrow.down")
                }

                Button {
                    isExporting = true
                } label: {
                    Label(L10n.tr("stego.detail.export"), systemImage: "square.and.arrow.up")
                }
                .disabled(app.stegoProbe.latestReport == nil)

                Spacer()
            }
        }
    }

    private var severityBadge: some View {
        let (color, text): (Color, String) = {
            guard let r = app.stegoProbe.latestReport else { return (.secondary, L10n.tr("stego.card.status.unknown")) }
            switch r.severity {
            case .clean:      return (.green,  L10n.tr("stego.card.status.clean"))
            case .suspicious: return (.yellow, L10n.tr("stego.card.status.suspicious"))
            case .confirmed:  return (.red,    L10n.tr("stego.card.status.confirmed"))
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.title3.weight(.semibold)).foregroundStyle(color)
        }
    }

    private var browserSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("stego.detail.browser.title"))
                .font(.headline)
            Text(L10n.tr("stego.detail.browser.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            let hits = app.stegoProbe.latestReport?.browserHits ?? []
            if hits.isEmpty {
                Text(L10n.tr("stego.detail.browser.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(h.browser) · \(h.artifactType)")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if let t = h.mtime {
                                Text(Self.tsFmt.string(from: t))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text(h.artifactPath.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(String(format: L10n.tr("stego.detail.browser.keywords.fmt"),
                                    h.matchedKeywords.joined(separator: ", ")))
                            .font(.caption)
                        if let ex = h.excerpt, !ex.isEmpty {
                            Text(ex)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .padding(.top, 2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.background.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                }
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("stego.detail.prompt.title"))
                .font(.headline)
            Text(L10n.tr("stego.detail.prompt.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            let hits = app.stegoProbe.latestReport?.promptHits ?? []
            if hits.isEmpty {
                Text(L10n.tr("stego.detail.prompt.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(h.channel.rawValue)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(color(for: h.channel))
                            Text("· \(h.source == .mitmLog ? "mitm" : "local")")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let t = h.timestamp {
                                Text(Self.tsFmt.string(from: t))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let p = h.filePath {
                            Text(p.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Text(h.excerpt)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(4)
                        Text(String(format: L10n.tr("stego.detail.prompt.codepoint.fmt"), h.codepoint))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(color(for: h.channel).opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color(for: h.channel).opacity(0.4)))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(String(format: L10n.tr("stego.detail.footer.sigver.fmt"),
                        String(app.stegoProbe.latestReport?.signaturesVersion ?? StegoSignatures.signaturesVersion)))
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - helpers

    private func color(for channel: StegoChannel) -> Color {
        switch channel {
        case .dateSeparatorSlash:  return .orange
        case .apostropheU2019,
             .apostropheU02BC,
             .apostropheU02B9:     return .red
        case .unknownNonAscii:     return .yellow
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            Task {
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    _ = try await app.stegoProbe.importMitmLog(fileURL: url)
                } catch {
                    await MainActor.run {
                        lastError = error.localizedDescription
                    }
                }
            }
        case .failure(let err):
            lastError = err.localizedDescription
        }
    }

    private static let tsFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private struct ErrorMessage: Identifiable {
        let text: String
        var id: String { text }
    }
}

/// FileDocument wrapper：满足 `fileExporter` 的类型约束，导出 JSON 报告。
struct StegoReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
