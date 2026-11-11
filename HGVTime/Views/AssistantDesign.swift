import SwiftUI

/// Visual pieces for the assistant screen: aurora background, AI orb, glass bubbles, typing dots.
enum AIStyle {
    static let violet = Color(red: 0.55, green: 0.36, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.85, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.35, blue: 0.75)
    static let deep = Color(red: 0.04, green: 0.04, blue: 0.10)
    static let accent = LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let border = LinearGradient(colors: [cyan.opacity(0.7), violet.opacity(0.5), pink.opacity(0.4)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Slowly drifting coloured light on a near-black background.
struct AuroraBackground: View {
    var energy: Double = 0   // 0 idle … 1 busy

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate * (0.12 + energy * 0.25)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    AIStyle.deep
                    blob(AIStyle.violet, size: w * 1.1, x: w * (0.2 + 0.25 * sin(t)), y: h * (0.15 + 0.08 * cos(t * 0.8)))
                    blob(AIStyle.cyan, size: w * 0.9, x: w * (0.85 + 0.2 * cos(t * 1.1)), y: h * (0.45 + 0.12 * sin(t * 0.7)))
                    blob(AIStyle.pink, size: w * 0.8, x: w * (0.3 + 0.2 * sin(t * 0.9 + 2)), y: h * (0.9 + 0.06 * cos(t)))
                    // Fine grid for a "HUD" feel.
                    Canvas { ctx, size in
                        let step: CGFloat = 28
                        var path = Path()
                        stride(from: 0, through: size.width, by: step).forEach { x in
                            path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height))
                        }
                        stride(from: 0, through: size.height, by: step).forEach { y in
                            path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y))
                        }
                        ctx.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ c: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c.opacity(0.55 + energy * 0.2), c.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .blur(radius: 40)
    }
}

/// The assistant's "face": a glowing orb that spins faster and pulses while listening or thinking.
struct AIOrb: View {
    enum Mood { case idle, listening, thinking }
    var mood: Mood = .idle
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let speed = mood == .idle ? 0.4 : (mood == .thinking ? 1.6 : 1.0)
            let pulse = mood == .listening ? 1 + 0.08 * sin(t * 6) : (mood == .thinking ? 1 + 0.04 * sin(t * 3) : 1 + 0.02 * sin(t * 1.5))
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [AIStyle.cyan, AIStyle.violet, AIStyle.pink, AIStyle.cyan],
                                          center: .center, angle: .degrees(t * 60 * speed)))
                    .blur(radius: size * 0.18)
                    .opacity(0.9)
                    .scaleEffect(1.25 * pulse)
                Circle()
                    .fill(AngularGradient(colors: [AIStyle.violet, AIStyle.cyan, AIStyle.pink, AIStyle.violet],
                                          center: .center, angle: .degrees(-t * 90 * speed)))
                    .overlay(
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.85), .clear], center: .init(x: 0.35, y: 0.3),
                                                     startRadius: 0, endRadius: size * 0.45))
                    )
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                    .scaleEffect(pulse)
                if mood == .listening {
                    ForEach(0..<3) { i in
                        let phase = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle().stroke(AIStyle.cyan.opacity(1 - phase), lineWidth: 1.5)
                            .scaleEffect(1 + phase * 0.8)
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// Three bouncing dots in the accent gradient.
struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(AIStyle.accent)
                        .frame(width: 7, height: 7)
                        .offset(y: -4 * max(0, sin(t * 6 - Double(i) * 0.7)))
                        .opacity(0.5 + 0.5 * max(0, sin(t * 6 - Double(i) * 0.7)))
                }
            }
        }
        .accessibilityLabel("Thinking")
    }
}

extension View {
    /// Frosted glass with a thin gradient edge.
    func aiGlass(cornerRadius: CGFloat = 20, tint: Color = .clear) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(AIStyle.border, lineWidth: 0.8))
        }
    }
}
