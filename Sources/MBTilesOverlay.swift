import MapKit
import SQLite3

final class MBTilesOverlay: MKTileOverlay {
    private var db: OpaquePointer?

    init(path: String) {
        super.init(urlTemplate: nil)
        sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        canReplaceMapContent = true
    }

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        let y = (1 << path.z) - 1 - path.y
        var stmt: OpaquePointer?
        let sql = "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?"
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(path.z))
        sqlite3_bind_int(stmt, 2, Int32(path.x))
        sqlite3_bind_int(stmt, 3, Int32(y))
        if sqlite3_step(stmt) == SQLITE_ROW, let b = sqlite3_column_blob(stmt, 0) {
            let n = Int(sqlite3_column_bytes(stmt, 0))
            result(Data(bytes: b, count: n), nil)
        } else {
            result(nil, nil)
        }
        sqlite3_finalize(stmt)
    }
}
