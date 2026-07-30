import Foundation
import Darwin

public struct PalMacStatus: Sendable {
    public let version: String
    public let revision: String
    public let loaderStateIsSupported: Bool
    public let executableState: String
    public let activePackages: [String]
    public let managedModsPath: String
    public let passwordFreeManagement: Bool
}

public struct PalMacPackageReport: Sendable {
    public let modName: String
    public let packageName: String
    public let version: String
    public let author: String?
    public let details: String?
    public let archiveFiles: [String]
    public let errors: [String]
    public let warnings: [String]

    public var canInstall: Bool { errors.isEmpty }
}

public struct PalMacInstalledMod: Identifiable, Sendable {
    public var id: String { packageName }
    public let modName: String
    public let packageName: String
    public let version: String
    public let author: String?
    public let isEnabled: Bool
}

public struct PalMacOperationRequest: Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case install
        case enable
        case disable
        case uninstall
        case prepareAccess
    }

    public let action: Action
    public let packagePath: String?
    public let packageName: String?
    public let userID: UInt32?
    public let groupID: UInt32?

    public init(
        action: Action,
        packagePath: String? = nil,
        packageName: String? = nil,
        userID: UInt32? = nil,
        groupID: UInt32? = nil
    ) {
        self.action = action
        self.packagePath = packagePath
        self.packageName = packageName
        self.userID = userID
        self.groupID = groupID
    }
}

public final class PalMacService {
    public let appURL: URL
    private let layout: PalworldLayout
    private let manager: PalMacManager
    private let fileManager = FileManager.default

    public init(appURL: URL = URL(fileURLWithPath: "/Applications/Palworld.app", isDirectory: true)) {
        self.appURL = appURL
        self.layout = PalworldLayout(app: appURL)
        self.manager = PalMacManager(layout: layout)
    }

    public func status() throws -> PalMacStatus {
        let installation = try manager.verifyInstallation()
        let state = try PalMacState.load(from: layout.state)
        let executableState = installation["loaderSwitch"] ?? "unknown"
        return PalMacStatus(
            version: installation["version"] ?? "unknown",
            revision: installation["revision"] ?? "unknown",
            loaderStateIsSupported: executableState == LoaderSwitchDetector.State.disabled.rawValue,
            executableState: executableState,
            activePackages: state.activeMods,
            managedModsPath: layout.managedMods.path,
            passwordFreeManagement: hasManagedAccess()
        )
    }

    public func hasManagedAccess() -> Bool {
        fileManager.fileExists(atPath: layout.palMacRoot.path) &&
            fileManager.fileExists(atPath: layout.pakMods.path) &&
            fileManager.isWritableFile(atPath: layout.palMacRoot.path) &&
            fileManager.isWritableFile(atPath: layout.pakMods.path)
    }

    public func inspectPackage(at packageURL: URL) -> PalMacPackageReport {
        do {
            let info = try ModPackage.load(from: packageURL)
            let archiveSet = try ModPackage.archiveSet(from: packageURL, info: info)
            var warnings: [String] = []
            var errors: [String] = []

            if let minimum = info.minRevision,
               let installedRevision = try? status().revision,
               let revision = Int(installedRevision),
               minimum > revision {
                errors.append("Requires Palworld revision \(minimum); revision \(revision) is installed.")
            }
            if info.minRevision == nil {
                warnings.append("The package does not declare a minimum Palworld revision.")
            }
            warnings.append("Cooked platform compatibility cannot be proven from filenames; the content must target Palworld macOS.")

            return PalMacPackageReport(
                modName: info.modName,
                packageName: info.packageName,
                version: info.version,
                author: info.author,
                details: info.description,
                archiveFiles: archiveSet.files.map(\.lastPathComponent).sorted(),
                errors: errors,
                warnings: warnings
            )
        } catch {
            return PalMacPackageReport(
                modName: packageURL.lastPathComponent,
                packageName: "",
                version: "",
                author: nil,
                details: nil,
                archiveFiles: [],
                errors: [error.localizedDescription],
                warnings: []
            )
        }
    }

    public func installedMods() throws -> [PalMacInstalledMod] {
        let state = try PalMacState.load(from: layout.state)
        guard fileManager.fileExists(atPath: layout.managedMods.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: layout.managedMods,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { directory in
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true,
                  let info = try? ModPackage.decodeInfo(from: directory) else { return nil }
            return PalMacInstalledMod(
                modName: info.modName,
                packageName: info.packageName,
                version: info.version,
                author: info.author,
                isEnabled: state.activeMods.contains(info.packageName)
            )
        }.sorted { $0.modName.localizedCaseInsensitiveCompare($1.modName) == .orderedAscending }
    }

    public func perform(_ request: PalMacOperationRequest) throws {
        switch request.action {
        case .prepareAccess:
            guard geteuid() == 0 else {
                throw PalMacError.message("Preparing password-free access requires administrator authorization once.")
            }
            guard let userID = request.userID,
                  let groupID = request.groupID,
                  userID != 0,
                  request.packagePath == nil,
                  request.packageName == nil else {
                throw PalMacError.message("The access preparation request is malformed.")
            }
            try manager.prepareManagedAccess(userID: userID, groupID: groupID)
        case .install:
            guard geteuid() != 0 else {
                throw PalMacError.message(
                    "PalMac refuses to install packages as root. Administrator access is used only to prepare the two managed folders."
                )
            }
            guard let path = request.packagePath,
                  request.packageName == nil,
                  request.userID == nil,
                  request.groupID == nil else {
                throw PalMacError.message("The install request is malformed.")
            }
            _ = try manager.install(package: URL(fileURLWithPath: path, isDirectory: true))
        case .enable, .disable, .uninstall:
            guard geteuid() != 0 else {
                throw PalMacError.message(
                    "PalMac refuses mod file operations as root. Administrator access is used only for initial folder setup."
                )
            }
            guard let name = request.packageName,
                  request.packagePath == nil,
                  request.userID == nil,
                  request.groupID == nil else {
                throw PalMacError.message("The package request is malformed.")
            }
            if request.action == .uninstall {
                try manager.uninstall(packageName: name)
            } else {
                try manager.setEnabled(packageName: name, enabled: request.action == .enable)
            }
        }
    }

    public static func loadRequest(from url: URL) throws -> PalMacOperationRequest {
        try JSONDecoder().decode(PalMacOperationRequest.self, from: Data(contentsOf: url))
    }
}
