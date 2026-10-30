import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let mbtiles = UTType(filenameExtension: "mbtiles") ?? .data
    static let ldk     = UTType(filenameExtension: "ldk") ?? .data
    static let gpx     = UTType(filenameExtension: "gpx") ?? .xml
    static let kml     = UTType(filenameExtension: "kml") ?? .xml
}

final class MapStore {
    static let shared = MapStore()
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
    }
}
