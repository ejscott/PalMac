import AppKit
import SwiftUI
import PalMacKit
import Darwin

@main
struct PalMacApplication: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 860, height: 600)
    }
}

@MainActor
private final class AppModel: ObservableObject {
    @Published var status: PalMacStatus?
    @Published var installed: [PalMacInstalledMod] = []
    @Published var packageURL: URL?
    @Published var report: PalMacPackageReport?
    @Published var isWorking = false
    @Published var message: String?
    @Published var showingError = false

    init() {
        refresh()
    }

    func refresh() {
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let backgroundService = PalMacService()
                    return (
                        try backgroundService.status(),
                        try backgroundService.installedMods()
                    )
                }
            }.value
            switch result {
            case .success(let snapshot):
                status = snapshot.0
                installed = snapshot.1
            case .failure(let error):
                show(error)
            }
        }
    }

    func refreshInstalled() {
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try PalMacService().installedMods()
                }
            }.value
            switch result {
            case .success(let mods):
                installed = mods
            case .failure(let error):
                show(error)
            }
        }
    }

    func choosePackage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a PalMac mod package"
        panel.prompt = "Inspect Package"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        packageURL = url
        report = nil
        isWorking = true
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                PalMacService().inspectPackage(at: url)
            }.value
            self.report = report
            isWorking = false
        }
    }

    func installSelected() {
        guard let packageURL, report?.canInstall == true else { return }
        run(
            PalMacOperationRequest(action: .install, packagePath: packageURL.path),
            success: "The mod was installed and enabled."
        )
    }

    func launchPalworld() {
        let gameURL = URL(fileURLWithPath: "/Applications/Palworld.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: gameURL.path) else {
            showMessage("Palworld was not found in Applications.", isError: true)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: gameURL,
            configuration: configuration
        ) { _, error in
            Task { @MainActor in
                if let error {
                    self.show(error)
                } else {
                    self.showMessage("Palworld launched.", isError: false)
                }
            }
        }
    }

    func preparePasswordFreeAccess() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try PrivilegedOperationRunner.prepareManagedAccess()
                }
            }.value
            isWorking = false
            switch result {
            case .success:
                showMessage(
                    "Mod access is ready. Future mod changes will not require a password.",
                    isError: false
                )
                refresh()
            case .failure(let error):
                show(error)
            }
        }
    }

    func toggle(_ mod: PalMacInstalledMod) {
        run(
            PalMacOperationRequest(
                action: mod.isEnabled ? .disable : .enable,
                packageName: mod.packageName
            ),
            success: mod.isEnabled ? "The mod was disabled." : "The mod was enabled."
        )
    }

    func uninstall(_ mod: PalMacInstalledMod) {
        run(
            PalMacOperationRequest(action: .uninstall, packageName: mod.packageName),
            success: "The mod was uninstalled."
        )
    }

    private func run(_ request: PalMacOperationRequest, success: String) {
        guard !isWorking else { return }
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.pocketpair.palworld.mac"
        ).isEmpty else {
            showMessage("Close Palworld before changing mods.", isError: true)
            return
        }

        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try PrivilegedOperationRunner.run(request)
                }
            }.value
            isWorking = false
            switch result {
            case .success:
                message = success
                showingError = false
                refreshInstalled()
            case .failure(let error):
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        showMessage(error.localizedDescription, isError: true)
    }

    private func showMessage(_ text: String, isError: Bool) {
        message = text
        showingError = isError
    }
}

private enum PrivilegedOperationRunner {
    static func run(_ request: PalMacOperationRequest) throws {
        let service = PalMacService()
        if !service.hasManagedAccess() {
            try prepareManagedAccess()
        }
        try service.perform(request)
    }

    static func prepareManagedAccess() throws {
        let request = PalMacOperationRequest(
            action: .prepareAccess,
            userID: getuid(),
            groupID: getgid()
        )
        try runElevated(request)
    }

    private static func runElevated(_ request: PalMacOperationRequest) throws {
        guard let ownExecutable = Bundle.main.executableURL else {
            throw RunnerError.message("Could not locate the PalMac application executable.")
        }
        let cli = ownExecutable.deletingLastPathComponent().appendingPathComponent("PalMacHelper")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            throw RunnerError.message("The PalMac command helper is missing beside the application.")
        }

        let encodedRequest = try JSONEncoder().encode(request).base64EncodedString()
        let command = "\(shellQuote(cli.path)) apply-request-data \(shellQuote(encodedRequest))"
        let script = "do shell script \(appleScriptString(command)) with administrator privileges"
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RunnerError.message(text?.isEmpty == false ? text! : "The administrator operation was cancelled.")
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private enum RunnerError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let message): message
            }
        }
    }
}

private struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            List {
                Section("Palworld") {
                    Label("Overview", systemImage: "gamecontroller")
                }
                Section("Installed Mods") {
                    if model.installed.isEmpty {
                        Text("No PalMac mods installed")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.installed) { mod in
                        Label(mod.modName, systemImage: mod.isEnabled ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    gameStatus
                    installedMods
                    packageInspector
                    if let message = model.message {
                        Label(message, systemImage: model.showingError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(model.showingError ? .red : .green)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("PalMac")
            .toolbar {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Palworld Mods for macOS")
                .font(.largeTitle.bold())
            Text("Install and manage native Mac-compatible Unreal packages without modifying the game executable.")
                .foregroundStyle(.secondary)
        }
    }

    private var gameStatus: some View {
        GroupBox("Game Status") {
            VStack(spacing: 10) {
                HStack {
                    if let status = model.status {
                        Label(
                            "Palworld \(status.version) · revision \(status.revision)",
                            systemImage: status.loaderStateIsSupported ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .foregroundStyle(status.loaderStateIsSupported ? .green : .red)
                        Spacer()
                        Button {
                            model.launchPalworld()
                        } label: {
                            Label("Launch Palworld", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        ProgressView()
                        Text("Checking Palworld…")
                        Spacer()
                    }
                }

                if let status = model.status {
                    HStack {
                        Label(
                            status.passwordFreeManagement
                                ? "Mod access ready"
                                : "One-time mod access setup required",
                            systemImage: status.passwordFreeManagement
                                ? "lock.open.fill"
                                : "lock.fill"
                        )
                        .foregroundStyle(
                            status.passwordFreeManagement
                                ? Color.secondary
                                : Color.orange
                        )
                        Spacer()
                        if !status.passwordFreeManagement {
                            Button("Set Up…") {
                                model.preparePasswordFreeAccess()
                            }
                            .disabled(model.isWorking || !status.loaderStateIsSupported)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var installedMods: some View {
        GroupBox("Installed Mods") {
            VStack(spacing: 0) {
                if model.installed.isEmpty {
                    ContentUnavailableView(
                        "No Mods Installed",
                        systemImage: "shippingbox",
                        description: Text("Choose a package below to inspect and install it.")
                    )
                    .frame(height: 130)
                } else {
                    ForEach(model.installed) { mod in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mod.modName).font(.headline)
                                Text("\(mod.version) · \(mod.packageName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle(
                                "Enabled",
                                isOn: Binding(
                                    get: { mod.isEnabled },
                                    set: { _ in model.toggle(mod) }
                                )
                            )
                            .toggleStyle(.switch)
                            .disabled(model.isWorking)
                            Button("Uninstall", role: .destructive) {
                                model.uninstall(mod)
                            }
                            .disabled(model.isWorking)
                        }
                        .padding(10)
                        if mod.id != model.installed.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var packageInspector: some View {
        GroupBox("Add a Mod") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Choose Package…") { model.choosePackage() }
                    if let url = model.packageURL {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }
                if let report = model.report {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.modName).font(.headline)
                        Text("\(report.version) · \(report.packageName)")
                            .foregroundStyle(.secondary)
                        ForEach(report.errors, id: \.self) {
                            Label($0, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                        }
                        ForEach(report.warnings, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        if !report.archiveFiles.isEmpty {
                            Text("\(report.archiveFiles.count) content file\(report.archiveFiles.count == 1 ? "" : "s") found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Install and Enable") { model.installSelected() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!report.canInstall || model.isWorking || model.status?.loaderStateIsSupported != true)
                    }
                }
                if model.isWorking {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Applying change…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
        }
    }
}
