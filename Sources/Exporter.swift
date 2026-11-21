static func geojson(points: [MapPoint], shapes: [MapShape]) -> String {
        var features: [String] = []
        for p in points {
            let geom = "{\"type\":\"Point\",\"coordinates\":[\(p.lon),\(p.lat)]}"
            let props = "{\"name\":\"\(escapeJSON(p.name))\",\"note\":\"\(escapeJSON(p.note))\",\"color\":\"\(p.color)\"}"
            features.append("{\"type\":\"Feature\",\"geometry\":\(geom),\"properties\":\(props)}")
        }
        for s in shapes {
            let cs = s.coords
            if cs.count < 2 { continue }
            let type = s.kind == "area" ? "Polygon" : "LineString"
            var coordStr = cs.map { "[\($0.longitude),\($0.latitude)]" }.joined(separator: ",")
            if s.kind == "area" {
                if let f = cs.first {
                    coordStr += ",[\(f.longitude),\(f.latitude)]"
                }
                coordStr = "[[\(coordStr)]]"
            } else {
                coordStr = "[\(coordStr)]"
            }
            let geom = "{\"type\":\"\(type)\",\"coordinates\":\(coordStr)}"
            let props = "{\"name\":\"\(escapeJSON(s.name))\",\"kind\":\"\(s.kind)\",\"color\":\"\(s.color)\"}"
            features.append("{\"type\":\"Feature\",\"geometry\":\(geom),\"properties\":\(props)}")
        }
        return "{\"type\":\"FeatureCollection\",\"features\":[\(features.joined(separator: ","))]}"
    }

    static func escapeJSON(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "\\", with: "\\\\")
        t = t.replacingOccurrences(of: "\"", with: "\\\"")
        t = t.replacingOccurrences(of: "\n", with: "\\n")
        return t
    }
