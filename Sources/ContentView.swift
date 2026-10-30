import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var overlay: MKTileOverlay?
    @State private var points: [LDKPoint] = []
    @State private var files: [URL] = []
    @State private var showMap = false
    @State private var showImporter = false
    @State private var message = ""
    @State private var showMessage = false

    var body: some View {
        NavigationStack {
            ZStack {
                if showMap {
                    OfflineMapView(overlay: overlay, points: points)
                        .ignoresSafeArea()
                } else {
                    List {
                        if files.isEmpty {
                            Text("لا توجد ملفات. اضغط استيراد.")
                                .foregroundColor(.secondary)
                        }
                        ForEach(files, id: \.self) { url in
                            Button {
                                open(url)
                            } label: {
                                HStack {
                                    Text(url.lastPathComponent)
                                    Spacer()
                                    Text(url.pathExtension.uppercased())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(showMap ? "\(points.count) pts" : "Maps")
            .toolbar {
                Button("استيراد") { showImporter = true }
                if showMap {
                    Button("القائمة") { showMap = false }
                    Button("مسح") {
                        overlay = nil
                        points = []
                        showMap = false
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                handle(result)
            }
            .alert(message, isPresented: $showMessage) {
                Button("OK", role: .cancel) {}
            }
            .onAppear(perform: reload)
        }
    }

    func say(_ text: String) {
        message = text
        showMessage = true
    }

    func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            say("فشل الاستيراد: \(error.localizedDescription)")
        case .success(let urls):
            guard let url = urls.first else {
                say("لم يتم اختيار ملف")
                return
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.lowercased()
            let dest = MapStore.shared.dir.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                reload()
                say("تم استيراد: \(url.lastPathComponent)")
            } catch {
                if ext == "ldk" {
                    let pts = LDKParser.parse(url: url)
                    points = pts
                    showMap = true
                    say("تعذر النسخ (\(error.localizedDescription)). قرأت الملف مباشرة: \(pts.count) نقطة")
                } else {
                    say("فشل النسخ: \(error.localizedDescription)")
                }
            }
        }
    }

    func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "mbtiles" {
            overlay = MBTilesOverlay(path: url.path)
        } else if ext == "ldk" {
            points = LDKParser.parse(url: url)
        }
        showMap = true
    }

    func reload() {
        let dir = MapStore.shared.dir
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { ["mbtiles", "ldk"].contains($0.pathExtension.lowercased()) }
    }
}
