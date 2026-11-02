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

struct NavBanner: View {
    @ObservedObject var nav: Navigator

    private var delta: Double {
        var d = nav.bearing - nav.heading
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private var bigDistance: String {
        if nav.arrived { return "وصلت" }
        if nav.roadMode { return Coords.formatDistance(nav.stepDistance) }
        return Coords.formatDistance(nav.distance)
    }

    private var mainText: String {
        if nav.arrived { return nav.targetName }
        if nav.roadMode && !nav.instruction.isEmpty { return nav.instruction }
        if nav.hasFix { return nav.targetName }
        return "جاري تحديد موقعك..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accentGradient)
                    if nav.arrived {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.black.opacity(0.8))
                    } else if nav.roadMode {
                        Image(systemName: nav.maneuver)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(Color.black.opacity(0.8))
                    } else {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.black.opacity(0.8))
                            .rotationEffect(.degrees(delta))
                            .animation(.easeOut(duration: 0.3), value: delta)
                    }
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 3) {
                    Text(bigDistance)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: bigDistance)
                    Text(mainText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if nav.roadMode && !nav.nextInstruction.isEmpty && !nav.arrived {
                HStack(spacing: 8) {
                    Text("ثم")
                    Image(systemName: nav.nextManeuver)
                    Text(nav.nextInstruction)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))
            }

            if !nav.roadMode && !nav.arrived && !nav.status.isEmpty {
                Text(nav.status)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.65))
            }
        }
        .padding(12)
        .glass(20)
    }
}

struct NavBottomBar: View {
    @ObservedObject var nav: Navigator
    let following: Bool
    let onRecenter: () -> Void
    let onStop: () -> Void

    private var arrivalText: String {
        if nav.eta <= 0 { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date().addingTimeInterval(nav.eta))
    }

    private var remainText: String {
        let m = nav.remaining > 0 ? nav.remaining : nav.distance
        return Coords.formatDistance(m)
    }

    private var etaText: String {
        if nav.eta > 0 { return Coords.formatDuration(nav.eta) }
        return "—"
    }

    private var speedText: String {
        return String(Int((nav.speed * 3.6).rounded()))
    }

    private func circleButton(_ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(color, in: Circle())
        }
        .buttonStyle(PressableStyle())
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .overlay(Circle().stroke(Theme.accent.opacity(0.7), lineWidth: 2))
                VStack(spacing: 0) {
                    Text(speedText)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: speedText)
                    Text("km/h")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 2) {
                Text(arrivalText)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(remainText + "  •  " + etaText)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            if !following {
                circleButton("location.fill", Theme.accentDeep) { onRecenter() }
                    .transition(.scale.combined(with: .opacity))
            }
            circleButton(nav.voice ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         Color.white.opacity(0.18)) {
                nav.voice.toggle()
            }
            circleButton("xmark", Color.red.opacity(0.9)) { onStop() }
        }
        .padding(12)
        .glass(26)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: following)
    }
}
