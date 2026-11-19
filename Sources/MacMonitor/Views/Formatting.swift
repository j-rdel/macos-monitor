import Foundation
import SwiftUI

enum Fmt {
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func temperature(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb.formatted(.number.precision(.fractionLength(1))) + " GB"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowsNonnumericFormatting = false
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func rate(_ bytesPerSecond: Double) -> String {
        byteFormatter.string(fromByteCount: Int64(max(bytesPerSecond, 0))) + "/s"
    }

    static func storage(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)min" }
        return "\(mins)min"
    }

    static func minutes(_ total: Int) -> String {
        total >= 60 ? "\(total / 60)h\(String(format: "%02d", total % 60))" : "\(total) min"
    }
}

extension Color {
    /// Cor de destaque discreta: segue a cor do sistema e só muda quando há algo a notar.
    static func level(_ value: Double, warn: Double = 0.75, critical: Double = 0.9) -> Color {
        if value >= critical { return .red }
        if value >= warn { return .orange }
        return .accentColor
    }

    static func temperature(_ value: Double) -> Color {
        if value >= 90 { return .red }
        if value >= 75 { return .orange }
        return .primary
    }
}
