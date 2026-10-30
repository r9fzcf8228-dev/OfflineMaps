import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var overlay: MKTileOverlay?
    @State private var files: [URL] = []
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let overlay {
                    OfflineMapView(overlay: overlay).ignoresSafeArea()
                } else {
                    List(files, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            overlay = MBTilesOverlay(path: url.path)
                        }
                    }
                }
            }
            .navigationTitle("خرائطي")
            .toolbar {
                Button("استيراد") { showImporter = true }
                if overlay != nil {
                    Button("القائمة") { overlay = nil }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.mbtiles, .ldk, .gpx, .kml, .data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    urls.forEach { MapStore.shared.importFile($0) }
                    reload()
                }
            }
            .onAppear(perform: reload)
        }
    }

    func reload() {
        let dir = MapStore.shared.dir
        files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "mbtiles" } ?? []
    }
}
