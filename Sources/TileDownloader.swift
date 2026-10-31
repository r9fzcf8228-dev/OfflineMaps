import Foundation
import SQLite3

struct GeoBounds {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double
}

enum TileMath {
    static func tx(_ lon: Double, _ z: Int) -> Int {
        let n = pow(2.0, Double(z))
        let v = Int(floor((lon + 180.0) / 360.0 * n))
        return max(0, min(Int(n) - 1, v))
    }

    static func ty(_ lat: Double, _ z: Int) -> Int {
        let n = pow(2.0, Double(z))
        let la = max(-85.0511, min(85.0511, lat))
        let rad = la * Double.pi / 180
        let v = Int(floor((1.0 - asinh(tan(rad)) / Double.pi) / 2.0 * n))
        return max(0, min(Int(n) - 1, v))
    }

    static func count(_ b: GeoBounds, _ minZ: Int, _ maxZ: Int) -> Int {
        if maxZ < minZ { return 0 }
        var total = 0
        for z in minZ...maxZ {
            let x1 = tx(b.minLon, z)
            let x2 = tx(b.maxLon, z)
            let y1 = ty(b.maxLat, z)
            let y2 = ty(b.minLat, z)
            total += (x2 - x1 + 1) * (y2 - y1 + 1)
        }
        return total
    }
}

private let tileTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class MBTilesWriter {
    private var db: OpaquePointer?
    private var stmt: OpaquePointer?

    init?(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK { return nil }
        exec("CREATE TABLE IF NOT EXISTS metadata (name TEXT, value TEXT)")
        exec("CREATE TABLE IF NOT EXISTS tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)")
        exec("CREATE UNIQUE INDEX IF NOT EXISTS tile_index ON tiles (zoom_level, tile_column, tile_row)")
        let sql = "INSERT OR REPLACE INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return nil }
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    func begin() { exec("BEGIN") }
    func commit() { exec("COMMIT") }

    func put(z: Int, x: Int, y: Int, data: Data) {
        let row = (1 << z) - 1 - y
        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(z))
        sqlite3_bind_int(stmt, 2, Int32(x))
        sqlite3_bind_int(stmt, 3, Int32(row))
        data.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, 4, raw.baseAddress, Int32(data.count), tileTransient)
        }
        sqlite3_step(stmt)
    }

    func setMeta(_ name: String, _ value: String) {
        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM metadata WHERE name = ?", -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_text(del, 1, name, -1, tileTransient)
            sqlite3_step(del)
        }
        sqlite3_finalize(del)
        var ins: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT INTO metadata (name, value) VALUES (?, ?)", -1, &ins, nil) == SQLITE_OK {
            sqlite3_bind_text(ins, 1, name, -1, tileTransient)
            sqlite3_bind_text(ins, 2, value, -1, tileTransient)
            sqlite3_step(ins)
        }
        sqlite3_finalize(ins)
    }

    func close() {
        if stmt != nil { sqlite3_finalize(stmt) }
        stmt = nil
        if db != nil { sqlite3_close(db) }
        db = nil
    }
}

final class TileDownloader: ObservableObject {
    static let maxTiles = 40000

    @Published var running = false
    @Published var done = 0
    @Published var total = 0
    @Published var failed = 0
    @Published var status = ""

    private let lock = NSLock()
    private var cancelFlag = false

    func cancel() {
        lock.lock()
        cancelFlag = true
        lock.unlock()
        status = "جاري الإيقاف..."
    }

    private func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelFlag
    }

    func start(template: String, bounds b: GeoBounds, minZ: Int, maxZ: Int, fileName: String,
               onFinish: @escaping (Bool, String) -> Void) {
        if running { return }
        let count = TileMath.count(b, minZ, maxZ)
        if count <= 0 || count > TileDownloader.maxTiles {
            status = "عدد البلاطات غير مناسب (الحد الأقصى \(TileDownloader.maxTiles))"
            return
        }
        lock.lock()
        cancelFlag = false
        lock.unlock()

        running = true
        done = 0
        failed = 0
        total = count
        status = "جاري التنزيل..."

        let path = MapStore.shared.dir.appendingPathComponent(fileName).path

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let writer = MBTilesWriter(path: path) else {
                DispatchQueue.main.async {
                    self.running = false
                    self.status = "تعذر إنشاء ملف الخريطة"
                    onFinish(false, fileName)
                }
                return
            }

            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 20
            cfg.httpMaximumConnectionsPerHost = 4
            let session = URLSession(configuration: cfg)
            let sem = DispatchSemaphore(value: 4)
            let group = DispatchGroup()
            let wlock = NSLock()
            var doneCount = 0
            var failCount = 0
            var sinceCommit = 0
            var format = ""

            writer.begin()

            outer: for z in minZ...maxZ {
                let x1 = TileMath.tx(b.minLon, z)
                let x2 = TileMath.tx(b.maxLon, z)
                let y1 = TileMath.ty(b.maxLat, z)
                let y2 = TileMath.ty(b.minLat, z)
                for x in x1...x2 {
                    for y in y1...y2 {
                        if self.isCancelled() { break outer }
                        sem.wait()
                        group.enter()

                        let urlStr = template
                            .replacingOccurrences(of: "{z}", with: "\(z)")
                            .replacingOccurrences(of: "{x}", with: "\(x)")
                            .replacingOccurrences(of: "{y}", with: "\(y)")
                        guard let url = URL(string: urlStr) else {
                            wlock.lock()
                            failCount += 1
                            doneCount += 1
                            wlock.unlock()
                            sem.signal()
                            group.leave()
                            continue
                        }

                        var req = URLRequest(url: url)
                        req.setValue("OfflineMapsApp/1.0", forHTTPHeaderField: "User-Agent")
                        session.dataTask(with: req) { data, resp, _ in
                            var ok = false
                            if let d = data, let http = resp as? HTTPURLResponse,
                               http.statusCode == 200, d.count > 100 {
                                ok = true
                                wlock.lock()
                                writer.put(z: z, x: x, y: y, data: d)
                                if format.isEmpty {
                                    format = (d.first == 0xFF) ? "jpg" : "png"
                                }
                                sinceCommit += 1
                                if sinceCommit >= 300 {
                                    writer.commit()
                                    writer.begin()
                                    sinceCommit = 0
                                }
                                wlock.unlock()
                            }
                            wlock.lock()
                            doneCount += 1
                            if !ok { failCount += 1 }
                            let dc = doneCount
                            let fc = failCount
                            wlock.unlock()
                            if dc % 20 == 0 || dc == count {
                                DispatchQueue.main.async {
                                    self.done = dc
                                    self.failed = fc
                                }
                            }
                            sem.signal()
                            group.leave()
                        }.resume()
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }

            group.wait()
            writer.commit()
            let okCount = doneCount - failCount
            if okCount > 0 {
                let name = (fileName as NSString).deletingPathExtension
                writer.setMeta("name", name)
                writer.setMeta("format", format.isEmpty ? "png" : format)
                writer.setMeta("type", "baselayer")
                writer.setMeta("version", "1")
                writer.setMeta("minzoom", "\(minZ)")
                writer.setMeta("maxzoom", "\(maxZ)")
                writer.setMeta("bounds", "\(b.minLon),\(b.minLat),\(b.maxLon),\(b.maxLat)")
            }
            writer.close()

            let wasCancelled = self.isCancelled()
            if okCount == 0 {
                try? FileManager.default.removeItem(atPath: path)
            }
            DispatchQueue.main.async {
                self.done = doneCount
                self.failed = failCount
                self.running = false
                if okCount == 0 {
                    self.status = "فشل التنزيل: تحقق من الرابط ومن الإنترنت"
                    onFinish(false, fileName)
                } else if wasCancelled {
                    self.status = "تم الإيقاف. حُفظ \(okCount) بلاطة"
                    onFinish(true, fileName)
                } else {
                    self.status = "اكتمل التنزيل: \(okCount) بلاطة، فشل \(failCount)"
                    onFinish(true, fileName)
                }
            }
        }
    }
}
