import SwiftUI
import UIKit
import CoreLocation

enum Exporter {
    static func escape(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "&", with: "&amp;")
        t = t.replacingOccurrences(of: "<", with: "&lt;")
        t = t.replacingOccurrences(of: ">", with: "&gt;")
        t = t.replacingOccurrences(of: "\"", with: "&quot;")
        return t
    }

    // ألوان KML بصيغة aabbggrr
    static func kmlColor(_ name: String, alpha: Double = 1) -> String {
        let ui = LDKStyle.color(name)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ai = Int((alpha * 255).rounded())
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "%02x%02x%02x%02x", ai, bi, gi, ri)
    }

    private static func coordString(_ c: CLLocationCoordinate2D) -> String {
        return String(format: "%.7f,%.7f,0", c.longitude, c.latitude)
    }

    static func kml(points: [MapPoint], shapes: [MapShape]) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n<Document>\n<name>OfflineMaps</name>\n"

        var pointStyles: [String: String] = [:]
        for p in points {
            if pointStyles[p.color] == nil {
                let id = "p\(pointStyles.count)"
                pointStyles[p.color] = id
                out += "<Style id=\"\(id)\"><IconStyle><color>\(kmlColor(p.color))</color><scale>1.1</scale>"
                out += "<Icon><href>http://maps.google.com/mapfiles/kml/paddle/wht-blank.png</href></Icon></IconStyle></Style>\n"
            }
        }

        for (i, s) in shapes.enumerated() {
            let c = kmlColor(s.color)
            let w = s.lineWidth > 0 ? s.lineWidth : ((s.kind == "route") ? 4 : 3)
            if s.kind == "area" {
                let fill = kmlColor(s.color, alpha: s.fillAlpha)
                out += "<Style id=\"s\(i)\"><LineStyle><color>\(c)</color><width>\(w)</width></LineStyle>"
                out += "<PolyStyle><color>\(fill)</color></PolyStyle></Style>\n"
            } else {
                out += "<Style id=\"s\(i)\"><LineStyle><color>\(c)</color><width>\(w)</width></LineStyle></Style>\n"
            }
        }

        out += "<Folder><name>Points</name>\n"
        for p in points {
            var desc = p.note
            if !desc.isEmpty { desc += "\n" }
            desc += "MGRS: " + Coords.mgrsString(p.coordinate) + "\nUTM: " + Coords.utmString(p.coordinate)
            let sid = pointStyles[p.color] ?? "p0"
            out += "<Placemark><name>\(escape(p.name))</name><description>\(escape(desc))</description>"
            out += "<styleUrl>#\(sid)</styleUrl>"
            out += "<Point><coordinates>\(coordString(p.coordinate))</coordinates></Point></Placemark>\n"
        }
        out += "</Folder>\n<Folder><name>Shapes</name>\n"
        for (i, s) in shapes.enumerated() {
            var cs = s.coords
            if cs.count < 2 { continue }
            out += "<Placemark><name>\(escape(s.name))</name><styleUrl>#s\(i)</styleUrl>"
            if s.kind == "area" {
                if let f = cs.first { cs.append(f) }
                let ring = cs.map { coordString($0) }.joined(separator: " ")
                out += "<Polygon><outerBoundaryIs><LinearRing><coordinates>\(ring)</coordinates></LinearRing></outerBoundaryIs></Polygon>"
            } else {
                let line = cs.map { coordString($0) }.joined(separator: " ")
                out += "<LineString><tessellate>1</tessellate><coordinates>\(line)</coordinates></LineString>"
            }
            out += "</Placemark>\n"
        }
        out += "</Folder>\n</Document>\n</kml>\n"
        return out
    }

    static func gpx(points: [MapPoint], shapes: [MapShape]) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<gpx version=\"1.1\" creator=\"OfflineMaps\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        for p in points {
            var desc = p.note
            if !desc.isEmpty { desc += " | " }
            desc += "MGRS " + Coords.mgrsString(p.coordinate)
            out += String(format: "<wpt lat=\"%.7f\" lon=\"%.7f\">", p.lat, p.lon)
            out += "<name>\(escape(p.name))</name><desc>\(escape(desc))</desc></wpt>\n"
        }
        for s in shapes {
            var cs = s.coords
            if cs.count < 2 { continue }
            var name = s.name
            if s.kind == "area" {
                name += " (area)"
                if let f = cs.first { cs.append(f) }
            }
            out += "<trk><name>\(escape(name))</name><trkseg>\n"
            for c in cs {
                out += String(format: "<trkpt lat=\"%.7f\" lon=\"%.7f\"></trkpt>\n", c.latitude, c.longitude)
            }
            out += "</trkseg></trk>\n"
        }
        out += "</gpx>\n"
        return out
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    // يكتب الملف في مجلد مؤقت ويعيد رابطه للمشاركة
    static func write(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ExportSheet: View {
    let points: [MapPoint]
    let shapes: [MapShape]
    let backup: () -> Data?

    @Environment(\.dismiss) private var dismiss
    @State private var item: ShareItem?
    @State private var maps: [URL] = []
    @State private var errorText = ""
    @State private var showError = false

    private func share(_ data: Data?, _ name: String) {
        guard let d = data, let url = Exporter.write(d, name: name) else {
            errorText = "تعذر إنشاء الملف"
            showError = true
            return
        }
        item = ShareItem(url: url)
    }

    private func refresh() {
        let all = (try? FileManager.default.contentsOfDirectory(at: MapStore.shared.dir,
                                                                includingPropertiesForKeys: nil)) ?? []
        let ok = ["mbtiles", "ldk"]
        maps = all.filter { ok.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("المحتوى الحالي") {
                    Text("\(points.count) نقطة  •  \(shapes.count) شكل (مناطق وخطوط ومسارات)")
                        .font(.subheadline)
                }

                Section("تصدير البيانات ومشاركتها") {
                    Button {
                        let text = Exporter.kml(points: points, shapes: shapes)
                        share(text.data(using: .utf8), "OfflineMaps-\(Exporter.stamp()).kml")
                    } label: {
                        Label("KML — يحفظ الألوان (Google Earth وغيره)", systemImage: "globe")
                    }
                    Button {
                        let text = Exporter.gpx(points: points, shapes: shapes)
                        share(text.data(using: .utf8), "OfflineMaps-\(Exporter.stamp()).gpx")
                    } label: {
                        Label("GPX — نقاط ومسارات", systemImage: "location.north.line")
                    }
                    Button {
                        share(backup(), "OfflineMaps-backup-\(Exporter.stamp()).json")
                    } label: {
                        Label("نسخة احتياطية كاملة للتطبيق (JSON)", systemImage: "externaldrive")
                    }
                }

                Section("ملفات الخرائط المحفوظة") {
                    if maps.isEmpty {
                        Text("لا توجد ملفات.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach(maps, id: \.self) { url in
                        Button {
                            item = ShareItem(url: url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    Text("لنقل بياناتك إلى جهاز آخر عليه هذا التطبيق: صدّر «النسخة الاحتياطية» وأرسلها بـ AirDrop أو واتساب، ثم في الجهاز الآخر اضغط استيراد واختر الملف.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("تصدير ومشاركة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .onAppear(perform: refresh)
            .alert(errorText, isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
            .sheet(item: $item) { it in
                ShareSheet(items: [it.url])
            }
        }
    }
}
