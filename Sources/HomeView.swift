import SwiftUI

struct HomeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let colors: [Color]
    let delay: Double
    let appeared: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glass(20)
        }
        .buttonStyle(PressableStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 26)
        .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(delay), value: appeared)
    }
}

struct StatTile: View {
    let value: Int
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.accent)
            Text("\(value)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: value)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(16)
    }
}

struct HomeView: View {
    let pointsCount: Int
    let areasCount: Int
    let routesCount: Int
    let baseName: String
    let online: Bool
    let files: [URL]
    let onOpenMap: () -> Void
    let onDownload: () -> Void
    let onNavigate: () -> Void
    let onImport: () -> Void
    let onOpenFile: (URL) -> Void

    @State private var appeared = false
    @State private var glow = false

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    statsRow
                    cards
                    filesSection
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            appeared = true
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 58, height: 58)
                    .shadow(color: Theme.accent.opacity(glow ? 0.8 : 0.3), radius: glow ? 18 : 8)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color.black.opacity(0.75))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("خرائطي")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.accentGradient)
                Text(baseName)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            Spacer()
            statusChip
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -16)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appeared)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(online ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(online ? "متصل" : "دون إنترنت")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glass(14)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(value: pointsCount, label: "نقطة", icon: "mappin.and.ellipse")
            StatTile(value: areasCount, label: "منطقة", icon: "square.on.square.dashed")
            StatTile(value: routesCount, label: "مسار", icon: "point.topleft.down.curvedto.point.bottomright.up")
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.7).delay(0.15), value: appeared)
    }

    private var cards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            HomeCard(icon: "map.fill", title: "الخريطة", subtitle: "افتح الخريطة والبيانات المحفوظة",
                     colors: [Theme.teal, Color(red: 0.1, green: 0.5, blue: 0.5)],
                     delay: 0.2, appeared: appeared, action: onOpenMap)
            HomeCard(icon: "location.north.circle.fill", title: "ملاحة", subtitle: "من موقعك إلى أي نقطة",
                     colors: [Theme.accent, Theme.accentDeep],
                     delay: 0.28, appeared: appeared, action: onNavigate)
            HomeCard(icon: "arrow.down.circle.fill", title: "خرائط دون إنترنت", subtitle: "نزّل منطقة واستخدمها بلا اتصال",
                     colors: [Color(red: 0.45, green: 0.55, blue: 1.0), Color(red: 0.3, green: 0.3, blue: 0.85)],
                     delay: 0.36, appeared: appeared, action: onDownload)
            HomeCard(icon: "square.and.arrow.down.fill", title: "استيراد", subtitle: "ملفات LDK وخرائط MBTiles",
                     colors: [Color(red: 0.95, green: 0.4, blue: 0.5), Color(red: 0.75, green: 0.2, blue: 0.35)],
                     delay: 0.44, appeared: appeared, action: onImport)
        }
    }

    private func sizeText(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let n = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !files.isEmpty {
                Text("الملفات")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            ForEach(files, id: \.self) { url in
                Button {
                    Haptics.tap()
                    onOpenFile(url)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: url.pathExtension.lowercased() == "ldk" ? "doc.text.fill" : "map")
                            .foregroundColor(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(url.pathExtension.uppercased() + "  •  " + sizeText(url))
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.55))
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .padding(12)
                    .glass(14)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.7).delay(0.5), value: appeared)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("تصميم وبرمجة")
                .font(.system(size: 10))
                .foregroundColor(Theme.accent)
            Text("الملازم أول طبابة منتظر يسر جبار")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.8))
        }
        .padding(.top, 14)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.8).delay(0.7), value: appeared)
    }
}
