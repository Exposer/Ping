import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PingViewModel()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage(Language.storageKey) private var language: Language = .systemDefault

    private let presets = ["1.1.1.1", "8.8.8.8", "apple.com", "google.com", "127.0.0.1"]

    var body: some View {
        let t = language.pick

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(t("IP 或域名", "IP or hostname"), text: $viewModel.target)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.start() }
                    .disabled(viewModel.isRunning)

                Menu(t("常用", "Presets")) {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) { viewModel.target = preset }
                    }
                }
                .fixedSize()
                .disabled(viewModel.isRunning)
            }

            HStack {
                Stepper(
                    t("次数：", "Count: ") + (viewModel.isContinuous ? "∞" : "\(viewModel.count)"),
                    value: $viewModel.count,
                    in: 1...100
                )
                .disabled(viewModel.isRunning || viewModel.isContinuous)

                Toggle(t("持续", "Continuous"), isOn: $viewModel.isContinuous)
                    .toggleStyle(.checkbox)
                    .disabled(viewModel.isRunning)

                Spacer()

                Button(t("清空", "Clear")) { viewModel.clear() }
                    .disabled(viewModel.isRunning || viewModel.lines.isEmpty)

                if viewModel.isRunning {
                    Button(t("停止", "Stop")) { viewModel.stop() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button(t("开始", "Start")) { viewModel.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(viewModel.target.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    optionField(t("包大小", "Size"), value: $viewModel.options.payloadSize,
                                in: PingOptions.payloadSizeRange, step: 8, unit: t("字节", "bytes"),
                                help: t("ICMP 数据部分的字节数，不含 8 字节 ICMP 头（同 ping -s）",
                                        "ICMP payload bytes, excluding the 8-byte ICMP header (same as ping -s)"))
                    optionField("TTL", value: $viewModel.options.ttl,
                                in: PingOptions.ttlRange, step: 1, unit: t("跳", "hops"),
                                help: t("IP 生存时间，经过这么多跳路由后丢弃",
                                        "IP time to live: the packet is dropped after this many router hops"))
                }
                GridRow {
                    optionField(t("超时", "Timeout"), value: $viewModel.options.timeout,
                                in: PingOptions.timeoutRange, step: 0.5, unit: t("秒", "s"),
                                help: t("等待单个回复的最长时间", "How long to wait for each reply"))
                    optionField(t("间隔", "Interval"), value: $viewModel.options.interval,
                                in: PingOptions.intervalRange, step: 0.5, unit: t("秒", "s"),
                                help: t("两次发送之间的间隔", "Time between sending packets"))
                    Button(t("恢复默认", "Reset")) { viewModel.options = PingOptions() }
                }
            }
            .disabled(viewModel.isRunning)

            ScrollViewReader { proxy in
                List(viewModel.lines) { line in
                    Text(line.text(language))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(color(for: line.kind))
                        .textSelection(.enabled)
                        .id(line.id)
                }
                .onChange(of: viewModel.lines.count) { _ in
                    if let last = viewModel.lines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .overlay {
                if viewModel.lines.isEmpty {
                    Text(t("输入目标后点击「开始」", "Enter a target and click Start"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(stats: viewModel.stats, language: language)
        }
        .frame(minWidth: 660, minHeight: 380)
        .toolbar {
            ToolbarItemGroup {
                Picker(t("语言", "Language"), selection: $language) {
                    ForEach(Language.allCases) { option in
                        Text(option.name)
                    }
                }
                .pickerStyle(.segmented)
                .help(t("界面语言", "Interface language"))

                Picker(t("配色", "Appearance"), selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Label(option.title(in: language), systemImage: option.symbol)
                            .help(option.title(in: language))
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
            }
        }
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { $0.apply() }
    }

    private func optionField(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>,
                             step: Int, unit: String, help: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .frame(width: 60, alignment: .leading)
            TextField(title, value: value, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
        .help(help)
    }

    private func optionField(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                             step: Double, unit: String, help: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .frame(width: 60, alignment: .leading)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
        .help(help)
    }

    private func color(for kind: PingLine.Kind) -> Color {
        switch kind {
        case .info: return .primary
        case .reply: return .green
        case .failure: return .red
        }
    }
}
