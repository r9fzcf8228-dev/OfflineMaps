import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var overlay: MKTileOverlay?
    @State private var points: [LDKPoint] = []
    @State private var files: [URL] = []
    @State private var showMap = false
    @State private var showImporter = false

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
            .navigationTitle(showMap ? "\(points.count) نقطة" : " منتظر يسر خرائطي")
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
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    urls.forEach { MapStore.shared.importFile($0) }
                    reload()
                }
            }
            .onAppear(perform: reload)
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
