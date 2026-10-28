import SwiftUI

/// Live counters and round-trip statistics shown along the bottom of the window.
struct StatusBar: View {
    let stats: PingStats
    let language: Language

    var body: some View {
        let t = language.pick
        let rtt = stats.rtt

        HStack(spacing: 14) {
            item(t("发送", "Sent"), "\(stats.sent)")
            item(t("接收", "Received"), "\(stats.received)")
            item(t("丢失", "Lost"), "\(stats.lost)", highlight: stats.lost > 0)
            item(t("丢包率", "Loss"), stats.lossPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                 highlight: stats.lost > 0)

            Divider()
                .frame(height: 12)

            item(t("最小", "Min"), milliseconds(rtt?.min))
            item(t("平均", "Avg"), milliseconds(rtt?.avg))
            item(t("最大", "Max"), milliseconds(rtt?.max))
            item(t("标准差", "StdDev"), milliseconds(rtt?.stddev))

            Spacer(minLength: 0)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func item(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(highlight ? Color.red : Color.primary)
        }
        .fixedSize()
    }

    private func milliseconds(_ value: Double?) -> String {
        value.map { String(format: "%.2f ms", $0) } ?? "—"
    }
}
