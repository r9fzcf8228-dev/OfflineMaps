import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct DocPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}

struct ContentView: View {
    @State private var overlay: MKTileOverlay?
    @State private var data = LDKData()
    @State private var files: [URL] = []
    @State private var showMap = false
    @State private var showImporter = false
    @State private var message = ""
    @State private var showMessage = false

    @State private var showPoints = true
    @State private var showAreas = true
    @State private var showLines = true
    @State private var showTracks = true
    @State private var hybrid = false
    @State private var showCrosshair = true
    @State private var center: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            ZStack {
                if showMap {
                    mapScreen
                } else {
                    fileList
                }
            }
            .navigationTitle(showMap ? "\(data.points.count) pts" : "منتظر يسر جبار")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if showMap {
                        Menu {
                            Toggle("النقاط", isOn: $showPoints)
                            Toggle("المناطق", isOn: $showAreas)
                            Toggle("الخطوط", isOn: $showLines)
                            Toggle("المسارات", isOn: $showTracks)
                            Divider()
                            Toggle("قمر صناعي", isOn: $hybrid)
                            Toggle("الإحداثيات", isOn: $showCrosshair)
                            Divider()
                            Button("مسح البيانات", role: .destructive) {
                                overlay = nil
                                data = LDKData()
                                showMap = false
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        Button("القائمة") { showMap = false }
                    }
                    Button("استيراد") { showImporter = true }
                }
            }
            .sheet(isPresented: $showImporter) {
                DocPicker { urls in
                    showImporter = false
                    handle(urls)
                }
            }
            .alert(message, isPresented: $showMessage) {
                Button("OK", role: .cancel) {}
            }
            .onAppear(perform: reload)
        }
    }

    private var mapScreen: some View {
        ZStack {
            OfflineMapView(overlay: overlay,
                           data: data,
                           showPoints: showPoints,
                           showAreas: showAreas,
                           showLines: showLines,
                           showTracks: showTracks,
                           mapType: hybrid ? .hybrid : .standard,
                           onCenter: { c in center = c })
                .ignoresSafeArea()
            if showCrosshair {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(.red)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) { hud }
    }

    private var hud: some View {
        Group {
            if showCrosshair, let c = center {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UTM  " + Coords.utmString(c))
                    Text("MGRS " + Coords.mgrsString(c))
                    Text(Coords.ddString(c))
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 8)
            }
        }
    }

    private var fileList: some View {
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

    func say(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            message = text
            showMessage = true
        }
    }

    func handle(_ urls: [URL]) {
        guard let url = urls.first else { return }
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
                data = LDKParser.parse(url: url)
                showMap = true
                say("تعذر النسخ. قرأت الملف مباشرة: \(data.points.count) نقطة")
            } else {
                say("فشل النسخ: \(error.localizedDescription)")
            }
        }
    }

    func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "mbtiles" {
            overlay = MBTilesOverlay(path: url.path)
        } else if ext == "ldk" {
            data = LDKParser.parse(url: url)
        }
        showMap = true
    }

    func reload() {
        let dir = MapStore.shared.dir
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { ["mbtiles", "ldk"].contains($0.pathExtension.lowercased()) }
    }
}
