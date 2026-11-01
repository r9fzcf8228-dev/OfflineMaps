import SwiftUI

struct SplashView: View {
    let onFinish: () -> Void

    @State private var spin = false
    @State private var pulse = false
    @State private var blink = false
    @State private var showEmblem = false
    @State private var showTitle = false
    @State private var showCredit = false
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 26) {
                Spacer()
                radar
                titleBlock
                Spacer()
                creditBlock
                loadingBar
            }
            .padding(.bottom, 36)
        }
        .onAppear { begin() }
    }

    private var sweepGradient: AngularGradient {
        return AngularGradient(
            stops: [
                Gradient.Stop(color: Color.clear, location: 0.0),
                Gradient.Stop(color: Theme.accent.opacity(0.55), location: 0.25),
                Gradient.Stop(color: Color.clear, location: 0.2501),
                Gradient.Stop(color: Color.clear, location: 1.0)
            ],
            center: .center
        )
    }

    private var radar: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Theme.accent.opacity(0.38 - Double(i) * 0.09), lineWidth: 1.5)
                    .frame(width: CGFloat(90 + i * 70), height: CGFloat(90 + i * 70))
                    .scaleEffect(pulse ? 1.06 : 0.95)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            }
            Rectangle()
                .fill(Theme.accent.opacity(0.25))
                .frame(width: 1, height: 230)
            Rectangle()
                .fill(Theme.accent.opacity(0.25))
                .frame(width: 230, height: 1)
            Circle()
                .fill(sweepGradient)
                .frame(width: 230, height: 230)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2.8).repeatForever(autoreverses: false), value: spin)
            blip(x: 52, y: -44, delay: 0.0)
            blip(x: -66, y: 30, delay: 0.5)
            blip(x: 20, y: 74, delay: 1.0)
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 62, height: 62)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 16)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.black.opacity(0.75))
            }
        }
        .frame(width: 240, height: 240)
        .scaleEffect(showEmblem ? 1 : 0.4)
        .opacity(showEmblem ? 1 : 0)
    }

    private func blip(x: CGFloat, y: CGFloat, delay: Double) -> some View {
        Circle()
            .fill(Theme.teal)
            .frame(width: 7, height: 7)
            .shadow(color: Theme.teal, radius: 5)
            .offset(x: x, y: y)
            .opacity(blink ? 1 : 0.1)
            .animation(.easeInOut(duration: 0.9).delay(delay).repeatForever(autoreverses: true), value: blink)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("خرائطي")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(Theme.accentGradient)
            Text("OFFLINE TACTICAL MAPS")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundColor(Color.white.opacity(0.7))
        }
        .opacity(showTitle ? 1 : 0)
        .offset(y: showTitle ? 0 : 26)
    }

    private var creditBlock: some View {
        VStack(spacing: 6) {
            Text("تصميم وبرمجة")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.accent)
            Text("الملازم أول طبابة")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.9))
            Text("منتظر يسر جبار")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(Color.white)
        }
        .opacity(showCredit ? 1 : 0)
        .offset(y: showCredit ? 0 : 20)
    }

    private var loadingBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(width: 180, height: 4)
    }

    private func begin() {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
            showEmblem = true
        }
        spin = true
        pulse = true
        blink = true
        withAnimation(.easeInOut(duration: 3.2)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.8)) { showTitle = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.8)) { showCredit = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            onFinish()
        }
    }
}
