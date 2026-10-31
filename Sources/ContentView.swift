import SwiftUI
import MapKit
import CoreLocation
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

enum ActiveSheet: Identifiable {
    case importer
    case goTo
    case editPoint(MapPoint, Bool)

    var id: String {
        switch self {
        case .importer: return "importer"
        case .goTo: return "goto"
        case .editPoint(let p, _): return "edit-" + p.id.uuidString
        }
    }
}

struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @StateObject private var controller = MapController()

    @State private var overlay: MKTileOverlay?
    @State private var files: [URL] = []
    @State private var showMap = false
    @State private var sheet: ActiveSheet?
    @State private var message = ""
    @State private var showMessage = false

    @State private var showPoints = true
    @State private var showAreas = true
    @State private var showLines = true
    @State private var showTracks = true
    @State private var hybrid = false
    @State private var showCrosshair = true
    @State private var center: CLLocationCoordinate2D?

    @State private var editMode = false
    @State private var pathMode = false
    @State private var followRoads = false
    @State private var pathInfo = PathInfo()

    var body: some View {
        NavigationStack {
            ZStack {
                if showMap {
                    mapScreen
                } else {
                    fileList
                }
            }
            .navigationTitle(showMap ? "\(store.points.count) pts" : "صمم بواسطة ضياء محمد جميل ")
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
                            Button("تكبير على البيانات") {
                                controller.needsFit = true
                                store.changed()
                            }
                            Button("مسح كل البيانات", role: .destructive) {
                                controller.clearPath()
                                store.clearAll()
                                overlay = nil
                                showMap = false
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        Button("القائمة") { showMap = false }
                    }
                    Button("استيراد") { sheet = .importer }
                }
            }
            .sheet(item: $sheet) { s in
                sheetContent(s)
            }
            .alert(message, isPresented: $showMessage) {
                Button("OK", role: .cancel) {}
            }
            .onAppear(perform: reload)
        }
    }

    // MARK: - النوافذ

    @ViewBuilder
    private func sheetContent(_ s: ActiveSheet) -> some View {
        switch s {
        case .importer:
            DocPicker { urls in
                sheet = nil
                handle(urls)
            }
        case .goTo:
            GoToSheet(onGo: { c in
                controller.goTo(c)
            }, onAdd: { c in
                sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    newPoint(at: c)
                }
            })
        case .editPoint(let p, let isNew):
            PointEditor(point: p, isNew: isNew,
                        onSave: { np in store.upsert(np) },
                        onDelete: deleter(p, isNew))
        }
    }

    private func deleter(_ p: MapPoint, _ isNew: Bool) -> (() -> Void)? {
        if isNew { return nil }
        return { store.deletePoint(p.id) }
    }

    // MARK: - الخريطة

    private var mapScreen: some View {
        ZStack {
            OfflineMapView(overlay: overlay,
                           points: store.points,
                           shapes: store.shapes,
                           revision: store.revision,
                           showPoints: showPoints,
                           showAreas: showAreas,
                           showLines: showLines,
                           showTracks: showTracks,
                           mapType: hybrid ? .hybrid : .standard,
                           editMode: editMode,
                           pathMode: pathMode,
                           followRoads: followRoads,
                           controller: controller,
                           onCenter: { c in center = c },
                           onEditPoint: { id in openEditor(id) },
                           onMovePoint: { id, c in store.move(id, to: c) },
                           onLongPress: { c in newPoint(at: c) },
                           onPath: { info in pathInfo = info },
                           onPathMessage: { m in say(m) })
                .ignoresSafeArea()
            if showCrosshair {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(.red)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) { hud }
        .safeAreaInset(edge: .bottom) { bottomPanel }
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

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if pathMode || pathInfo.count > 0 {
                pathPanel
            }
            HStack(spacing: 8) {
                toolButton("plus.circle.fill", "نقطة", false) {
                    let c = center ?? CLLocationCoordinate2D(latitude: 35.47, longitude: 44.39)
                    newPoint(at: c)
                }
                toolButton("scope", "إحداثيات", false) {
                    sheet = .goTo
                }
                toolButton("point.topleft.down.curvedto.point.bottomright.up", "مسار", pathMode) {
                    pathMode.toggle()
                    if pathMode { editMode = false }
                }
                toolButton("pencil.circle", "تعديل", editMode) {
                    editMode.toggle()
                    if editMode { pathMode = false }
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
    }

    private func toolButton(_ icon: String, _ title: String, _ on: Bool,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(on ? Color.accentColor.opacity(0.25) : Color.clear)
            .cornerRadius(8)
        }
    }

    private var pathLine1: String {
        var s = "المسافة: " + Coords.formatDistance(pathInfo.total)
        if pathInfo.seconds > 0 {
            s += "  |  الزمن: " + Coords.formatDuration(pathInfo.seconds)
        }
        return s
    }

    private var pathLine2: String {
        if pathInfo.count < 2 { return "اضغط على الخريطة لإضافة نقاط" }
        let deg = String(format: "%.1f", pathInfo.bearing)
        let mil = Coords.mils(pathInfo.bearing)
        let leg = Coords.formatDistance(pathInfo.lastLeg)
        return "آخر مقطع: \(leg)  |  الاتجاه: \(deg)° / \(mil) mil"
    }

    private var pathPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pathLine1).font(.system(size: 14, weight: .semibold))
            Text(pathLine2).font(.system(size: 13))
            if pathInfo.busy {
                Text("جاري حساب الطريق...").font(.system(size: 12)).foregroundColor(.secondary)
            }
            Toggle("اتباع الطرق (يلزم إنترنت)", isOn: $followRoads)
                .font(.system(size: 13))
            HStack(spacing: 10) {
                Button("تراجع") { controller.undoPath() }
                    .buttonStyle(.bordered)
                Button("مسح") { controller.clearPath() }
                    .buttonStyle(.bordered)
                Button("حفظ كمسار") { saveRoute() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pathInfo.count < 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - قائمة الملفات

    private var fileList: some View {
        List {
            if !store.points.isEmpty || !store.shapes.isEmpty {
                Button {
                    controller.needsFit = true
                    showMap = true
                } label: {
                    Text("فتح الخريطة (\(store.points.count) نقطة)")
                        .font(.headline)
                }
            }
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

    // MARK: - الإجراءات

    func say(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            message = text
            showMessage = true
        }
    }

    func newPoint(at c: CLLocationCoordinate2D) {
        let p = MapPoint(name: "نقطة \(store.points.count + 1)", lat: c.latitude, lon: c.longitude)
        sheet = .editPoint(p, true)
    }

    func openEditor(_ id: UUID) {
        if let p = store.points.first(where: { $0.id == id }) {
            sheet = .editPoint(p, false)
        }
    }

    func saveRoute() {
        let cs = controller.pathCoords()
        if cs.count < 2 { return }
        let n = store.shapes.filter { $0.kind == "route" }.count + 1
        let len = Coords.length(cs)
        store.addRoute(name: "مسار \(n)", coords: cs)
        controller.clearPath()
        say("تم حفظ المسار: " + Coords.formatDistance(len))
    }

    func handle(_ urls: [URL]) {
        guard let url = urls.first else { return }
        let dest = MapStore.shared.dir.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            reload()
            say("تم استيراد: \(url.lastPathComponent)")
        } catch {
            if url.pathExtension.lowercased() == "ldk" {
                loadLDK(url)
            } else {
                say("فشل النسخ: \(error.localizedDescription)")
            }
        }
    }

    func loadLDK(_ url: URL) {
        let parsed = LDKParser.parse(url: url)
        controller.needsFit = true
        store.importLDK(parsed, name: url.lastPathComponent)
        showMap = true
    }

    func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "mbtiles" {
            overlay = MBTilesOverlay(path: url.path)
            controller.needsFit = true
            showMap = true
        } else if ext == "ldk" {
            loadLDK(url)
        }
    }

    func reload() {
        let dir = MapStore.shared.dir
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { ["mbtiles", "ldk"].contains($0.pathExtension.lowercased()) }
    }
}
