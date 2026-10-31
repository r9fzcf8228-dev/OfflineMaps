import SwiftUI

struct OfflineMapsSheet: View {
    @ObservedObject var downloader: TileDownloader
    let bounds: GeoBounds?
    let activeName: String?
    let onActivate: (String?) -> Void
    let onDeleted: (String) -> Void
    let onFinished: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var maps: [URL] = []
    @State private var template: String = UserDefaults.standard.string(forKey: "tileTemplate") ?? ""
    @State private var mapName: String = "منطقتي"
    @State private var minZ: Int = 10
    @State private var maxZ: Int = 15

    private var estimate: Int {
        guard let b = bounds else { return 0 }
        return TileMath.count(b, minZ, maxZ)
    }

    private var templateOK: Bool {
        return template.contains("{z}") && template.contains("{x}") && template.contains("{y}")
    }

    private var canStart: Bool {
        if bounds == nil { return false }
        if !templateOK { return false }
        if maxZ < minZ { return false }
        return estimate > 0 && estimate <= TileDownloader.maxTiles
    }

    private var estimateText: String {
        let n = estimate
        let mb = Double(n) * 0.02
        return "عدد البلاطات: \(n)  •  الحجم التقريبي: \(String(format: "%.0f", mb)) MB"
    }

    private func sizeText(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let n = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private func refresh() {
        let all = (try? FileManager.default.contentsOfDirectory(at: MapStore.shared.dir,
                                                                includingPropertiesForKeys: nil)) ?? []
        maps = all.filter { $0.pathExtension.lowercased() == "mbtiles" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func cleanName() -> String {
        var n = mapName.trimmingCharacters(in: .whitespacesAndNewlines)
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
        if n.isEmpty { n = "map" }
        return n + ".mbtiles"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الخريطة الأساسية") {
                    Button {
                        onActivate(nil)
                    } label: {
                        HStack {
                            Text("خرائط Apple (تحتاج إنترنت)")
                            Spacer()
                            if activeName == nil {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent)
                            }
                        }
                    }
                    ForEach(maps, id: \.self) { url in
                        Button {
                            onActivate(url.lastPathComponent)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                    Text(sizeText(url))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if activeName == url.lastPathComponent {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                try? FileManager.default.removeItem(at: url)
                                onDeleted(url.lastPathComponent)
                                refresh()
                            } label: {
                                Text("حذف")
                            }
                        }
                    }
                    if maps.isEmpty {
                        Text("لا توجد خرائط محفوظة. نزّل منطقة أو استورد ملف MBTiles.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("تنزيل المنطقة المعروضة على الخريطة") {
                    if let b = bounds {
                        Text(String(format: "ش %.3f إلى %.3f   ق %.3f إلى %.3f",
                                    b.minLat, b.maxLat, b.minLon, b.maxLon))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)

                        TextField("رابط البلاطات مثل https://.../{z}/{x}/{y}.png", text: $template)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 12, design: .monospaced))
                        TextField("اسم الخريطة", text: $mapName)
                        Stepper("أدنى تكبير: \(minZ)", value: $minZ, in: 1...18)
                        Stepper("أقصى تكبير: \(maxZ)", value: $maxZ, in: 1...19)

                        Text(estimateText)
                            .font(.caption)
                            .foregroundColor(estimate > TileDownloader.maxTiles ? .red : .secondary)

                        if downloader.running {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: Double(downloader.done),
                                             total: Double(max(downloader.total, 1)))
                                    .tint(Theme.accent)
                                    .animation(.easeInOut(duration: 0.3), value: downloader.done)
                                Text("\(downloader.done) / \(downloader.total)   فشل: \(downloader.failed)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Button("إيقاف", role: .destructive) {
                                downloader.cancel()
                            }
                        } else {
                            Button("بدء التنزيل") {
                                UserDefaults.standard.set(template, forKey: "tileTemplate")
                                let file = cleanName()
                                downloader.start(template: template, bounds: b,
                                                 minZ: minZ, maxZ: maxZ, fileName: file) { ok, name in
                                    refresh()
                                    if ok { onFinished(name) }
                                }
                            }
                            .disabled(!canStart)
                        }

                        if !downloader.status.isEmpty {
                            Text(downloader.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("افتح الخريطة وحرّكها إلى المنطقة المطلوبة، ثم افتح هذه النافذة من زر التنزيل.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Text("استخدم مصدر بلاطات يسمح شرط استخدامه بالتنزيل. كثير من الخوادم العامة تمنع التنزيل الجماعي. يمكنك أيضاً استيراد ملف MBTiles جاهز.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("الخرائط دون إنترنت")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .onAppear(perform: refresh)
        }
    }
}
