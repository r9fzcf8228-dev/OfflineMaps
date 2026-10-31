import SwiftUI
import CoreLocation

struct NavTargetSheet: View {
    let points: [MapPoint]
    let center: CLLocationCoordinate2D?
    let user: CLLocation?
    let onStart: (CLLocationCoordinate2D, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var coordText = ""

    private var origin: CLLocationCoordinate2D? {
        if let u = user { return u.coordinate }
        return center
    }

    private var filtered: [MapPoint] {
        var list = points
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(q) }
        }
        if let o = origin {
            list.sort { Coords.distance(o, $0.coordinate) < Coords.distance(o, $1.coordinate) }
        }
        return Array(list.prefix(60))
    }

    private func distanceText(_ p: MapPoint) -> String {
        guard let o = origin else { return "" }
        return Coords.formatDistance(Coords.distance(o, p.coordinate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ابدأ الملاحة من موقعك الحالي إلى:") {
                    if let c = center {
                        Button {
                            onStart(c, "مركز الخريطة")
                            dismiss()
                        } label: {
                            Label("مركز الخريطة (علامة +)", systemImage: "scope")
                        }
                        Text(Coords.mgrsString(c))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section("إحداثيات (MGRS أو UTM أو عشري)") {
                    TextField("مثال: 38S MD 15154 71396", text: $coordText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if let c = Coords.parse(coordText) {
                        Button {
                            onStart(c, Coords.mgrsString(c))
                            dismiss()
                        } label: {
                            Label("ابدأ الملاحة", systemImage: "location.north.line.fill")
                        }
                    } else if !coordText.isEmpty {
                        Text("صيغة غير مفهومة").foregroundColor(.red)
                    }
                }

                Section("النقاط المحفوظة (الأقرب أولاً)") {
                    TextField("بحث بالاسم", text: $query)
                    ForEach(filtered) { p in
                        Button {
                            onStart(p.coordinate, p.name)
                            dismiss()
                        } label: {
                            HStack {
                                Text(p.name.isEmpty ? "بدون اسم" : p.name)
                                Spacer()
                                Text(distanceText(p))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    if points.isEmpty {
                        Text("لا توجد نقاط محفوظة.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("الملاحة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
    }
}

struct NavHUD: View {
    @ObservedObject var nav: Navigator
    let online: Bool
    let onStop: () -> Void

    private var delta: Double {
        var d = nav.bearing - nav.heading
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private var remainText: String {
        let m = nav.remaining > 0 ? nav.remaining : nav.distance
        return Coords.formatDistance(m)
    }

    private var etaText: String {
        if nav.eta > 0 { return Coords.formatDuration(nav.eta) }
        return "—"
    }

    private var bearingText: String {
        let deg = String(format: "%.0f", nav.bearing)
        return "\(deg)° / \(Coords.mils(nav.bearing)) mil"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Theme.accent.opacity(0.45), lineWidth: 2)
                        .frame(width: 66, height: 66)
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 66, height: 66)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.accent)
                        .rotationEffect(.degrees(delta))
                        .animation(.easeOut(duration: 0.3), value: delta)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(remainText)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: remainText)
                    Text(nav.targetName)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(etaText, systemImage: "clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(bearingText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.7))
                }
            }

            if nav.arrived {
                Label("وصلت إلى الهدف", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if nav.roadMode && !nav.instruction.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.up.right")
                        .foregroundColor(Theme.accent)
                    Text(nav.instruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer()
                    Text(Coords.formatDistance(nav.stepDistance))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            } else {
                Text(nav.hasFix ? nav.status : "جاري تحديد موقعك...")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.7))
            }

            if !online && !nav.roadMode {
                Label("بدون إنترنت: السهم يشير إلى الهدف مباشرة", systemImage: "wifi.slash")
                    .font(.system(size: 11))
                    .foregroundColor(Color.orange)
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    nav.voice.toggle()
                } label: {
                    Image(systemName: nav.voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 44, height: 36)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundColor(.white)
                }
                .buttonStyle(PressableStyle())

                Button {
                    Haptics.success()
                    onStop()
                } label: {
                    Label("إنهاء الملاحة", systemImage: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundColor(.white)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(14)
        .glass(22)
    }
}
