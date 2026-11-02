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

enum Stage {
    case splash
    case home
    case map
}

enum ActiveSheet: Identifiable {
    case importer
    case goTo
    case navTarget
    case offlineMaps
    case editPoint(MapPoint, Bool)

    var id: String {
        switch self {
        case .importer: return "importer"
        case .goTo: return "goto"
        case .navTarget: return "navtarget"
        case .offlineMaps: return "offline"
        case .editPoint(let p, _): return "edit-" + p.id.uuidString
        }
    }
}

struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @StateObject private var controller = MapController()
    @StateObject private var navigator = Navigator()
    @StateObject private var net = NetworkMonitor()
    @StateObject private var downloader = TileDownloader()

    @State private var stage: Stage = .splash
    @State private var overlay: MKTileOverlay?
    @State private var activeBase: String?
    @State private var files: [URL] = []
    @State private var sheet: ActiveSheet?
    @State private var message = ""
    @State private var showMessage = false
    @State private var banner: String?

    @State private var showPoints = true
    @State private var showAreas = true
    @State private var showLines = true
    @State private var showTracks = true
    @State private var hybrid = false
    @State private var showCrosshair = true
    @State private var clusterPoints = true
    @State private var navFollowing = true
    @State private var center: CLLocationCoordinate2D?

    @State private var editMode = false
    @State private var pathMode = false
    @State private var followRoads = false
    @State private var pathInfo = PathInfo()

    var body: some View {
        ZStack {
            switch stage {
            case .splash:
                SplashView {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        stage = .home
                    }
                }
                .transition(.opacity)
            case .home:
                homeScreen
                    .transition(.opacity)
            case .map:
                mapStage
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { s in
            sheetContent(s)
        }
        .alert(message, isPresented: $showMessage) {
            Button("OK", role: .cancel) {}
        }
        .onAppear {
            reload()
            loadActiveBase()
        }
    }

    // MARK: - الشاشة الرئيسية

    private var homeScreen: some View {
        HomeView(pointsCount: store.points.count,
                 areasCount: store.shapes.filter { $0.kind == "area" }.count,
                 routesCount: store.shapes.filter { $0.kind == "route" }.count,
                 baseName: activeBase ?? "Apple Maps",
                 online: net.online,
                 files: files,
                 onOpenMap: { openMap() },
                 onDownload: {
                     openMap()
                     showBanner("حرّك الخريطة إلى المنطقة المطلوبة ثم اضغط زر «تنزيل»")
                 },
                 onNavigate: {
                     openMap()
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                         sheet = .navTarget
                     }
                 },
                 onImport: { sheet = .importer },
                 onOpenFile: { url in open(url) })
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
        case .navTarget:
            NavTargetSheet(points: store.points,
                           center: center,
                           user: controller.userLocation()) { c, name in
                startNav(c, name)
            }
        case .offlineMaps:
            OfflineMapsSheet(downloader: downloader,
                             bounds: controller.visibleBounds(),
                             activeName: activeBase,
                             onActivate: { name in setActiveBase(name) },
                             onDeleted: { name in
                                 if activeBase == name { setActiveBase(nil) }
                                 reload()
                             },
                             onFinished: { name in
                                 reload()
                                 setActiveBase(name)
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

    // MARK: - شاشة الخريطة

    private var mapStage: some View {
        ZStack {
            OfflineMapView(overlay: overlay,
                           points: store.points,
                           shapes: store.shapes,
                           revision: store.revision,
                           showPoints: showPoints,
                           showAreas: showAreas,
                           showLines: showLines,
                           showTracks: showTracks,
                           clusterPoints: clusterPoints,
                           mapType: hybrid ? .hybrid : .standard,
                           editMode: editMode,
                           pathMode: pathMode,
                           followRoads: followRoads,
                           navRoute: navigator.routeCoords,
                           navRevision: navigator.routeRevision,
                           navProgress: navigator.progressIndex,
                           navTarget: navigator.active ? navigator.target : nil,
                           navRoad: navigator.roadMode,
                           navActive: navigator.active,
                           navFollow: navFollowing,
                           navNear: navigator.roadMode && navigator.stepDistance < 180,
                           controller: controller,
                           onCenter: { c in center = c },
                           onEditPoint: { id in openEditor(id) },
                           onMovePoint: { id, c in
                               store.move(id, to: c)
                               Haptics.success()
                           },
                           onLongPress: { c in newPoint(at: c) },
                           onPath: { info in pathInfo = info },
                           onPathMessage: { m in say(m) },
                           onFollowChange: { f in navFollowing = f })
                .ignoresSafeArea()
            if showCrosshair && !navigator.active {
                crosshair
            }
        }
        .overlay(alignment: .top) { topBar }
        .safeAreaInset(edge: .bottom) { bottomPanel }
    }

    private var crosshair: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
                .frame(width: 26, height: 26)
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundColor(.red)
        }
        .allowsHitTesting(false)
    }

    private func roundButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .glass(20)
        }
        .buttonStyle(PressableStyle())
    }

    private var mapMenu: some View {
        Menu {
            Toggle("النقاط", isOn: $showPoints)
            Toggle("المناطق", isOn: $showAreas)
            Toggle("الخطوط", isOn: $showLines)
            Toggle("المسارات", isOn: $showTracks)
            Divider()
            Toggle("قمر صناعي", isOn: $hybrid)
            Toggle("الإحداثيات", isOn: $showCrosshair)
            Toggle("تجميع النقاط القريبة", isOn: $clusterPoints)
            Divider()
            Button("الخرائط دون إنترنت") { sheet = .offlineMaps }
            Button("استيراد ملف") { sheet = .importer }
            Button("تكبير على البيانات") {
                controller.needsFit = true
                store.changed()
            }
            Button("مسح كل البيانات", role: .destructive) {
                controller.clearPath()
                navigator.stop()
                store.clearAll()
                goHome()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .glass(20)
        }
    }

    private func hudCapsule(_ c: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("UTM  " + Coords.utmString(c))
            Text("MGRS " + Coords.mgrsString(c))
            Text(Coords.ddString(c))
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glass(12)
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                roundButton("chevron.backward") { goHome() }
                if showCrosshair && !navigator.active, let c = center {
                    hudCapsule(c)
                }
                Spacer(minLength: 0)
                mapMenu
            }
            .padding(.horizontal, 12)

            if navigator.active {
                NavBanner(nav: navigator)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let b = banner {
                Text(b)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glass(14)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !net.online {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text("بدون إنترنت — الأدوات تعمل محلياً")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glass(12)
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: navigator.active)
    }

    // MARK: - الأسفل

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if navigator.active {
                NavBottomBar(nav: navigator,
                             following: navFollowing,
                             onRecenter: {
                                 navFollowing = true
                                 controller.recenterNow()
                             },
                             onStop: {
                                 withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                     navigator.stop()
                                 }
                             })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if pathMode || pathInfo.count > 0 {
                    pathPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                toolbar
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: navigator.active)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: pathMode)
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolButton("plus.circle.fill", "نقطة", false) {
                let c = center ?? CLLocationCoordinate2D(latitude: 35.47, longitude: 44.39)
                newPoint(at: c)
            }
            toolButton("scope", "إحداثيات", false) {
                sheet = .goTo
            }
            toolButton("location.north.circle.fill", "ملاحة", navigator.active) {
                if navigator.active {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        navigator.stop()
                    }
                } else {
                    sheet = .navTarget
                }
            }
            toolButton("point.topleft.down.curvedto.point.bottomright.up", "مسار", pathMode) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    pathMode.toggle()
                    if pathMode { editMode = false }
                }
            }
            toolButton("pencil.circle", "تعديل", editMode) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    editMode.toggle()
                    if editMode { pathMode = false }
                }
            }
            toolButton("arrow.down.circle.fill", "تنزيل", false) {
                sheet = .offlineMaps
            }
        }
        .padding(6)
        .glass(22)
    }

    private func toolButton(_ icon: String, _ title: String, _ on: Bool,
                            _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(on ? Theme.accent : Color.white)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(on ? Theme.accent : Color.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(on ? Theme.accent.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
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
            Text(pathLine1)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: pathLine1)
            Text(pathLine2)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.8))
            if pathInfo.busy {
                Text("جاري حساب الطريق...")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
            }
            Toggle("اتباع الطرق (يلزم إنترنت)", isOn: $followRoads)
                .font(.system(size: 13))
                .tint(Theme.accent)
            HStack(spacing: 10) {
                Button("تراجع") { controller.undoPath() }
                    .buttonStyle(.bordered)
                Button("مسح") { controller.clearPath() }
                    .buttonStyle(.bordered)
                Button("حفظ كمسار") { saveRoute() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(pathInfo.count < 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(22)
    }

    // MARK: - الإجراءات

    private func openMap() {
        controller.needsFit = true
        withAnimation(.easeInOut(duration: 0.5)) {
            stage = .map
        }
    }

    private func goHome() {
        pathMode = false
        editMode = false
        pathInfo = PathInfo()
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .home
        }
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            banner = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            withAnimation(.easeOut(duration: 0.4)) {
                banner = nil
            }
        }
    }

    private func startNav(_ c: CLLocationCoordinate2D, _ name: String) {
        pathMode = false
        editMode = false
        navFollowing = true
        navigator.start(to: c, name: name, online: net.online)
        Haptics.success()
    }

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

    // MARK: - الخرائط والملفات

    func loadActiveBase() {
        guard let name = UserDefaults.standard.string(forKey: "activeBase") else { return }
        let url = MapStore.shared.dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            activeBase = name
            overlay = MBTilesOverlay(path: url.path)
        }
    }

    func setActiveBase(_ name: String?) {
        if let n = name {
            let url = MapStore.shared.dir.appendingPathComponent(n)
            overlay = MBTilesOverlay(path: url.path)
            activeBase = n
            UserDefaults.standard.set(n, forKey: "activeBase")
        } else {
            overlay = nil
            activeBase = nil
            UserDefaults.standard.removeObject(forKey: "activeBase")
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
            if ext == "mbtiles" {
                setActiveBase(url.lastPathComponent)
                say("تم استيراد الخريطة وتفعيلها: \(url.lastPathComponent)")
            } else {
                say("تم استيراد: \(url.lastPathComponent)")
            }
        } catch {
            if ext == "ldk" {
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
        openMap()
    }

    func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "mbtiles" {
            setActiveBase(url.lastPathComponent)
            openMap()
        } else if ext == "ldk" {
            loadLDK(url)
        }
    }

    func reload() {
        let dir = MapStore.shared.dir
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { ["mbtiles", "ldk"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
