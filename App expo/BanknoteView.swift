//
//  BanknoteView.swift
//  App expo
//
//  Banknote Replicas - note1: Greek 200 Drachma, note2: Suriname 500 Gulden
//

import SwiftUI

enum BanknoteType {
    case note1  // Greek 200 Drachma
    case note2  // Suriname 500 Gulden
}

struct BanknoteView: View {
    @State private var tapLocation: CGPoint = .zero
    @State private var rippleTrigger: Int = 0
    @State private var currentNote: BanknoteType = .note2  // Default to note2 (Suriname)
    @State private var wingFlapTrigger: Int = 0  // For bird wing animation
    @State private var foldProgress: CGFloat = 0  // 0 = flat, 1 = fully folded
    @State private var dragStart: CGPoint = .zero  // Where drag started (normalized)
    @State private var dragCurrent: CGPoint = .zero  // Current drag position (normalized)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let noteWidth = width * 0.8
            let noteHeight = height * 0.8

            ZStack {
                // Dark background
                Color.black

                // Main banknote with ripple effect and smooth fold capability
                Group {
                    switch currentNote {
                    case .note1:
                        GreekDrachmaContent()
                    case .note2:
                        SurinameGuldenContent(wingFlapTrigger: wingFlapTrigger)
                    }
                }
                .frame(width: noteWidth, height: noteHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .drawingGroup()  // Flatten all layers before applying shader
                .paperFold(progress: foldProgress, curlRadius: 0.15, dragStart: dragStart, dragCurrent: dragCurrent)
                .modifier(RippleEffect(origin: tapLocation, trigger: rippleTrigger))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            // Double-tap to switch between notes
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentNote = currentNote == .note1 ? .note2 : .note1
                            }
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            // Single tap for ripple effect and wing flap
                            let noteX = (width - noteWidth) / 2
                            let noteY = (height - noteHeight) / 2

                            let relativeX = value.location.x - noteX
                            let relativeY = value.location.y - noteY

                            if relativeX >= 0 && relativeX <= noteWidth &&
                               relativeY >= 0 && relativeY <= noteHeight {
                                tapLocation = CGPoint(x: relativeX, y: relativeY)
                                rippleTrigger += 1
                                // Trigger wing flap animation
                                wingFlapTrigger += 1
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            // Track normalized start position (0-1 range within note)
                            let noteX = (width - noteWidth) / 2
                            let noteY = (height - noteHeight) / 2

                            // Normalize start position
                            let startX = (value.startLocation.x - noteX) / noteWidth
                            let startY = (value.startLocation.y - noteY) / noteHeight
                            dragStart = CGPoint(x: max(0, min(1, startX)), y: max(0, min(1, startY)))

                            // Normalize current position
                            let curX = (value.location.x - noteX) / noteWidth
                            let curY = (value.location.y - noteY) / noteHeight
                            dragCurrent = CGPoint(x: max(0, min(1, curX)), y: max(0, min(1, curY)))

                            // Calculate progress based on drag distance
                            let dragAmount = -value.translation.width
                            if dragAmount > 0 {
                                let dx = value.translation.width
                                let dy = value.translation.height
                                let totalDrag = sqrt(dx * dx + dy * dy)
                                foldProgress = min(1, totalDrag / noteWidth)
                            } else {
                                foldProgress = 0
                            }
                        }
                        .onEnded { _ in
                            // Only animate foldProgress — angle stays frozen.
                            // dragStart/dragCurrent are left as-is (shader ignores
                            // them when foldProgress is 0, and the next drag overwrites them).
                            withAnimation(.spring(response: 2.0, dampingFraction: 0.85)) {
                                foldProgress = 0
                            }
                        }
                )
            }
            .frame(width: width, height: height)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page Curl Effect using Metal Shader

struct FoldModifier: ViewModifier, Animatable {
    var progress: CGFloat
    var curlRadius: CGFloat
    var dragStart: CGPoint    // Where the drag started (0-1 normalized)
    var dragCurrent: CGPoint  // Current drag position (0-1 normalized)

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            view.layerEffect(
                ShaderLibrary.pageCurl(
                    .float2(proxy.size),
                    .float(progress),
                    .float(curlRadius),
                    .float2(dragStart.x, dragStart.y),
                    .float2(dragCurrent.x, dragCurrent.y)
                ),
                maxSampleOffset: CGSize(width: proxy.size.width, height: proxy.size.height),
                isEnabled: progress > 0.001
            )
        }
    }
}

extension View {
    func paperFold(progress: CGFloat, curlRadius: CGFloat = 0.15, dragStart: CGPoint = CGPoint(x: 1, y: 0.5), dragCurrent: CGPoint = CGPoint(x: 0, y: 0.5)) -> some View {
        modifier(FoldModifier(progress: progress, curlRadius: curlRadius, dragStart: dragStart, dragCurrent: dragCurrent))
    }
}

// MARK: - Ripple Effect (Apple WWDC24 approach)

struct RippleEffect<T: Equatable>: ViewModifier {
    var origin: CGPoint
    var trigger: T

    var duration: TimeInterval = 3.0
    var amplitude: Double = 12
    var frequency: Double = 15
    var decay: Double = 8
    var speed: Double = 1200

    func body(content: Content) -> some View {
        content.keyframeAnimator(
            initialValue: 0.0,
            trigger: trigger
        ) { view, elapsedTime in
            view.modifier(RippleModifier(
                origin: origin,
                elapsedTime: elapsedTime,
                duration: duration,
                amplitude: amplitude,
                frequency: frequency,
                decay: decay,
                speed: speed
            ))
        } keyframes: { _ in
            MoveKeyframe(0.0)
            LinearKeyframe(duration, duration: duration)
        }
    }
}

struct RippleModifier: ViewModifier {
    var origin: CGPoint
    var elapsedTime: TimeInterval
    var duration: TimeInterval
    var amplitude: Double
    var frequency: Double
    var decay: Double
    var speed: Double

    func body(content: Content) -> some View {
        let shader = ShaderLibrary.ripple(
            .float2(origin),
            .float(elapsedTime),
            .float(amplitude),
            .float(frequency),
            .float(decay),
            .float(speed)
        )

        content.visualEffect { view, _ in
            view.layerEffect(
                shader,
                maxSampleOffset: CGSize(width: amplitude, height: amplitude),
                isEnabled: 0 < elapsedTime && elapsedTime < duration
            )
        }
    }
}

// MARK: - Suriname 500 Gulden Banknote

struct SurinameGuldenContent: View {
    var wingFlapTrigger: Int = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Layer 1: Base gradient background
                SurinameBackground(w: w, h: h)

                // Layer 2: All mesh/pattern overlays
                SurinamePatterns(w: w, h: h)

                // Layer 3: Map of Suriname
                SurinameMapView(w: w, h: h)

                // Layer 4: Top illustration strip
                TopDecoStrip(w: w, h: h)

                // Layer 5: Curved bank text
                CurvedBankText(w: w, h: h)

                // Layer 6: Main bird
                AccurateBird(flapTrigger: wingFlapTrigger)
                    .frame(width: w * 0.55, height: h * 0.85)
                    .offset(x: -w * 0.08, y: h * 0.02)

                // Layer 7: Butterflies
                ButterflyOverlay(w: w, h: h)

                // Layer 8: Text elements
                TextElements(w: w, h: h)

                // Layer 9: Coat of arms
                SurinameCoatOfArms()
                    .frame(width: w * 0.14, height: h * 0.22)
                    .offset(x: w * 0.28, y: -h * 0.22)

                // Layer 10: Golden border
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.75, green: 0.55, blue: 0.25),
                                Color(red: 0.90, green: 0.70, blue: 0.30),
                                Color(red: 0.75, green: 0.55, blue: 0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: w * 0.015
                    )
            }
        }
    }
}

// MARK: - Background Layer

struct SurinameBackground: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        ZStack {
            // Base yellow-gold to cream gradient
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.65, blue: 0.25),
                    Color(red: 0.92, green: 0.78, blue: 0.45),
                    Color(red: 0.95, green: 0.88, blue: 0.65),
                    Color(red: 0.96, green: 0.92, blue: 0.75)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Vertical stripes on left side (golden)
            HStack(spacing: 0) {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(Color(red: 0.80, green: 0.55, blue: 0.20).opacity(i % 2 == 0 ? 0.3 : 0.15))
                        .frame(width: w * 0.012)
                }
                Spacer()
            }
            .padding(.leading, w * 0.05)
        }
    }
}

// MARK: - Pattern Layers

struct SurinamePatterns: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        ZStack {
            // Dense diamond mesh - covers whole note
            FullDiamondMesh()
                .stroke(Color(red: 0.70, green: 0.50, blue: 0.25).opacity(0.35), lineWidth: 0.5)

            // Circular radial pattern behind bird
            RadialLinesPattern()
                .stroke(Color(red: 0.75, green: 0.55, blue: 0.45).opacity(0.25), lineWidth: 0.5)
                .frame(width: w * 0.6, height: w * 0.6)
                .offset(x: -w * 0.05, y: h * 0.05)

            // Denser mesh on right side
            DenseDiamondMesh()
                .stroke(Color(red: 0.70, green: 0.50, blue: 0.25).opacity(0.4), lineWidth: 0.5)
                .frame(width: w * 0.4, height: h)
                .offset(x: w * 0.30)
        }
    }
}

struct FullDiamondMesh: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 8

        // Diagonal lines one way
        var x: CGFloat = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            x += spacing
        }

        // Diagonal lines other way
        x = 0
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x - rect.height, y: rect.height))
            x += spacing
        }

        return path
    }
}

struct DenseDiamondMesh: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 5

        var x: CGFloat = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            x += spacing
        }

        x = 0
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x - rect.height, y: rect.height))
            x += spacing
        }

        return path
    }
}

struct RadialLinesPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = max(rect.width, rect.height) / 2

        // Concentric circles
        for r in stride(from: CGFloat(10), to: maxRadius, by: CGFloat(8)) {
            path.addEllipse(in: CGRect(
                x: center.x - r,
                y: center.y - r,
                width: r * 2,
                height: r * 2
            ))
        }

        // Radial lines
        for i in 0..<36 {
            let angle = CGFloat(i) * .pi / 18
            path.move(to: center)
            path.addLine(to: CGPoint(
                x: center.x + maxRadius * Darwin.cos(angle),
                y: center.y + maxRadius * Darwin.sin(angle)
            ))
        }

        return path
    }
}

// MARK: - Map View

struct SurinameMapView: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        ZStack {
            // Map outline
            SurinameMapShape()
                .stroke(Color(red: 0.45, green: 0.35, blue: 0.25).opacity(0.4), lineWidth: 1.5)
                .frame(width: w * 0.28, height: h * 0.50)
                .offset(x: w * 0.20, y: h * 0.02)

            // River lines inside map
            Path { path in
                path.move(to: CGPoint(x: w * 0.62, y: h * 0.25))
                path.addQuadCurve(
                    to: CGPoint(x: w * 0.72, y: h * 0.55),
                    control: CGPoint(x: w * 0.68, y: h * 0.40)
                )
            }
            .stroke(Color(red: 0.45, green: 0.35, blue: 0.25).opacity(0.25), lineWidth: 1)
        }
    }
}

struct SurinameMapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.15, y: h * 0.10))
        path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.15))
        path.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.50),
            control1: CGPoint(x: w * 0.95, y: h * 0.30),
            control2: CGPoint(x: w * 0.92, y: h * 0.40)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.70, y: h * 0.75),
            control1: CGPoint(x: w * 0.85, y: h * 0.62),
            control2: CGPoint(x: w * 0.78, y: h * 0.70)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.40, y: h * 0.92),
            control1: CGPoint(x: w * 0.58, y: h * 0.82),
            control2: CGPoint(x: w * 0.48, y: h * 0.90)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.12, y: h * 0.65),
            control1: CGPoint(x: w * 0.25, y: h * 0.95),
            control2: CGPoint(x: w * 0.15, y: h * 0.82)
        )
        path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.35))
        path.addCurve(
            to: CGPoint(x: w * 0.15, y: h * 0.10),
            control1: CGPoint(x: w * 0.05, y: h * 0.22),
            control2: CGPoint(x: w * 0.08, y: h * 0.12)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Top Decoration Strip

struct TopDecoStrip: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        HStack(spacing: w * 0.015) {
            // Trees and decorative elements
            ForEach(0..<10, id: \.self) { i in
                if i % 3 == 0 {
                    // Tree shape
                    VStack(spacing: 0) {
                        Triangle()
                            .fill(Color(red: 0.30, green: 0.50, blue: 0.30))
                            .frame(width: w * 0.025, height: h * 0.04)
                        Rectangle()
                            .fill(Color(red: 0.50, green: 0.35, blue: 0.20))
                            .frame(width: w * 0.008, height: h * 0.02)
                    }
                } else if i % 3 == 1 {
                    // Round bush
                    Circle()
                        .fill(Color(red: 0.45, green: 0.55, blue: 0.35))
                        .frame(width: w * 0.02, height: w * 0.02)
                } else {
                    // Person/figure silhouette
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.40, blue: 0.30))
                        .frame(width: w * 0.012, height: h * 0.05)
                }
            }
            Spacer()
        }
        .frame(height: h * 0.07)
        .padding(.horizontal, w * 0.12)
        .offset(y: -h * 0.45)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Curved Bank Text

struct CurvedBankText: View {
    let w: CGFloat
    let h: CGFloat
    let brown = Color(red: 0.35, green: 0.25, blue: 0.18)

    var body: some View {
        ZStack {
            // "CENTRALE BANK" - top arc
            ArcText(text: "CENTRALE BANK", radius: w * 0.32, angleStart: -155, angleEnd: -25)
                .foregroundColor(brown.opacity(0.85))
                .offset(x: -w * 0.05, y: h * 0.02)

            // "VAN SURINAME" - bottom arc
            ArcText(text: "VAN SURINAME", radius: w * 0.32, angleStart: 25, angleEnd: 155, upsideDown: true)
                .foregroundColor(brown.opacity(0.85))
                .offset(x: -w * 0.05, y: h * 0.02)
        }
    }
}

struct ArcText: View {
    let text: String
    let radius: CGFloat
    let angleStart: Double
    let angleEnd: Double
    var upsideDown: Bool = false

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                    let totalAngle = angleEnd - angleStart
                    let charAngle = angleStart + (totalAngle * Double(index) / Double(text.count - 1))
                    let radians = charAngle * .pi / 180

                    Text(String(char))
                        .font(.system(size: radius * 0.09, weight: .semibold))
                        .position(
                            x: center.x + radius * CGFloat(Darwin.cos(radians)),
                            y: center.y + radius * CGFloat(Darwin.sin(radians))
                        )
                        .rotationEffect(.degrees(charAngle + (upsideDown ? -90 : 90)))
                }
            }
        }
    }
}

// MARK: - Butterfly Overlay

struct ButterflyOverlay: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        ZStack {
            // Orange/red butterfly - top left
            DetailedOrangeButterfly()
                .frame(width: w * 0.08, height: w * 0.065)
                .offset(x: -w * 0.35, y: -h * 0.28)

            // Small yellow-green butterfly - bottom left
            SmallGreenButterfly()
                .frame(width: w * 0.04, height: w * 0.03)
                .offset(x: -w * 0.42, y: h * 0.35)

            // White/cream butterfly - bottom right
            DetailedWhiteButterfly()
                .frame(width: w * 0.08, height: w * 0.065)
                .offset(x: w * 0.22, y: h * 0.25)
        }
    }
}

struct DetailedOrangeButterfly: View {
    let orange = Color(red: 0.85, green: 0.40, blue: 0.20)
    let orangeDark = Color(red: 0.70, green: 0.28, blue: 0.12)
    let brown = Color(red: 0.30, green: 0.18, blue: 0.10)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Upper left wing
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w * 0.05, y: h * 0.15), control: CGPoint(x: w * 0.15, y: h * 0.25))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.5), control: CGPoint(x: w * 0.10, y: h * 0.55))
                }
                .fill(orange)

                // Upper right wing
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w * 0.95, y: h * 0.15), control: CGPoint(x: w * 0.85, y: h * 0.25))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.5), control: CGPoint(x: w * 0.90, y: h * 0.55))
                }
                .fill(orange)

                // Lower wings
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w * 0.15, y: h * 0.85), control: CGPoint(x: w * 0.25, y: h * 0.65))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.5), control: CGPoint(x: w * 0.35, y: h * 0.75))
                }
                .fill(orangeDark)

                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w * 0.85, y: h * 0.85), control: CGPoint(x: w * 0.75, y: h * 0.65))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.5), control: CGPoint(x: w * 0.65, y: h * 0.75))
                }
                .fill(orangeDark)

                // Body
                Capsule()
                    .fill(brown)
                    .frame(width: w * 0.08, height: h * 0.4)
                    .position(x: w * 0.5, y: h * 0.5)

                // Antennae
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.32))
                    p.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.08), control: CGPoint(x: w * 0.40, y: h * 0.18))
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.32))
                    p.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.08), control: CGPoint(x: w * 0.60, y: h * 0.18))
                }
                .stroke(brown, lineWidth: 1)
            }
        }
    }
}

struct SmallGreenButterfly: View {
    let green = Color(red: 0.55, green: 0.65, blue: 0.35)
    let brown = Color(red: 0.35, green: 0.25, blue: 0.15)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Wings (simplified)
                Ellipse()
                    .fill(green)
                    .frame(width: w * 0.45, height: h * 0.7)
                    .position(x: w * 0.28, y: h * 0.45)

                Ellipse()
                    .fill(green)
                    .frame(width: w * 0.45, height: h * 0.7)
                    .position(x: w * 0.72, y: h * 0.45)

                // Body
                Capsule()
                    .fill(brown)
                    .frame(width: w * 0.12, height: h * 0.5)
                    .position(x: w * 0.5, y: h * 0.5)
            }
        }
    }
}

struct DetailedWhiteButterfly: View {
    let white = Color.white
    let cream = Color(red: 0.98, green: 0.95, blue: 0.85)
    let yellow = Color(red: 0.90, green: 0.75, blue: 0.30)
    let brown = Color(red: 0.45, green: 0.35, blue: 0.20)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Upper wings
                Ellipse()
                    .fill(
                        RadialGradient(colors: [white, cream], center: .center, startRadius: 0, endRadius: w * 0.3)
                    )
                    .frame(width: w * 0.48, height: h * 0.55)
                    .position(x: w * 0.28, y: h * 0.38)

                Ellipse()
                    .fill(
                        RadialGradient(colors: [white, cream], center: .center, startRadius: 0, endRadius: w * 0.3)
                    )
                    .frame(width: w * 0.48, height: h * 0.55)
                    .position(x: w * 0.72, y: h * 0.38)

                // Lower wings
                Ellipse()
                    .fill(cream)
                    .frame(width: w * 0.38, height: h * 0.42)
                    .position(x: w * 0.30, y: h * 0.70)

                Ellipse()
                    .fill(cream)
                    .frame(width: w * 0.38, height: h * 0.42)
                    .position(x: w * 0.70, y: h * 0.70)

                // Body (yellow)
                Capsule()
                    .fill(yellow)
                    .frame(width: w * 0.10, height: h * 0.45)
                    .position(x: w * 0.5, y: h * 0.52)

                // Head
                Circle()
                    .fill(brown)
                    .frame(width: w * 0.08, height: w * 0.08)
                    .position(x: w * 0.5, y: h * 0.28)

                // Antennae
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.25))
                    p.addQuadCurve(to: CGPoint(x: w * 0.38, y: h * 0.08), control: CGPoint(x: w * 0.42, y: h * 0.15))
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.25))
                    p.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.08), control: CGPoint(x: w * 0.58, y: h * 0.15))
                }
                .stroke(brown, lineWidth: 1)
            }
        }
    }
}

// MARK: - Text Elements

struct TextElements: View {
    let w: CGFloat
    let h: CGFloat
    let brown = Color(red: 0.35, green: 0.25, blue: 0.15)
    let orangeGold = Color(red: 0.85, green: 0.55, blue: 0.15)
    let orangeDark = Color(red: 0.75, green: 0.40, blue: 0.10)

    var body: some View {
        ZStack {
            // "500" top left
            Text("500")
                .font(.system(size: h * 0.14, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [orangeGold, orangeDark], startPoint: .top, endPoint: .bottom)
                )
                .position(x: w * 0.09, y: h * 0.14)

            // "500" bottom right (large)
            Text("500")
                .font(.system(size: h * 0.20, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.65, blue: 0.20),
                            Color(red: 0.80, green: 0.45, blue: 0.15),
                            Color(red: 0.70, green: 0.35, blue: 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.15), radius: 1, x: 1, y: 1)
                .position(x: w * 0.85, y: h * 0.85)

            // Serial - vertical left
            Text("AK054345")
                .font(.system(size: h * 0.038, weight: .medium, design: .monospaced))
                .foregroundColor(.black.opacity(0.9))
                .rotationEffect(.degrees(-90))
                .position(x: w * 0.04, y: h * 0.55)

            // Serial - horizontal top right
            Text("AK054345")
                .font(.system(size: h * 0.038, weight: .medium, design: .monospaced))
                .foregroundColor(.black.opacity(0.9))
                .position(x: w * 0.78, y: h * 0.12)

            // Date
            Text("1 JANUARI 2000")
                .font(.system(size: h * 0.032, weight: .regular))
                .foregroundColor(brown.opacity(0.85))
                .position(x: w * 0.52, y: h * 0.22)

            // President signature area
            VStack(spacing: 2) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 8))
                    p.addQuadCurve(to: CGPoint(x: 15, y: 4), control: CGPoint(x: 8, y: 2))
                    p.addQuadCurve(to: CGPoint(x: 30, y: 6), control: CGPoint(x: 22, y: 10))
                    p.addLine(to: CGPoint(x: 40, y: 5))
                }
                .stroke(brown.opacity(0.7), lineWidth: 1)
                .frame(width: 40, height: 12)

                Text("PRESIDENT")
                    .font(.system(size: h * 0.028, weight: .regular))
                    .foregroundColor(brown.opacity(0.85))
            }
            .position(x: w * 0.85, y: h * 0.22)

            // Scientific name
            Text("RUPICOLA RUPICOLA")
                .font(.system(size: h * 0.024, weight: .light, design: .serif))
                .italic()
                .foregroundColor(brown.opacity(0.7))
                .position(x: w * 0.45, y: h * 0.94)
        }
    }
}

// MARK: - Coat of Arms

struct SurinameCoatOfArms: View {
    let brown = Color(red: 0.45, green: 0.32, blue: 0.20)
    let gold = Color(red: 0.80, green: 0.65, blue: 0.25)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Shield outline
                Path { p in
                    p.move(to: CGPoint(x: w * 0.15, y: h * 0.18))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.18))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.55))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.88), control: CGPoint(x: w * 0.85, y: h * 0.78))
                    p.addQuadCurve(to: CGPoint(x: w * 0.15, y: h * 0.55), control: CGPoint(x: w * 0.15, y: h * 0.78))
                    p.closeSubpath()
                }
                .stroke(brown.opacity(0.6), lineWidth: 1.5)

                // Inner diamond
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h * 0.28))
                    p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.50))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.72))
                    p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.50))
                    p.closeSubpath()
                }
                .stroke(brown.opacity(0.5), lineWidth: 1)

                // Star at top
                FivePointStar()
                    .fill(gold.opacity(0.7))
                    .frame(width: w * 0.18, height: w * 0.18)
                    .position(x: w * 0.5, y: h * 0.10)

                // Side decorations (palm fronds)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.08, y: h * 0.92))
                    p.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.12), control: CGPoint(x: w * 0.0, y: h * 0.50))
                }
                .stroke(Color(red: 0.35, green: 0.50, blue: 0.30).opacity(0.6), lineWidth: 1.5)

                Path { p in
                    p.move(to: CGPoint(x: w * 0.92, y: h * 0.92))
                    p.addQuadCurve(to: CGPoint(x: w * 0.75, y: h * 0.12), control: CGPoint(x: w * 1.0, y: h * 0.50))
                }
                .stroke(Color(red: 0.35, green: 0.50, blue: 0.30).opacity(0.6), lineWidth: 1.5)
            }
        }
    }
}

struct FivePointStar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.4

        for i in 0..<10 {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let point = CGPoint(
                x: center.x + radius * Darwin.cos(angle),
                y: center.y + radius * Darwin.sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Diamond Mesh Pattern

struct DiamondMeshPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 12
        let rows = Int(rect.height / spacing) + 1
        let cols = Int(rect.width / spacing) + 1

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * spacing
                let y = CGFloat(row) * spacing

                // Diagonal lines forming diamond pattern
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + spacing, y: y + spacing))
                path.move(to: CGPoint(x: x + spacing, y: y))
                path.addLine(to: CGPoint(x: x, y: y + spacing))
            }
        }
        return path
    }
}

// MARK: - Circular Mesh Pattern

struct CircularMeshPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = max(rect.width, rect.height) / 2

        // Concentric circles
        for r in stride(from: 15.0, to: maxRadius, by: 15.0) {
            path.addEllipse(in: CGRect(
                x: center.x - r,
                y: center.y - r,
                width: r * 2,
                height: r * 2
            ))
        }

        // Radial lines
        for i in 0..<24 {
            let angle = CGFloat(i) * .pi / 12
            path.move(to: center)
            path.addLine(to: CGPoint(
                x: center.x + maxRadius * Darwin.cos(angle),
                y: center.y + maxRadius * Darwin.sin(angle)
            ))
        }

        return path
    }
}

// MARK: - Suriname Map Outline

struct SurinameMapOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Accurate Suriname outline
        path.move(to: CGPoint(x: w * 0.1, y: h * 0.15))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.12))
        path.addCurve(
            to: CGPoint(x: w * 0.85, y: h * 0.45),
            control1: CGPoint(x: w * 0.92, y: h * 0.25),
            control2: CGPoint(x: w * 0.88, y: h * 0.35)
        )
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.65))
        path.addCurve(
            to: CGPoint(x: w * 0.45, y: h * 0.90),
            control1: CGPoint(x: w * 0.68, y: h * 0.78),
            control2: CGPoint(x: w * 0.55, y: h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.15, y: h * 0.70),
            control1: CGPoint(x: w * 0.30, y: h * 0.92),
            control2: CGPoint(x: w * 0.18, y: h * 0.85)
        )
        path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.40))
        path.addCurve(
            to: CGPoint(x: w * 0.1, y: h * 0.15),
            control1: CGPoint(x: w * 0.05, y: h * 0.30),
            control2: CGPoint(x: w * 0.06, y: h * 0.20)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Top Illustration Border

struct TopIllustrationBorder: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            HStack(spacing: w * 0.02) {
                // Trees
                ForEach(0..<3, id: \.self) { _ in
                    TreeIllustration()
                        .frame(width: w * 0.06, height: h * 0.9)
                }

                // Figures/buildings
                Rectangle()
                    .fill(Color(red: 0.6, green: 0.4, blue: 0.3))
                    .frame(width: w * 0.04, height: h * 0.7)

                // More trees
                ForEach(0..<2, id: \.self) { _ in
                    TreeIllustration()
                        .frame(width: w * 0.05, height: h * 0.85)
                }

                // Animal shape
                Ellipse()
                    .fill(Color(red: 0.5, green: 0.35, blue: 0.25))
                    .frame(width: w * 0.04, height: h * 0.5)

                // More elements
                ForEach(0..<4, id: \.self) { i in
                    if i % 2 == 0 {
                        TreeIllustration()
                            .frame(width: w * 0.05, height: h * 0.8)
                    } else {
                        Circle()
                            .fill(Color(red: 0.7, green: 0.5, blue: 0.3))
                            .frame(width: w * 0.03, height: w * 0.03)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, w * 0.02)
        }
    }
}

struct TreeIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Trunk
                Rectangle()
                    .fill(Color(red: 0.5, green: 0.35, blue: 0.2))
                    .frame(width: w * 0.2, height: h * 0.4)
                    .offset(y: h * 0.3)

                // Foliage
                Ellipse()
                    .fill(Color(red: 0.3, green: 0.5, blue: 0.3))
                    .frame(width: w, height: h * 0.7)
                    .offset(y: -h * 0.1)
            }
        }
    }
}

// MARK: - Curved Text

struct CurvedText: View {
    let text: String
    let radius: CGFloat
    let startAngle: Double
    let endAngle: Double

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let angleRange = endAngle - startAngle
            let anglePerChar = angleRange / Double(text.count)

            ZStack {
                ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                    let angle = startAngle + Double(index) * anglePerChar + anglePerChar / 2
                    let radians = angle * .pi / 180

                    Text(String(char))
                        .font(.system(size: radius * 0.12, weight: .semibold))
                        .position(
                            x: center.x + radius * cos(radians),
                            y: center.y + radius * sin(radians)
                        )
                        .rotationEffect(.degrees(angle + 90))
                }
            }
        }
    }
}

// MARK: - Accurate Cock-of-the-Rock Bird

struct AccurateBird: View {
    var flapTrigger: Int = 0
    @State private var wingRotation: Double = 0
    @State private var wingOffset: CGFloat = 0

    // Colors matching the actual banknote bird
    let salmonMain = Color(red: 0.85, green: 0.45, blue: 0.38)
    let salmonLight = Color(red: 0.92, green: 0.58, blue: 0.50)
    let salmonDark = Color(red: 0.68, green: 0.32, blue: 0.28)
    let brownDark = Color(red: 0.32, green: 0.20, blue: 0.12)
    let cream = Color(red: 0.95, green: 0.92, blue: 0.85)
    let white = Color.white

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Layer 1: Body base
                BirdBodyBase(w: w, h: h, mainColor: salmonMain, darkColor: salmonDark, lightColor: salmonLight)

                // Layer 2: Feather scales on body
                FeatherScalesLayer(w: w, h: h, darkColor: salmonDark)

                // Layer 3: Wing (animated)
                BirdWingAnimated(w: w, h: h, darkColor: salmonDark, cream: cream, rotation: wingRotation, offset: wingOffset)

                // Layer 4: Head crest
                BirdCrest(w: w, h: h, mainColor: salmonMain, lightColor: salmonLight, darkColor: salmonDark)

                // Layer 5: Head and face details
                BirdFace(w: w, h: h, mainColor: salmonMain, lightColor: salmonLight, brownDark: brownDark, cream: cream)

                // Layer 6: Tail feathers
                BirdTail(w: w, h: h, darkColor: salmonDark, brownDark: brownDark, cream: cream)

                // Layer 7: Legs and branch
                BirdLegsAndBranch(w: w, h: h, brownDark: brownDark)
            }
        }
        .onChange(of: flapTrigger) { _, _ in
            withAnimation(.easeOut(duration: 0.12)) {
                wingRotation = -15
                wingOffset = -8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    wingRotation = 10
                    wingOffset = 5
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeOut(duration: 0.12)) {
                    wingRotation = -12
                    wingOffset = -6
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    wingRotation = 8
                    wingOffset = 4
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) {
                withAnimation(.easeOut(duration: 0.15)) {
                    wingRotation = -5
                    wingOffset = -2
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.59) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    wingRotation = 0
                    wingOffset = 0
                }
            }
        }
    }
}

// Bird body base shape
struct BirdBodyBase: View {
    let w: CGFloat
    let h: CGFloat
    let mainColor: Color
    let darkColor: Color
    let lightColor: Color

    var body: some View {
        Path { path in
            // Main body outline
            path.move(to: CGPoint(x: w * 0.42, y: h * 0.25))
            path.addCurve(
                to: CGPoint(x: w * 0.72, y: h * 0.35),
                control1: CGPoint(x: w * 0.55, y: h * 0.22),
                control2: CGPoint(x: w * 0.65, y: h * 0.26)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.62),
                control1: CGPoint(x: w * 0.80, y: h * 0.42),
                control2: CGPoint(x: w * 0.82, y: h * 0.52)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.55, y: h * 0.78),
                control1: CGPoint(x: w * 0.75, y: h * 0.72),
                control2: CGPoint(x: w * 0.65, y: h * 0.78)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.35, y: h * 0.65),
                control1: CGPoint(x: w * 0.45, y: h * 0.78),
                control2: CGPoint(x: w * 0.38, y: h * 0.74)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.32, y: h * 0.42),
                control1: CGPoint(x: w * 0.32, y: h * 0.58),
                control2: CGPoint(x: w * 0.30, y: h * 0.50)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.42, y: h * 0.25),
                control1: CGPoint(x: w * 0.34, y: h * 0.34),
                control2: CGPoint(x: w * 0.38, y: h * 0.28)
            )
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [lightColor, mainColor, darkColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// Feather scales pattern on body
struct FeatherScalesLayer: View {
    let w: CGFloat
    let h: CGFloat
    let darkColor: Color

    var body: some View {
        Canvas { context, size in
            // Draw feather scale pattern
            let scaleWidth: CGFloat = 12
            let scaleHeight: CGFloat = 10

            for row in 0..<18 {
                for col in 0..<12 {
                    let xOffset = row % 2 == 0 ? 0 : scaleWidth / 2
                    let x = w * 0.34 + CGFloat(col) * scaleWidth + xOffset
                    let y = h * 0.30 + CGFloat(row) * scaleHeight * 0.7

                    // Check if within body bounds (roughly)
                    let centerX = w * 0.52
                    let centerY = h * 0.50
                    let distX = abs(x - centerX) / (w * 0.25)
                    let distY = abs(y - centerY) / (h * 0.30)

                    if distX * distX + distY * distY < 1.2 && y < h * 0.72 && y > h * 0.28 {
                        let scalePath = Path { p in
                            p.move(to: CGPoint(x: x, y: y))
                            p.addQuadCurve(
                                to: CGPoint(x: x + scaleWidth, y: y),
                                control: CGPoint(x: x + scaleWidth / 2, y: y + scaleHeight)
                            )
                        }
                        context.stroke(scalePath, with: .color(darkColor.opacity(0.5)), lineWidth: 1)
                    }
                }
            }
        }
    }
}

// Bird wing with animation
struct BirdWingAnimated: View {
    let w: CGFloat
    let h: CGFloat
    let darkColor: Color
    let cream: Color
    var rotation: Double
    var offset: CGFloat

    var body: some View {
        Group {
            // Wing base
            Path { path in
                path.move(to: CGPoint(x: w * 0.48, y: h * 0.35))
                path.addCurve(
                    to: CGPoint(x: w * 0.82, y: h * 0.48),
                    control1: CGPoint(x: w * 0.60, y: h * 0.32),
                    control2: CGPoint(x: w * 0.74, y: h * 0.38)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.72, y: h * 0.68),
                    control1: CGPoint(x: w * 0.88, y: h * 0.56),
                    control2: CGPoint(x: w * 0.82, y: h * 0.64)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.48, y: h * 0.55),
                    control1: CGPoint(x: w * 0.62, y: h * 0.70),
                    control2: CGPoint(x: w * 0.52, y: h * 0.65)
                )
                path.closeSubpath()
            }
            .fill(darkColor)

            // Wing feather stripes (white/cream bars)
            ForEach(0..<8, id: \.self) { i in
                let yBase = h * (0.40 + CGFloat(i) * 0.032)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.50, y: yBase))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.75, y: yBase + h * 0.025),
                        control: CGPoint(x: w * 0.62, y: yBase - h * 0.008)
                    )
                }
                .stroke(cream.opacity(0.7), lineWidth: 2.5)
            }
        }
        .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: 0.48, y: 0.45))
        .offset(y: offset)
    }
}

// Bird head crest (prominent semicircular crest)
struct BirdCrest: View {
    let w: CGFloat
    let h: CGFloat
    let mainColor: Color
    let lightColor: Color
    let darkColor: Color

    var body: some View {
        ZStack {
            // Main crest shape
            Path { path in
                path.move(to: CGPoint(x: w * 0.42, y: h * 0.28))
                path.addCurve(
                    to: CGPoint(x: w * 0.22, y: h * 0.12),
                    control1: CGPoint(x: w * 0.35, y: h * 0.22),
                    control2: CGPoint(x: w * 0.26, y: h * 0.14)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.38, y: h * 0.06),
                    control1: CGPoint(x: w * 0.26, y: h * 0.06),
                    control2: CGPoint(x: w * 0.32, y: h * 0.04)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.52, y: h * 0.12),
                    control1: CGPoint(x: w * 0.45, y: h * 0.05),
                    control2: CGPoint(x: w * 0.50, y: h * 0.07)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.48, y: h * 0.26),
                    control1: CGPoint(x: w * 0.54, y: h * 0.18),
                    control2: CGPoint(x: w * 0.52, y: h * 0.23)
                )
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [lightColor, mainColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Crest feather lines
            ForEach(0..<12, id: \.self) { i in
                let angle = -0.6 + Double(i) * 0.1
                let startX = w * 0.40
                let startY = h * 0.20
                let endX = startX + w * 0.12 * CGFloat(Darwin.cos(angle))
                let endY = startY - h * 0.10 * CGFloat(Darwin.sin(angle) + 0.5)

                Path { p in
                    p.move(to: CGPoint(x: startX, y: startY))
                    p.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(darkColor.opacity(0.4), lineWidth: 0.8)
            }
        }
    }
}

// Bird face details
struct BirdFace: View {
    let w: CGFloat
    let h: CGFloat
    let mainColor: Color
    let lightColor: Color
    let brownDark: Color
    let cream: Color

    var body: some View {
        ZStack {
            // Head shape
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [lightColor, mainColor],
                        center: .center,
                        startRadius: 0,
                        endRadius: w * 0.08
                    )
                )
                .frame(width: w * 0.15, height: w * 0.13)
                .position(x: w * 0.40, y: h * 0.26)

            // Eye ring (white)
            Circle()
                .fill(cream)
                .frame(width: w * 0.055, height: w * 0.055)
                .position(x: w * 0.42, y: h * 0.25)

            // Eye (dark)
            Circle()
                .fill(brownDark)
                .frame(width: w * 0.035, height: w * 0.035)
                .position(x: w * 0.42, y: h * 0.25)

            // Eye highlight
            Circle()
                .fill(Color.white)
                .frame(width: w * 0.012, height: w * 0.012)
                .position(x: w * 0.425, y: h * 0.245)

            // Beak
            Path { p in
                p.move(to: CGPoint(x: w * 0.34, y: h * 0.27))
                p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.34, y: h * 0.32))
                p.closeSubpath()
            }
            .fill(brownDark)

            // Small lines near beak
            Path { p in
                p.move(to: CGPoint(x: w * 0.28, y: h * 0.29))
                p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.28))
            }
            .stroke(brownDark.opacity(0.6), lineWidth: 0.5)
        }
    }
}

// Bird tail
struct BirdTail: View {
    let w: CGFloat
    let h: CGFloat
    let darkColor: Color
    let brownDark: Color
    let cream: Color

    var body: some View {
        ZStack {
            // Tail base
            Path { path in
                path.move(to: CGPoint(x: w * 0.50, y: h * 0.72))
                path.addCurve(
                    to: CGPoint(x: w * 0.78, y: h * 0.85),
                    control1: CGPoint(x: w * 0.60, y: h * 0.74),
                    control2: CGPoint(x: w * 0.70, y: h * 0.80)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.48, y: h * 0.76),
                    control1: CGPoint(x: w * 0.68, y: h * 0.88),
                    control2: CGPoint(x: w * 0.55, y: h * 0.82)
                )
                path.closeSubpath()
            }
            .fill(brownDark.opacity(0.75))

            // Tail stripes
            ForEach(0..<5, id: \.self) { i in
                let xStart = w * (0.52 + CGFloat(i) * 0.05)
                Path { p in
                    p.move(to: CGPoint(x: xStart, y: h * 0.73))
                    p.addLine(to: CGPoint(x: xStart + w * 0.10, y: h * 0.82))
                }
                .stroke(cream.opacity(0.5), lineWidth: 1.5)
            }
        }
    }
}

// Bird legs and branch
struct BirdLegsAndBranch: View {
    let w: CGFloat
    let h: CGFloat
    let brownDark: Color

    var body: some View {
        ZStack {
            // Branch
            Path { p in
                p.move(to: CGPoint(x: w * 0.20, y: h * 0.82))
                p.addQuadCurve(
                    to: CGPoint(x: w * 0.70, y: h * 0.85),
                    control: CGPoint(x: w * 0.45, y: h * 0.78)
                )
                p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.88))
                p.addQuadCurve(
                    to: CGPoint(x: w * 0.20, y: h * 0.85),
                    control: CGPoint(x: w * 0.45, y: h * 0.82)
                )
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.50, green: 0.38, blue: 0.25),
                        Color(red: 0.38, green: 0.28, blue: 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Branch texture
            ForEach(0..<8, id: \.self) { i in
                let x = w * (0.25 + CGFloat(i) * 0.055)
                Path { p in
                    p.move(to: CGPoint(x: x, y: h * 0.81))
                    p.addLine(to: CGPoint(x: x + w * 0.02, y: h * 0.87))
                }
                .stroke(brownDark.opacity(0.3), lineWidth: 1)
            }

            // Legs
            Path { p in
                // Left leg
                p.move(to: CGPoint(x: w * 0.42, y: h * 0.74))
                p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.82))
                // Right leg
                p.move(to: CGPoint(x: w * 0.50, y: h * 0.74))
                p.addLine(to: CGPoint(x: w * 0.52, y: h * 0.82))
            }
            .stroke(brownDark, lineWidth: 2.5)

            // Feet/claws
            Path { p in
                // Left foot
                p.move(to: CGPoint(x: w * 0.36, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.82))
                p.move(to: CGPoint(x: w * 0.38, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.85))
                p.move(to: CGPoint(x: w * 0.42, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.85))

                // Right foot
                p.move(to: CGPoint(x: w * 0.48, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.82))
                p.move(to: CGPoint(x: w * 0.50, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.85))
                p.move(to: CGPoint(x: w * 0.54, y: h * 0.82))
                p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.85))
            }
            .stroke(brownDark, lineWidth: 2)
        }
    }
}

struct BirdBodyShape: View {
    let w: CGFloat
    let h: CGFloat
    let coralMain = Color(red: 0.88, green: 0.48, blue: 0.42)
    let coralDark = Color(red: 0.72, green: 0.32, blue: 0.28)
    let coralLight = Color(red: 0.95, green: 0.62, blue: 0.55)

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: w * 0.35, y: h * 0.35))
            path.addCurve(
                to: CGPoint(x: w * 0.75, y: h * 0.45),
                control1: CGPoint(x: w * 0.50, y: h * 0.28),
                control2: CGPoint(x: w * 0.65, y: h * 0.32)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.80, y: h * 0.72),
                control1: CGPoint(x: w * 0.82, y: h * 0.52),
                control2: CGPoint(x: w * 0.84, y: h * 0.62)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.45, y: h * 0.82),
                control1: CGPoint(x: w * 0.72, y: h * 0.80),
                control2: CGPoint(x: w * 0.58, y: h * 0.84)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.30, y: h * 0.55),
                control1: CGPoint(x: w * 0.35, y: h * 0.78),
                control2: CGPoint(x: w * 0.28, y: h * 0.68)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.35, y: h * 0.35),
                control1: CGPoint(x: w * 0.30, y: h * 0.45),
                control2: CGPoint(x: w * 0.32, y: h * 0.38)
            )
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [coralLight, coralMain, coralDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct BirdCrestShape: View {
    let w: CGFloat
    let h: CGFloat
    let coralMain = Color(red: 0.88, green: 0.48, blue: 0.42)
    let coralDark = Color(red: 0.72, green: 0.32, blue: 0.28)
    let coralLight = Color(red: 0.95, green: 0.62, blue: 0.55)

    var body: some View {
        ZStack {
            // Head crest (prominent fan shape)
            Path { path in
                path.move(to: CGPoint(x: w * 0.38, y: h * 0.32))
                path.addCurve(
                    to: CGPoint(x: w * 0.22, y: h * 0.12),
                    control1: CGPoint(x: w * 0.32, y: h * 0.22),
                    control2: CGPoint(x: w * 0.25, y: h * 0.14)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.42, y: h * 0.08),
                    control1: CGPoint(x: w * 0.28, y: h * 0.06),
                    control2: CGPoint(x: w * 0.35, y: h * 0.05)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.52, y: h * 0.15),
                    control1: CGPoint(x: w * 0.48, y: h * 0.08),
                    control2: CGPoint(x: w * 0.52, y: h * 0.10)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.45, y: h * 0.30),
                    control1: CGPoint(x: w * 0.52, y: h * 0.22),
                    control2: CGPoint(x: w * 0.50, y: h * 0.28)
                )
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [coralLight, coralMain],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Crest detail lines
            CrestLines(w: w, h: h)
        }
    }
}

struct CrestLines: View {
    let w: CGFloat
    let h: CGFloat
    let coralDark = Color(red: 0.72, green: 0.32, blue: 0.28)

    var body: some View {
        ForEach(0..<8, id: \.self) { i in
            let startAngle = -0.4 + Double(i) * 0.1
            let cosVal = Darwin.cos(startAngle)
            let sinVal = Darwin.sin(startAngle)
            Path { path in
                path.move(to: CGPoint(x: w * 0.38, y: h * 0.25))
                path.addLine(to: CGPoint(
                    x: w * (0.32 + cosVal * 0.15),
                    y: h * (0.15 + sinVal * 0.12)
                ))
            }
            .stroke(coralDark.opacity(0.4), lineWidth: 1)
        }
    }
}

struct BirdHeadDetails: View {
    let w: CGFloat
    let h: CGFloat
    let coralMain = Color(red: 0.88, green: 0.48, blue: 0.42)
    let coralLight = Color(red: 0.95, green: 0.62, blue: 0.55)
    let brownDark = Color(red: 0.35, green: 0.22, blue: 0.15)
    let cream = Color(red: 0.98, green: 0.95, blue: 0.88)

    var body: some View {
        ZStack {
            // Head
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [coralLight, coralMain],
                        center: .center,
                        startRadius: 0,
                        endRadius: w * 0.1
                    )
                )
                .frame(width: w * 0.16, height: w * 0.14)
                .position(x: w * 0.38, y: h * 0.32)

            // Eye ring
            Circle()
                .stroke(cream, lineWidth: 2)
                .frame(width: w * 0.045, height: w * 0.045)
                .position(x: w * 0.40, y: h * 0.30)

            // Eye
            Circle()
                .fill(brownDark)
                .frame(width: w * 0.03, height: w * 0.03)
                .position(x: w * 0.40, y: h * 0.30)

            // Eye highlight
            Circle()
                .fill(Color.white)
                .frame(width: w * 0.01, height: w * 0.01)
                .position(x: w * 0.405, y: h * 0.295)

            // Beak
            Path { path in
                path.move(to: CGPoint(x: w * 0.32, y: h * 0.33))
                path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.36))
                path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.38))
                path.closeSubpath()
            }
            .fill(brownDark)
        }
    }
}

struct BirdWingShape: View {
    let w: CGFloat
    let h: CGFloat
    var flapOffset: CGFloat = 0
    var flapRotation: Double = 0
    let coralDark = Color(red: 0.72, green: 0.32, blue: 0.28)
    let coralLight = Color(red: 0.95, green: 0.62, blue: 0.55)
    let brownDark = Color(red: 0.35, green: 0.22, blue: 0.15)
    let cream = Color(red: 0.98, green: 0.95, blue: 0.88)

    var body: some View {
        ZStack {
            // Animated wing group
            Group {
                // Wing with feather details
                Path { path in
                    path.move(to: CGPoint(x: w * 0.42, y: h * 0.40))
                    path.addCurve(
                        to: CGPoint(x: w * 0.78, y: h * 0.50),
                        control1: CGPoint(x: w * 0.55, y: h * 0.35),
                        control2: CGPoint(x: w * 0.70, y: h * 0.40)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.72, y: h * 0.70),
                        control1: CGPoint(x: w * 0.82, y: h * 0.58),
                        control2: CGPoint(x: w * 0.80, y: h * 0.65)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.42, y: h * 0.60),
                        control1: CGPoint(x: w * 0.60, y: h * 0.72),
                        control2: CGPoint(x: w * 0.48, y: h * 0.68)
                    )
                    path.closeSubpath()
                }
                .fill(coralDark)

                // Wing feather stripes
                WingStripes(w: w, h: h)
            }
            .rotationEffect(.degrees(flapRotation), anchor: UnitPoint(x: 0.42, y: 0.50))
            .offset(y: flapOffset)

            // Belly area (lighter) - stays static
            Path { path in
                path.move(to: CGPoint(x: w * 0.35, y: h * 0.55))
                path.addCurve(
                    to: CGPoint(x: w * 0.50, y: h * 0.78),
                    control1: CGPoint(x: w * 0.32, y: h * 0.65),
                    control2: CGPoint(x: w * 0.38, y: h * 0.75)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.42, y: h * 0.60),
                    control1: CGPoint(x: w * 0.48, y: h * 0.72),
                    control2: CGPoint(x: w * 0.45, y: h * 0.65)
                )
                path.closeSubpath()
            }
            .fill(coralLight.opacity(0.6))

            // Belly stripes
            BellyStripes(w: w, h: h)
        }
    }
}

struct WingStripes: View {
    let w: CGFloat
    let h: CGFloat
    let cream = Color(red: 0.98, green: 0.95, blue: 0.88)

    var body: some View {
        ForEach(0..<6, id: \.self) { i in
            let yPos = h * (0.48 + CGFloat(i) * 0.035)
            Path { path in
                path.move(to: CGPoint(x: w * 0.45, y: yPos))
                path.addCurve(
                    to: CGPoint(x: w * 0.72, y: yPos + h * 0.02),
                    control1: CGPoint(x: w * 0.55, y: yPos - h * 0.01),
                    control2: CGPoint(x: w * 0.65, y: yPos)
                )
            }
            .stroke(cream.opacity(0.6), lineWidth: 2)
        }
    }
}

struct BellyStripes: View {
    let w: CGFloat
    let h: CGFloat
    let brownDark = Color(red: 0.35, green: 0.22, blue: 0.15)

    var body: some View {
        ForEach(0..<5, id: \.self) { i in
            let yPos = h * (0.58 + CGFloat(i) * 0.04)
            Path { path in
                path.move(to: CGPoint(x: w * 0.36, y: yPos))
                path.addQuadCurve(
                    to: CGPoint(x: w * 0.48, y: yPos + h * 0.02),
                    control: CGPoint(x: w * 0.42, y: yPos - h * 0.01)
                )
            }
            .stroke(brownDark.opacity(0.4), lineWidth: 1)
        }
    }
}

struct BirdTailAndLegs: View {
    let w: CGFloat
    let h: CGFloat
    let brownDark = Color(red: 0.35, green: 0.22, blue: 0.15)
    let cream = Color(red: 0.98, green: 0.95, blue: 0.88)

    var body: some View {
        ZStack {
            // Tail feathers
            Path { path in
                path.move(to: CGPoint(x: w * 0.55, y: h * 0.75))
                path.addCurve(
                    to: CGPoint(x: w * 0.85, y: h * 0.88),
                    control1: CGPoint(x: w * 0.68, y: h * 0.78),
                    control2: CGPoint(x: w * 0.78, y: h * 0.85)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.50, y: h * 0.80),
                    control1: CGPoint(x: w * 0.75, y: h * 0.92),
                    control2: CGPoint(x: w * 0.60, y: h * 0.88)
                )
                path.closeSubpath()
            }
            .fill(brownDark.opacity(0.85))

            // Tail stripes
            TailStripes(w: w, h: h)

            // Legs
            Path { path in
                path.move(to: CGPoint(x: w * 0.42, y: h * 0.78))
                path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.90))
                path.move(to: CGPoint(x: w * 0.48, y: h * 0.78))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.90))
            }
            .stroke(brownDark, lineWidth: 2.5)

            // Feet/claws
            Path { path in
                path.move(to: CGPoint(x: w * 0.36, y: h * 0.90))
                path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.90))
                path.move(to: CGPoint(x: w * 0.38, y: h * 0.90))
                path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.93))
                path.move(to: CGPoint(x: w * 0.42, y: h * 0.90))
                path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.93))
                path.move(to: CGPoint(x: w * 0.46, y: h * 0.90))
                path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.90))
                path.move(to: CGPoint(x: w * 0.48, y: h * 0.90))
                path.addLine(to: CGPoint(x: w * 0.46, y: h * 0.93))
                path.move(to: CGPoint(x: w * 0.52, y: h * 0.90))
                path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.93))
            }
            .stroke(brownDark, lineWidth: 2)
        }
    }
}

struct TailStripes: View {
    let w: CGFloat
    let h: CGFloat
    let cream = Color(red: 0.98, green: 0.95, blue: 0.88)

    var body: some View {
        ForEach(0..<4, id: \.self) { i in
            let xStart = w * (0.55 + CGFloat(i) * 0.07)
            Path { path in
                path.move(to: CGPoint(x: xStart, y: h * 0.76))
                path.addLine(to: CGPoint(x: xStart + w * 0.12, y: h * 0.85))
            }
            .stroke(cream.opacity(0.5), lineWidth: 1.5)
        }
    }
}

struct FeatherScale: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.midY)
        )
        return path
    }
}

// MARK: - Branch

struct BranchView: View {
    let brownDark = Color(red: 0.35, green: 0.25, blue: 0.15)
    let brownLight = Color(red: 0.50, green: 0.38, blue: 0.25)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Main branch
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.5))
                    path.addCurve(
                        to: CGPoint(x: w, y: h * 0.4),
                        control1: CGPoint(x: w * 0.3, y: h * 0.6),
                        control2: CGPoint(x: w * 0.7, y: h * 0.3)
                    )
                    path.addLine(to: CGPoint(x: w, y: h * 0.6))
                    path.addCurve(
                        to: CGPoint(x: 0, y: h * 0.7),
                        control1: CGPoint(x: w * 0.7, y: h * 0.5),
                        control2: CGPoint(x: w * 0.3, y: h * 0.8)
                    )
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [brownLight, brownDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Branch texture lines
                ForEach(0..<8, id: \.self) { i in
                    Path { path in
                        let x = w * (0.1 + Double(i) * 0.11)
                        path.move(to: CGPoint(x: x, y: h * 0.45))
                        path.addLine(to: CGPoint(x: x + w * 0.05, y: h * 0.65))
                    }
                    .stroke(brownDark.opacity(0.5), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - Orange Butterfly

struct OrangeButterfly: View {
    let orange = Color(red: 0.90, green: 0.45, blue: 0.20)
    let orangeDark = Color(red: 0.75, green: 0.30, blue: 0.15)
    let brown = Color(red: 0.35, green: 0.20, blue: 0.10)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Upper wings
                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    path.addCurve(
                        to: CGPoint(x: w * 0.05, y: h * 0.25),
                        control1: CGPoint(x: w * 0.25, y: h * 0.35),
                        control2: CGPoint(x: w * 0.10, y: h * 0.15)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.5),
                        control1: CGPoint(x: w * 0.0, y: h * 0.45),
                        control2: CGPoint(x: w * 0.20, y: h * 0.55)
                    )
                }
                .fill(orange)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    path.addCurve(
                        to: CGPoint(x: w * 0.95, y: h * 0.25),
                        control1: CGPoint(x: w * 0.75, y: h * 0.35),
                        control2: CGPoint(x: w * 0.90, y: h * 0.15)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.5),
                        control1: CGPoint(x: w * 1.0, y: h * 0.45),
                        control2: CGPoint(x: w * 0.80, y: h * 0.55)
                    )
                }
                .fill(orange)

                // Lower wings
                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    path.addCurve(
                        to: CGPoint(x: w * 0.15, y: h * 0.85),
                        control1: CGPoint(x: w * 0.30, y: h * 0.60),
                        control2: CGPoint(x: w * 0.15, y: h * 0.75)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.5),
                        control1: CGPoint(x: w * 0.20, y: h * 0.90),
                        control2: CGPoint(x: w * 0.40, y: h * 0.65)
                    )
                }
                .fill(orangeDark)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                    path.addCurve(
                        to: CGPoint(x: w * 0.85, y: h * 0.85),
                        control1: CGPoint(x: w * 0.70, y: h * 0.60),
                        control2: CGPoint(x: w * 0.85, y: h * 0.75)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.5),
                        control1: CGPoint(x: w * 0.80, y: h * 0.90),
                        control2: CGPoint(x: w * 0.60, y: h * 0.65)
                    )
                }
                .fill(orangeDark)

                // Body
                Ellipse()
                    .fill(brown)
                    .frame(width: w * 0.08, height: h * 0.4)
                    .position(x: w * 0.5, y: h * 0.5)

                // Antennae
                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.32))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.35, y: h * 0.10),
                        control: CGPoint(x: w * 0.40, y: h * 0.20)
                    )
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.32))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.65, y: h * 0.10),
                        control: CGPoint(x: w * 0.60, y: h * 0.20)
                    )
                }
                .stroke(brown, lineWidth: 1)
            }
        }
    }
}

// MARK: - Yellow/Green Butterfly

struct YellowGreenButterfly: View {
    let yellowGreen = Color(red: 0.70, green: 0.75, blue: 0.30)
    let green = Color(red: 0.50, green: 0.60, blue: 0.25)
    let brown = Color(red: 0.35, green: 0.25, blue: 0.15)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Wings
                Ellipse()
                    .fill(yellowGreen)
                    .frame(width: w * 0.45, height: h * 0.6)
                    .position(x: w * 0.28, y: h * 0.4)

                Ellipse()
                    .fill(yellowGreen)
                    .frame(width: w * 0.45, height: h * 0.6)
                    .position(x: w * 0.72, y: h * 0.4)

                Ellipse()
                    .fill(green)
                    .frame(width: w * 0.35, height: h * 0.45)
                    .position(x: w * 0.30, y: h * 0.7)

                Ellipse()
                    .fill(green)
                    .frame(width: w * 0.35, height: h * 0.45)
                    .position(x: w * 0.70, y: h * 0.7)

                // Body
                Ellipse()
                    .fill(brown)
                    .frame(width: w * 0.1, height: h * 0.45)
                    .position(x: w * 0.5, y: h * 0.5)

                // Antennae
                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.08))
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.08))
                }
                .stroke(brown, lineWidth: 1)
            }
        }
    }
}

// MARK: - White Butterfly

struct WhiteButterfly: View {
    let white = Color.white
    let cream = Color(red: 0.98, green: 0.96, blue: 0.90)
    let grayLight = Color(red: 0.85, green: 0.85, blue: 0.82)
    let brown = Color(red: 0.45, green: 0.35, blue: 0.25)

    @ViewBuilder
    private func upperWings(w: CGFloat, h: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [white, cream],
                    center: .center,
                    startRadius: 0,
                    endRadius: w * 0.25
                )
            )
            .frame(width: w * 0.5, height: h * 0.55)
            .position(x: w * 0.25, y: h * 0.35)

        Ellipse()
            .fill(
                RadialGradient(
                    colors: [white, cream],
                    center: .center,
                    startRadius: 0,
                    endRadius: w * 0.25
                )
            )
            .frame(width: w * 0.5, height: h * 0.55)
            .position(x: w * 0.75, y: h * 0.35)
    }

    @ViewBuilder
    private func lowerWings(w: CGFloat, h: CGFloat) -> some View {
        Ellipse()
            .fill(grayLight)
            .frame(width: w * 0.4, height: h * 0.45)
            .position(x: w * 0.28, y: h * 0.72)

        Ellipse()
            .fill(grayLight)
            .frame(width: w * 0.4, height: h * 0.45)
            .position(x: w * 0.72, y: h * 0.72)
    }

    @ViewBuilder
    private func wingVeins(w: CGFloat, h: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { i in
            Path { path in
                path.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
                let angle: Double = Double(i - 1) * 0.4 - 0.8
                let xPos: CGFloat = w * CGFloat(0.5 + cos(angle) * 0.35)
                let yPos: CGFloat = h * CGFloat(0.5 + sin(angle) * 0.35)
                path.addLine(to: CGPoint(x: xPos, y: yPos))
            }
            .stroke(grayLight, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func bodyAndAntennae(w: CGFloat, h: CGFloat) -> some View {
        Ellipse()
            .fill(brown)
            .frame(width: w * 0.08, height: h * 0.35)
            .position(x: w * 0.5, y: h * 0.5)

        Path { path in
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.35))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.35, y: h * 0.12),
                control: CGPoint(x: w * 0.42, y: h * 0.22)
            )
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.35))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.65, y: h * 0.12),
                control: CGPoint(x: w * 0.58, y: h * 0.22)
            )
        }
        .stroke(brown, lineWidth: 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                upperWings(w: w, h: h)
                lowerWings(w: w, h: h)
                wingVeins(w: w, h: h)
                bodyAndAntennae(w: w, h: h)
            }
        }
    }
}

// MARK: - Coat of Arms

struct CoatOfArms: View {
    let brown = Color(red: 0.50, green: 0.35, blue: 0.20)
    let gold = Color(red: 0.85, green: 0.70, blue: 0.30)
    let green = Color(red: 0.30, green: 0.50, blue: 0.30)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Shield shape
                Path { path in
                    path.move(to: CGPoint(x: w * 0.1, y: h * 0.15))
                    path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.15))
                    path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.55))
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.90),
                        control1: CGPoint(x: w * 0.9, y: h * 0.75),
                        control2: CGPoint(x: w * 0.75, y: h * 0.88)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.1, y: h * 0.55),
                        control1: CGPoint(x: w * 0.25, y: h * 0.88),
                        control2: CGPoint(x: w * 0.1, y: h * 0.75)
                    )
                    path.closeSubpath()
                }
                .fill(gold.opacity(0.3))
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.1, y: h * 0.15))
                        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.15))
                        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.55))
                        path.addCurve(
                            to: CGPoint(x: w * 0.5, y: h * 0.90),
                            control1: CGPoint(x: w * 0.9, y: h * 0.75),
                            control2: CGPoint(x: w * 0.75, y: h * 0.88)
                        )
                        path.addCurve(
                            to: CGPoint(x: w * 0.1, y: h * 0.55),
                            control1: CGPoint(x: w * 0.25, y: h * 0.88),
                            control2: CGPoint(x: w * 0.1, y: h * 0.75)
                        )
                        path.closeSubpath()
                    }
                    .stroke(brown, lineWidth: 1.5)
                )

                // Diamond in center
                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.25))
                    path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.50))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.75))
                    path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.50))
                    path.closeSubpath()
                }
                .stroke(brown, lineWidth: 1)

                // Star at top
                Path { path in
                    let cx = w * 0.5
                    let cy = h * 0.08
                    let r: CGFloat = w * 0.08
                    for i in 0..<5 {
                        let angle = Double(i) * 4 * .pi / 5 - .pi / 2
                        let x = cx + r * cos(angle)
                        let y = cy + r * sin(angle)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.closeSubpath()
                }
                .fill(gold)

                // Palm fronds on sides
                Path { path in
                    path.move(to: CGPoint(x: w * 0.05, y: h * 0.95))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.30, y: h * 0.10),
                        control: CGPoint(x: w * -0.05, y: h * 0.50)
                    )
                }
                .stroke(green, lineWidth: 1.5)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.95, y: h * 0.95))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.70, y: h * 0.10),
                        control: CGPoint(x: w * 1.05, y: h * 0.50)
                    )
                }
                .stroke(green, lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Signature Scribble

struct SignatureScribble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.1, y: h * 0.7))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.3, y: h * 0.3),
            control: CGPoint(x: w * 0.15, y: h * 0.4)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.6),
            control: CGPoint(x: w * 0.4, y: h * 0.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.7, y: h * 0.4),
            control: CGPoint(x: w * 0.6, y: h * 0.8)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.9, y: h * 0.5),
            control: CGPoint(x: w * 0.8, y: h * 0.3)
        )

        return path
    }
}

// MARK: - Greek 200 Drachma Banknote (note1)

struct GreekDrachmaContent: View {
    // Color definitions matching the banknote
    let orangeDark = Color(red: 0.85, green: 0.45, blue: 0.15)
    let orangeMedium = Color(red: 0.95, green: 0.55, blue: 0.20)
    let orangeLight = Color(red: 0.98, green: 0.70, blue: 0.35)
    let orangePale = Color(red: 0.99, green: 0.85, blue: 0.70)
    let yellowGold = Color(red: 0.95, green: 0.75, blue: 0.25)
    let tealDark = Color(red: 0.20, green: 0.55, blue: 0.55)
    let tealMedium = Color(red: 0.35, green: 0.65, blue: 0.60)
    let tealLight = Color(red: 0.50, green: 0.75, blue: 0.70)
    let cream = Color(red: 0.98, green: 0.95, blue: 0.88)
    let tan = Color(red: 0.75, green: 0.60, blue: 0.45)
    let brown = Color(red: 0.55, green: 0.40, blue: 0.25)
    let skyBlue = Color(red: 0.70, green: 0.85, blue: 0.95)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Base cream/white background
                cream

                // Left section - Church scene with gradient sky
                HStack(spacing: 0) {
                    // Church area (left 45%)
                    ZStack {
                        // Sky gradient
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.80, blue: 0.50),
                                Color(red: 0.98, green: 0.70, blue: 0.40),
                                Color(red: 0.70, green: 0.85, blue: 0.90)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        // Church illustration
                        ChurchView()
                            .frame(width: w * 0.40, height: h * 0.75)
                            .offset(x: -w * 0.02, y: h * 0.05)

                        // Ground
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [tan, Color(red: 0.65, green: 0.50, blue: 0.35)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: h * 0.22)
                        }

                        // ΚΥΚΛΑΔΕΣ label
                        VStack {
                            Spacer()
                            HStack {
                                Text("ΚΥΚΛΑΔΕΣ")
                                    .font(.system(size: h * 0.025, weight: .medium))
                                    .foregroundColor(.black.opacity(0.7))
                                    .offset(x: w * 0.02)
                                Spacer()
                            }
                            .padding(.bottom, h * 0.19)
                        }
                    }
                    .frame(width: w * 0.45)

                    Spacer()
                }

                // Center-right geometric patterns
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: w * 0.30)

                    GeometricPatternView()
                        .frame(width: w * 0.70, height: h)
                }

                // Bell tower silhouette overlay
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: w * 0.35)

                    BellTowerSilhouette()
                        .fill(orangeMedium.opacity(0.6))
                        .frame(width: w * 0.25, height: h * 0.85)

                    Spacer()
                }

                // "200" top left
                VStack {
                    HStack {
                        Text("200")
                            .font(.system(size: h * 0.12, weight: .bold, design: .serif))
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.leading, w * 0.02)
                            .padding(.top, h * 0.02)
                        Spacer()
                    }
                    Spacer()
                }

                // "200" bottom left
                VStack {
                    Spacer()
                    HStack {
                        Text("200")
                            .font(.system(size: h * 0.10, weight: .bold, design: .serif))
                            .foregroundColor(.black.opacity(0.7))
                            .padding(.leading, w * 0.02)
                            .padding(.bottom, h * 0.02)
                        Spacer()
                    }
                }

                // Left vertical text "ΤΡΑΠΕΖΑ ΤΗΣ ΕΛΛΑΔΟΣ"
                HStack {
                    VerticalText(text: "ΤΡΑΠΕΖΑ ΤΗΣ ΕΛΛΑΔΟΣ")
                        .font(.system(size: h * 0.035, weight: .medium))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(width: h * 0.5)
                        .rotationEffect(.degrees(-90))
                        .offset(x: -w * 0.44)
                    Spacer()
                }

                // Right side elements
                // "ΔΙΑΚΟΣΙΕΣ ΔΡΑΧΜΕΣ" text
                HStack {
                    Spacer()
                    VStack {
                        Text("ΔΙΑΚΟΣΙΕΣ")
                            .font(.system(size: h * 0.055, weight: .semibold))
                            .foregroundColor(.black.opacity(0.85))
                        Text("ΔΡΑΧΜΕΣ")
                            .font(.system(size: h * 0.055, weight: .semibold))
                            .foregroundColor(.black.opacity(0.85))
                    }
                    .offset(x: -w * 0.15, y: -h * 0.25)
                }

                // Large "200" on right
                HStack {
                    Spacer()
                    Text("200")
                        .font(.system(size: h * 0.22, weight: .bold, design: .serif))
                        .foregroundColor(orangeDark.opacity(0.9))
                        .offset(x: -w * 0.08, y: h * 0.12)
                }

                // Right vertical text "ΤΡΑΠΕΖΑ ΤΗΣ ΕΛΛΑΔΟΣ"
                HStack {
                    Spacer()
                    VerticalText(text: "ΤΡΑΠΕΖΑ ΤΗΣ ΕΛΛΑΔΟΣ")
                        .font(.system(size: h * 0.035, weight: .medium))
                        .foregroundColor(orangeDark)
                        .frame(width: h * 0.5)
                        .rotationEffect(.degrees(90))
                        .offset(x: w * 0.44)
                }

                // Serial number
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("2010482590 AB")
                            .font(.system(size: h * 0.035, weight: .medium, design: .monospaced))
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.trailing, w * 0.08)
                            .padding(.bottom, h * 0.03)
                    }
                }

                // Atom symbol on right
                HStack {
                    Spacer()
                    AtomSymbol()
                        .stroke(orangeDark, lineWidth: 1.5)
                        .frame(width: h * 0.18, height: h * 0.18)
                        .offset(x: -w * 0.03, y: h * 0.25)
                }

                // Orange border
                Rectangle()
                    .strokeBorder(orangeMedium, lineWidth: w * 0.008)

                // Inner decorative border
                Rectangle()
                    .strokeBorder(orangeLight.opacity(0.5), lineWidth: w * 0.003)
                    .padding(w * 0.012)
            }
        }
    }
}

struct VerticalText: View {
    let text: String

    var body: some View {
        Text(text)
            .fixedSize()
    }
}

struct ChurchView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Main church building - white dome structure
                // Church base
                Path { path in
                    path.move(to: CGPoint(x: w * 0.15, y: h * 0.85))
                    path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.85))
                    path.closeSubpath()
                }
                .fill(Color.white)

                // Church dome
                Path { path in
                    path.move(to: CGPoint(x: w * 0.15, y: h * 0.45))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.55, y: h * 0.45),
                        control: CGPoint(x: w * 0.35, y: h * 0.15)
                    )
                }
                .fill(Color.white)

                // Dome cross
                Path { path in
                    path.move(to: CGPoint(x: w * 0.35, y: h * 0.12))
                    path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.20))
                    path.move(to: CGPoint(x: w * 0.32, y: h * 0.15))
                    path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.15))
                }
                .stroke(Color.black.opacity(0.6), lineWidth: 2)

                // Door
                Path { path in
                    path.addRoundedRect(
                        in: CGRect(x: w * 0.30, y: h * 0.60, width: w * 0.10, height: w * 0.18),
                        cornerSize: CGSize(width: w * 0.05, height: w * 0.05)
                    )
                }
                .fill(Color(red: 0.4, green: 0.25, blue: 0.15))

                // Windows
                Circle()
                    .fill(Color(red: 0.3, green: 0.4, blue: 0.5).opacity(0.6))
                    .frame(width: w * 0.06, height: w * 0.06)
                    .position(x: w * 0.35, y: h * 0.38)

                // Bell tower (right side)
                Path { path in
                    // Tower base
                    path.move(to: CGPoint(x: w * 0.60, y: h * 0.85))
                    path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.35))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.35))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.85))
                    path.closeSubpath()
                }
                .fill(Color.white)

                // Bell tower top/arches
                Path { path in
                    path.move(to: CGPoint(x: w * 0.60, y: h * 0.35))
                    path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.20))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.35))
                    path.closeSubpath()
                }
                .fill(Color.white)

                // Tower cross
                Path { path in
                    path.move(to: CGPoint(x: w * 0.70, y: h * 0.10))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.20))
                    path.move(to: CGPoint(x: w * 0.66, y: h * 0.14))
                    path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.14))
                }
                .stroke(Color.black.opacity(0.6), lineWidth: 2)

                // Bell openings
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.3, green: 0.35, blue: 0.4).opacity(0.5))
                        .frame(width: w * 0.04, height: h * 0.08)
                        .position(x: w * (0.64 + Double(i) * 0.06), y: h * 0.42)
                }

                // Church shadow/outline
                Path { path in
                    // Main building outline
                    path.move(to: CGPoint(x: w * 0.15, y: h * 0.85))
                    path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.45))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.55, y: h * 0.45),
                        control: CGPoint(x: w * 0.35, y: h * 0.15)
                    )
                    path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.85))
                }
                .stroke(Color.black.opacity(0.3), lineWidth: 1)

                // Tower outline
                Path { path in
                    path.move(to: CGPoint(x: w * 0.60, y: h * 0.85))
                    path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.20))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.85))
                }
                .stroke(Color.black.opacity(0.3), lineWidth: 1)
            }
        }
    }
}

struct GeometricPatternView: View {
    let orangeDark = Color(red: 0.85, green: 0.45, blue: 0.15)
    let orangeMedium = Color(red: 0.95, green: 0.55, blue: 0.20)
    let orangeLight = Color(red: 0.98, green: 0.70, blue: 0.35)
    let orangePale = Color(red: 0.99, green: 0.85, blue: 0.70)
    let tealDark = Color(red: 0.20, green: 0.55, blue: 0.55)
    let tealMedium = Color(red: 0.35, green: 0.65, blue: 0.60)
    let yellowGold = Color(red: 0.95, green: 0.78, blue: 0.25)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Vertical stripes
                HStack(spacing: 0) {
                    Rectangle().fill(orangePale).frame(width: w * 0.08)
                    Rectangle().fill(tealMedium.opacity(0.7)).frame(width: w * 0.06)
                    Rectangle().fill(orangeLight).frame(width: w * 0.08)
                    Rectangle().fill(tealDark.opacity(0.6)).frame(width: w * 0.05)
                    Rectangle().fill(yellowGold.opacity(0.8)).frame(width: w * 0.07)
                    Rectangle().fill(orangeMedium).frame(width: w * 0.10)
                    Rectangle().fill(tealMedium.opacity(0.5)).frame(width: w * 0.06)
                    Rectangle().fill(orangeLight).frame(width: w * 0.12)
                    Rectangle().fill(orangePale).frame(width: w * 0.15)
                    Rectangle().fill(orangeLight.opacity(0.5)).frame(width: w * 0.23)
                }

                // Curved overlay patterns
                CurvedPatterns()
                    .opacity(0.6)

                // Diamond/geometric grid pattern
                DiamondPattern()
                    .stroke(orangeDark.opacity(0.4), lineWidth: 1)
                    .offset(y: h * 0.15)
            }
        }
    }
}

struct CurvedPatterns: View {
    let orangeMedium = Color(red: 0.95, green: 0.55, blue: 0.20)
    let tealMedium = Color(red: 0.35, green: 0.65, blue: 0.60)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Large arc from bottom left
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.9))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.7, y: 0),
                        control: CGPoint(x: w * 0.2, y: h * 0.3)
                    )
                    path.addLine(to: CGPoint(x: w * 0.6, y: 0))
                    path.addQuadCurve(
                        to: CGPoint(x: 0, y: h * 0.8),
                        control: CGPoint(x: w * 0.15, y: h * 0.3)
                    )
                    path.closeSubpath()
                }
                .fill(orangeMedium.opacity(0.4))

                // Teal curved band
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.6))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.5, y: h),
                        control: CGPoint(x: w * 0.3, y: h * 0.5)
                    )
                    path.addLine(to: CGPoint(x: w * 0.4, y: h))
                    path.addQuadCurve(
                        to: CGPoint(x: 0, y: h * 0.7),
                        control: CGPoint(x: w * 0.25, y: h * 0.6)
                    )
                    path.closeSubpath()
                }
                .fill(tealMedium.opacity(0.5))
            }
        }
    }
}

struct DiamondPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 25
        let rows = Int(rect.height / spacing) + 1
        let cols = Int(rect.width / spacing) + 1

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * spacing
                let y = CGFloat(row) * spacing
                let offset: CGFloat = row % 2 == 0 ? 0 : spacing / 2

                // Diamond shape
                let size: CGFloat = 8
                path.move(to: CGPoint(x: x + offset, y: y - size))
                path.addLine(to: CGPoint(x: x + offset + size, y: y))
                path.addLine(to: CGPoint(x: x + offset, y: y + size))
                path.addLine(to: CGPoint(x: x + offset - size, y: y))
                path.closeSubpath()
            }
        }

        return path
    }
}

struct BellTowerSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Bell tower shape
        path.move(to: CGPoint(x: w * 0.3, y: h))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.7, y: h))
        path.closeSubpath()

        // Cross on top
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.02))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.08))
        path.move(to: CGPoint(x: w * 0.45, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.05))

        return path
    }
}

struct AtomSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.9

        // Three elliptical orbits
        for i in 0..<3 {
            let angle = Double(i) * .pi / 3
            let ellipsePath = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius * 0.3,
                width: radius * 2,
                height: radius * 0.6
            ))

            var transform = CGAffineTransform(translationX: -center.x, y: -center.y)
            transform = transform.concatenating(CGAffineTransform(rotationAngle: angle))
            transform = transform.concatenating(CGAffineTransform(translationX: center.x, y: center.y))

            path.addPath(ellipsePath.applying(transform))
        }

        // Center dot
        path.addEllipse(in: CGRect(
            x: center.x - 4,
            y: center.y - 4,
            width: 8,
            height: 8
        ))

        return path
    }
}

#Preview {
    BanknoteView()
        .previewInterfaceOrientation(.landscapeLeft)
}
