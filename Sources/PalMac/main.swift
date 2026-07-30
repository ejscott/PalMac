import Foundation
import PalMacKit

private func usage() -> Never {
    print("""
    PalMac — experimental Palworld mod manager for the native Mac build

    Usage:
      palmac status [--app /Applications/Palworld.app]
      palmac validate <package-directory>
      palmac install <package-directory> [--app /Applications/Palworld.app]
      palmac enable <PackageName> [--app /Applications/Palworld.app]
      palmac disable <PackageName> [--app /Applications/Palworld.app]
      palmac uninstall <PackageName> [--app /Applications/Palworld.app]
      palmac apply-request <request.json> [--app /Applications/Palworld.app]
      palmac apply-request-data <base64-request> [--app /Applications/Palworld.app]

    PalMac uses Unreal's standard PAK scanner and never modifies the game
    executable. Close Palworld before changing installed packages.
    """)
    exit(2)
}

private var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }
arguments.removeFirst()

var appPath = "/Applications/Palworld.app"
if let appIndex = arguments.firstIndex(of: "--app") {
    guard arguments.indices.contains(appIndex + 1) else { usage() }
    appPath = arguments[appIndex + 1]
    arguments.removeSubrange(appIndex...(appIndex + 1))
}

let service = PalMacService(
    appURL: URL(fileURLWithPath: appPath, isDirectory: true)
)

do {
    switch command {
    case "status":
        let status = try service.status()
        print("Palworld \(status.version) (revision \(status.revision))")
        print("Executable loader switch: \(status.executableState)")
        if !status.loaderStateIsSupported {
            print("WARNING: unsupported or unknown dormant-loader state; restore the App Store build if it was modified.")
        }
        print("Active packages: \(status.activePackages.isEmpty ? "none" : status.activePackages.joined(separator: ", "))")
        print("Managed mods: \(status.managedModsPath)")

    case "validate":
        guard arguments.count == 1 else { usage() }
        let report = service.inspectPackage(
            at: URL(fileURLWithPath: arguments[0], isDirectory: true)
        )
        guard report.canInstall else {
            throw CLIError.message(report.errors.joined(separator: "\n"))
        }
        print("Valid Paks package: \(report.modName) \(report.version) [\(report.packageName)]")
        for warning in report.warnings {
            print("warning: \(warning)")
        }

    case "install":
        guard arguments.count == 1 else { usage() }
        let packageURL = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let report = service.inspectPackage(at: packageURL)
        guard report.canInstall else {
            throw CLIError.message(report.errors.joined(separator: "\n"))
        }
        try service.perform(
            PalMacOperationRequest(action: .install, packagePath: packageURL.path)
        )
        print("Installed and enabled \(report.modName) [\(report.packageName)].")
        print("The game was not launched.")

    case "uninstall":
        guard arguments.count == 1 else { usage() }
        try service.perform(
            PalMacOperationRequest(action: .uninstall, packageName: arguments[0])
        )
        print("Uninstalled \(arguments[0]).")

    case "enable", "disable":
        guard arguments.count == 1 else { usage() }
        let enabled = command == "enable"
        try service.perform(
            PalMacOperationRequest(
                action: enabled ? .enable : .disable,
                packageName: arguments[0]
            )
        )
        print("\(enabled ? "Enabled" : "Disabled") \(arguments[0]).")
        print("Restart Palworld for the change to take effect.")

    case "apply-request":
        guard arguments.count == 1 else { usage() }
        let request = try PalMacService.loadRequest(
            from: URL(fileURLWithPath: arguments[0])
        )
        try service.perform(request)
        print("Operation completed.")

    case "apply-request-data":
        guard arguments.count == 1,
              let data = Data(base64Encoded: arguments[0]) else { usage() }
        let request = try JSONDecoder().decode(PalMacOperationRequest.self, from: data)
        try service.perform(request)
        print("Operation completed.")

    default:
        usage()
    }
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private enum CLIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
