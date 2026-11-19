// Gera o ícone do app: swift Resources/Icon/IconGenerator.swift <saída.png>
// Conceito: um chip de silício "vivo" — o traço de um batimento cardíaco atravessa o chip,
// indo do frio (ciano) ao quente (laranja), como as leituras de uso e temperatura.
import AppKit
import SwiftUI

struct Squircle: InsettableShape {
    var inset: CGFloat = 0
    func inset(by amount: CGFloat) -> Squircle { Squircle(inset: inset + amount) }
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return Path(roundedRect: r, cornerRadius: rect.width * 0.225, style: .continuous)
    }
}

struct _Unused: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.width * 0.225, style: .continuous)
    }
}

struct Pulse: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (0.00, 0.55), (0.30, 0.55), (0.37, 0.42), (0.44, 0.70),
            (0.53, 0.18), (0.62, 0.82), (0.69, 0.48), (0.75, 0.55), (1.00, 0.55),
        ]
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + pts[0].0 * rect.width, y: rect.minY + pts[0].1 * rect.height))
        for (x, y) in pts.dropFirst() {
            p.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height))
        }
        return p
    }
}

struct Pins: Shape {
    let count: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pinLength = rect.width * 0.075
        let pinWidth = rect.width * 0.032
        let inner = rect.insetBy(dx: pinLength, dy: pinLength)
        for i in 0..<count {
            let t = (CGFloat(i) + 0.5) / CGFloat(count)
            let x = inner.minX + inner.width * (0.12 + 0.76 * t)
            let y = inner.minY + inner.height * (0.12 + 0.76 * t)
            p.addRoundedRect(in: CGRect(x: x - pinWidth / 2, y: rect.minY, width: pinWidth, height: pinLength + 4), cornerSize: CGSize(width: pinWidth / 2, height: pinWidth / 2))
            p.addRoundedRect(in: CGRect(x: x - pinWidth / 2, y: rect.maxY - pinLength - 4, width: pinWidth, height: pinLength + 4), cornerSize: CGSize(width: pinWidth / 2, height: pinWidth / 2))
            p.addRoundedRect(in: CGRect(x: rect.minX, y: y - pinWidth / 2, width: pinLength + 4, height: pinWidth), cornerSize: CGSize(width: pinWidth / 2, height: pinWidth / 2))
            p.addRoundedRect(in: CGRect(x: rect.maxX - pinLength - 4, y: y - pinWidth / 2, width: pinLength + 4, height: pinWidth), cornerSize: CGSize(width: pinWidth / 2, height: pinWidth / 2))
        }
        return p
    }
}

struct AppIcon: View {
    let heat = LinearGradient(
        colors: [Color(red: 0.25, green: 0.90, blue: 1.00),
                 Color(red: 0.35, green: 1.00, blue: 0.60),
                 Color(red: 1.00, green: 0.80, blue: 0.25),
                 Color(red: 1.00, green: 0.42, blue: 0.30)],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack {
            // Fundo: azul-noite com brilho no topo
            Squircle()
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.48),
                                              Color(red: 0.05, green: 0.06, blue: 0.17)],
                                     startPoint: .top, endPoint: .bottom))
            Squircle()
                .fill(RadialGradient(colors: [Color(red: 0.45, green: 0.55, blue: 1).opacity(0.45), .clear],
                                     center: UnitPoint(x: 0.5, y: 0.0), startRadius: 0, endRadius: 620))

            // Grade sutil, como papel milimetrado de osciloscópio
            Canvas { ctx, size in
                let step = size.width / 14
                var grid = Path()
                for i in 1..<14 {
                    let v = CGFloat(i) * step
                    grid.move(to: CGPoint(x: v, y: 0)); grid.addLine(to: CGPoint(x: v, y: size.height))
                    grid.move(to: CGPoint(x: 0, y: v)); grid.addLine(to: CGPoint(x: size.width, y: v))
                }
                ctx.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 2)
            }
            .clipShape(Squircle())

            // Chip
            ZStack {
                Pins(count: 4).fill(Color.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 70, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.20), Color.white.opacity(0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 70, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 10)
                    )
                    .padding(44)
            }
            .frame(width: 560, height: 560)

            // Pulso atravessando o ícone, com brilho
            Pulse()
                .stroke(heat, style: StrokeStyle(lineWidth: 44, lineCap: .round, lineJoin: .round))
                .blur(radius: 36)
                .opacity(0.8)
                .frame(width: 660, height: 360)
            Pulse()
                .stroke(heat, style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
                .frame(width: 660, height: 360)
            Pulse()
                .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .frame(width: 660, height: 360)

            // Borda de vidro
            Squircle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.03)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 4)
        }
        .frame(width: 824, height: 824)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: AppIcon())
    renderer.scale = 1
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
