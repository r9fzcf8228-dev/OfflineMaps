import Foundation
import CoreLocation

struct MapPoint: Identifiable, Codable {
    var id: UUID
    var name: String
    var note: String
    var lat: Double
    var lon: Double
    var color: String
    var symbol: String
    var pinned: Bool

    init(id: UUID = UUID(), name: String, note: String = "", lat: Double, lon: Double,
         color: String = "red", symbol: String = "", pinned: Bool = false) {
        self.id = id
        self.name = name
        self.note = note
        self.lat = lat
        self.lon = lon
        self.color = color
        self.symbol = symbol
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey {
        case id, name, note, lat, lon, color, symbol, pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        color = (try? c.decode(String.self, forKey: .color)) ?? "red"
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? ""
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }

    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct MapShape: Identifiable, Codable {
    var id: UUID
    var kind: String      // line, area, track, route
    var name: String
    var color: String
    var dashed: Bool
    var lats: [Double]
    var lons: [Double]

    init(id: UUID = UUID(), kind: String, name: String, color: String,
         dashed: Bool = false, coords: [CLLocationCoordinate2D]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.color = color
        self.dashed = dashed
        self.lats = coords.map { $0.latitude }
        self.lons = coords.map { $0.longitude }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, color, dashed, lats, lons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "line"
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        color = (try? c.decode(String.self, forKey: .color)) ?? "black"
        dashed = (try? c.decode(Bool.self, forKey: .dashed)) ?? false
        lats = (try? c.decode([Double].self, forKey: .lats)) ?? []
        lons = (try? c.decode([Double].self, forKey: .lons)) ?? []
    }

    var coords: [CLLocationCoordinate2D] {
        let n = min(lats.count, lons.count)
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            out.append(CLLocationCoordinate2D(latitude: lats[i], longitude: lons[i]))
        }
        return out
    }
}

final class ProjectStore: ObservableObject {
    @Published var points: [MapPoint] = []
    @Published var shapes: [MapShape] = []
    @Published var imported: [String] = []
    @Published var revision: Int = 0

    private struct FileData: Codable {
        var points: [MapPoint]
        var shapes: [MapShape]
        var imported: [String]
    }

    private var fileURL: URL {
        return MapStore.shared.dir.appendingPathComponent("project.json")
    }

    init() {
        load()
    }

    func load() {
        guard let d = try? Data(contentsOf: fileURL),
              let f = try? JSONDecoder().decode(FileData.self, from: d) else { return }
        points = f.points
        shapes = f.shapes
        imported = f.imported
        revision += 1
    }

    func save() {
        let f = FileData(points: points, shapes: shapes, imported: imported)
        if let d = try? JSONEncoder().encode(f) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }

    func changed() {
        revision += 1
        save()
    }

    func importLDK(_ d: LDKData, name: String) {
        if imported.contains(name) { return }
        for p in d.points {
            points.append(MapPoint(name: p.name, note: p.comment,
                                   lat: p.coordinate.latitude, lon: p.coordinate.longitude,
                                   color: p.color))
        }
        for s in d.shapes {
            var kind = "line"
            if s.kind == .area { kind = "area" }
            if s.kind == .track { kind = "track" }
            shapes.append(MapShape(kind: kind, name: s.name, color: s.color,
                                   dashed: s.dashed, coords: s.coords))
        }
        imported.append(name)
        changed()
    }

    func upsert(_ p: MapPoint) {
        var q = p
        q.pinned = true
        if let i = points.firstIndex(where: { $0.id == q.id }) {
            points[i] = q
        } else {
            points.append(q)
        }
        changed()
    }

    func deletePoint(_ id: UUID) {
        points.removeAll(where: { $0.id == id })
        changed()
    }

    func move(_ id: UUID, to c: CLLocationCoordinate2D) {
        if let i = points.firstIndex(where: { $0.id == id }) {
            points[i].lat = c.latitude
            points[i].lon = c.longitude
            points[i].pinned = true
            changed()
        }
    }

    func addRoute(name: String, coords: [CLLocationCoordinate2D]) {
        if coords.count < 2 { return }
        shapes.append(MapShape(kind: "route", name: name, color: "blue", dashed: false, coords: coords))
        changed()
    }

    func clearAll() {
        points = []
        shapes = []
        imported = []
        changed()
    }
}
