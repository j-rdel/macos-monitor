import SwiftUI

/// Título de seção no estilo dos painéis do sistema ("Energy Mode", "Using Significant Energy").
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }
}

struct PanelDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// Barra horizontal fina com cantos arredondados.
struct UsageBar: View {
    var value: Double
    var tint: Color = .accentColor

    var body: some View {
        SegmentedBar(segments: [(value, tint)])
    }
}

struct SegmentedBar: View {
    var segments: [(value: Double, color: Color)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let width = geo.size.width * min(max(segment.value, 0), 1)
                    if width >= 1 {
                        Rectangle().fill(segment.color).frame(width: width)
                    }
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.1))
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.35), value: segments.map(\.value))
        }
        .frame(height: 6)
    }
}

/// Valor grande + legenda, usado em grades de 2–3 colunas.
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

/// Gráfico de linha com preenchimento suave, para o histórico de CPU.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            SparklineShape(values: values, closed: true)
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
            SparklineShape(values: values, closed: false)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SparklineShape: Shape {
    let values: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        let inset: CGFloat = 2
        func point(_ i: Int) -> CGPoint {
            let v = CGFloat(min(max(values[i], 0), 1))
            return CGPoint(x: CGFloat(i) * step, y: rect.maxY - inset - v * (rect.height - inset * 2))
        }
        path.move(to: point(0))
        for i in 1..<values.count { path.addLine(to: point(i)) }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// Linha clicável com destaque ao passar o mouse, como os itens de menu do sistema.
struct MenuRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.1) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 5)
    }
}
