import Foundation

enum PalMacError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

struct InstallRule: Codable {
    let type: String
    let isServer: Bool?
    let targets: [String]

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case isServer = "IsServer"
        case targets = "Targets"
    }
}

struct ModInfo: Codable {
    let modName: String
    let packageName: String
    let thumbnail: String?
    let version: String
    let debugMode: Bool?
    let minRevision: Int?
    let author: String?
    let description: String?
    let dependencies: [String]?
    let installRule: [InstallRule]

    enum CodingKeys: String, CodingKey {
        case modName = "ModName"
        case packageName = "PackageName"
        case thumbnail = "Thumbnail"
        case version = "Version"
        case debugMode = "DebugMode"
        case minRevision = "MinRevision"
        case author = "Author"
        case description = "Description"
        case dependencies = "Dependencies"
        case installRule = "InstallRule"
    }
}

struct InstallManifest: Codable {
    let workshopId: Int64
    let lastWorkshopUpdateTimeUtc: String
    let lastInstallTimeUtc: String
    let files: [String]
    let dirs: [String]

    enum CodingKeys: String, CodingKey {
        case workshopId = "WorkshopId"
        case lastWorkshopUpdateTimeUtc = "LastWorkshopUpdateTimeUtc"
        case lastInstallTimeUtc = "LastInstallTimeUtc"
        case files = "Files"
        case dirs = "Dirs"
    }
}

struct PalworldLayout {
    let app: URL

    var executable: URL { app.appendingPathComponent("Contents/MacOS/Palworld") }
    var infoPlist: URL { app.appendingPathComponent("Contents/Info.plist") }
    var unrealRoot: URL { app.appendingPathComponent("Contents/UE") }
    var palMacRoot: URL { unrealRoot.appendingPathComponent("PalMac") }
    var managedMods: URL { palMacRoot.appendingPathComponent("ManagedMods") }
    var state: URL { palMacRoot.appendingPathComponent("State.json") }
    var pakMods: URL {
        unrealRoot.appendingPathComponent("Pal/Content/Paks/~PalMacMods")
    }
}

struct PackageArchiveSet {
    let files: [URL]
    let totalBytes: Int64
}

enum ModPackage {
    static let supportedTypes = Set(["Paks"])
    static let packageNamePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_]+$")
    static let archiveNamePattern = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
    )
    static let archiveExtensions = Set(["pak", "ucas", "utoc"])
    static let maximumInfoBytes = 1 * 1_024 * 1_024
    static let maximumThumbnailBytes = 10 * 1_024 * 1_024
    static let maximumArchiveBytes: Int64 = 64 * 1_024 * 1_024 * 1_024
    static let maximumPackageBytes: Int64 = 128 * 1_024 * 1_024 * 1_024

    static func decodeInfo(from directory: URL) throws -> ModInfo {
        let root = try packageRoot(directory)
        let infoURL = root.appendingPathComponent("Info.json")
        guard FileManager.default.fileExists(atPath: infoURL.path) else {
            throw PalMacError.message("Info.json was not found at the package root.")
        }
        let values = try infoURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw PalMacError.message("Info.json must be a regular file, not a symbolic link.")
        }
        guard let size = values.fileSize, size <= maximumInfoBytes else {
            throw PalMacError.message("Info.json is larger than the 1 MB safety limit.")
        }

        let data = try Data(contentsOf: infoURL)
        let info: ModInfo
        do {
            info = try JSONDecoder().decode(ModInfo.self, from: data)
        } catch {
            throw PalMacError.message("Info.json is invalid: \(error.localizedDescription)")
        }

        let range = NSRange(info.packageName.startIndex..., in: info.packageName)
        guard !info.packageName.isEmpty, info.packageName.count <= 64,
              packageNamePattern.firstMatch(in: info.packageName, range: range) != nil else {
            throw PalMacError.message(
                "PackageName must be 1–64 ASCII letters, numbers, or underscores."
            )
        }
        guard !info.modName.isEmpty, info.modName.count <= 128,
              !info.version.isEmpty, info.version.count <= 64 else {
            throw PalMacError.message("ModName or Version is empty or too long.")
        }
        guard (info.author?.count ?? 0) <= 128,
              (info.description?.count ?? 0) <= 4_096,
              (info.thumbnail?.count ?? 0) <= 256 else {
            throw PalMacError.message("Package metadata exceeds the supported length limits.")
        }
        guard !info.installRule.isEmpty, info.installRule.count <= 16 else {
            throw PalMacError.message("A package needs between 1 and 16 InstallRule entries.")
        }
        return info
    }

    static func load(from directory: URL) throws -> ModInfo {
        let root = try packageRoot(directory)
        let info = try decodeInfo(from: directory)
        for rule in info.installRule where rule.isServer != true {
            guard supportedTypes.contains(rule.type) else {
                throw PalMacError.message(
                    "Install type \(rule.type) is not supported by the Mac proof of concept. Only Paks is currently safe."
                )
            }
            guard !rule.targets.isEmpty, rule.targets.count <= 16 else {
                throw PalMacError.message("Each Paks InstallRule needs between 1 and 16 targets.")
            }
            for target in rule.targets {
                guard !target.isEmpty, target.count <= 256 else {
                    throw PalMacError.message("An InstallRule target is empty or too long.")
                }
                _ = try safeDirectory(target, under: root)
            }
        }
        if let thumbnail = info.thumbnail {
            _ = try safeRegularFile(
                thumbnail,
                under: root,
                maximumBytes: maximumThumbnailBytes,
                purpose: "Thumbnail"
            )
        }
        return info
    }

    static func archiveSet(from directory: URL, info: ModInfo) throws -> PackageArchiveSet {
        let root = try packageRoot(directory)
        var files: [URL] = []
        var names = Set<String>()
        var totalBytes: Int64 = 0

        for rule in info.installRule where rule.isServer != true && rule.type == "Paks" {
            for target in rule.targets {
                let sourceDirectory = try safeDirectory(target, under: root)
                let children = try FileManager.default.contentsOfDirectory(
                    at: sourceDirectory,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey
                    ],
                    options: []
                )
                for file in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if file.lastPathComponent == ".DS_Store" { continue }
                    let values = try file.resourceValues(
                        forKeys: [
                            .isDirectoryKey,
                            .isRegularFileKey,
                            .isSymbolicLinkKey,
                            .fileSizeKey
                        ]
                    )
                    guard values.isDirectory != true,
                          values.isRegularFile == true,
                          values.isSymbolicLink != true else {
                        throw PalMacError.message(
                            "Paks targets may contain only regular archive files: \(file.lastPathComponent)"
                        )
                    }

                    let name = file.lastPathComponent
                    let nameRange = NSRange(name.startIndex..., in: name)
                    guard archiveNamePattern.firstMatch(in: name, range: nameRange) != nil else {
                        throw PalMacError.message("Unsafe or unsupported archive filename: \(name)")
                    }
                    let ext = file.pathExtension.lowercased()
                    guard archiveExtensions.contains(ext) else {
                        throw PalMacError.message(
                            "Unsupported file in a Paks target: \(name). Only .pak, .ucas, and .utoc are allowed."
                        )
                    }
                    guard names.insert(name.lowercased()).inserted else {
                        throw PalMacError.message("Duplicate archive filename: \(name)")
                    }
                    guard let byteCount = values.fileSize, byteCount > 0,
                          Int64(byteCount) <= maximumArchiveBytes else {
                        throw PalMacError.message(
                            "\(name) is empty or exceeds the 64 GB per-file safety limit."
                        )
                    }
                    try rejectExecutableHeader(file)
                    totalBytes += Int64(byteCount)
                    guard totalBytes <= maximumPackageBytes else {
                        throw PalMacError.message("The package exceeds the 128 GB total safety limit.")
                    }
                    files.append(file)
                }
            }
        }

        guard !files.isEmpty else {
            throw PalMacError.message("The package contains no .pak, .ucas, or .utoc files.")
        }
        let ucasNames = Set(files.filter { $0.pathExtension.lowercased() == "ucas" }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        let utocNames = Set(files.filter { $0.pathExtension.lowercased() == "utoc" }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        for name in ucasNames.subtracting(utocNames).sorted() {
            throw PalMacError.message("\(name).ucas is missing its matching .utoc file.")
        }
        for name in utocNames.subtracting(ucasNames).sorted() {
            throw PalMacError.message("\(name).utoc is missing its matching .ucas file.")
        }
        return PackageArchiveSet(files: files, totalBytes: totalBytes)
    }

    static func packageRoot(_ directory: URL) throws -> URL {
        let standardized = directory.standardizedFileURL
        let values = try standardized.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw PalMacError.message("The package root must be a real directory, not a symbolic link.")
        }
        return standardized.resolvingSymlinksInPath()
    }

    static func safeDirectory(_ relative: String, under root: URL) throws -> URL {
        let candidate = root.appendingPathComponent(relative, isDirectory: true).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        guard candidate.path == resolved.path,
              resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw PalMacError.message(
                "InstallRule target escapes the package root or traverses a symbolic link: \(relative)"
            )
        }
        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw PalMacError.message(
                "InstallRule target does not exist or is not a real directory: \(relative)"
            )
        }
        return resolved
    }

    static func safeRegularFile(
        _ relative: String,
        under root: URL,
        maximumBytes: Int,
        purpose: String
    ) throws -> URL {
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        guard candidate.path == resolved.path,
              resolved.path.hasPrefix(root.path + "/") else {
            throw PalMacError.message("\(purpose) escapes the package root or uses a symbolic link.")
        }
        let values = try resolved.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumBytes else {
            throw PalMacError.message("\(purpose) is not a regular file or is too large.")
        }
        return resolved
    }

    private static func rejectExecutableHeader(_ file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4) ?? Data()
        let forbidden: [Data] = [
            Data([0x4D, 0x5A]),             // Windows PE
            Data([0x23, 0x21]),             // script shebang
            Data([0xCF, 0xFA, 0xED, 0xFE]), // Mach-O 64-bit
            Data([0xFE, 0xED, 0xFA, 0xCF]), // swapped Mach-O 64-bit
            Data([0xCA, 0xFE, 0xBA, 0xBE])  // universal binary
        ]
        if forbidden.contains(where: { header.starts(with: $0) }) {
            throw PalMacError.message(
                "\(file.lastPathComponent) has an executable header and was rejected."
            )
        }
    }
}

struct PalMacState: Codable {
    var schemaVersion = 1
    var activeMods: [String]

    static func load(from url: URL) throws -> PalMacState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PalMacState(activeMods: [])
        }
        var state = try JSONDecoder().decode(PalMacState.self, from: Data(contentsOf: url))
        state.activeMods = Array(Set(state.activeMods)).sorted()
        return state
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var normalized = self
        normalized.activeMods = Array(Set(activeMods)).sorted()
        try JSONEncoder.pretty.encode(normalized).write(to: url, options: .atomic)
    }
}

struct LoaderSwitchDetector {
    static let symbol = "__ZN20FPalModLoaderManager17IsGlobalEnableModEv"
    static let disabledInstruction = Data([0x00, 0x00, 0x80, 0x52]) // mov w0, #0
    static let enabledInstruction = Data([0x20, 0x00, 0x80, 0x52])  // mov w0, #1

    enum State: String {
        case disabled
        case enabled
        case unknown
    }

    static func symbolAddress(executable: URL) throws -> UInt64 {
        let nm = Process()
        let filter = Process()
        let symbols = Pipe()
        let output = Pipe()

        nm.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        nm.arguments = ["-a", executable.path]
        nm.standardOutput = symbols
        nm.standardError = FileHandle.nullDevice

        filter.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        filter.arguments = ["-F", symbol]
        filter.standardInput = symbols
        filter.standardOutput = output
        filter.standardError = FileHandle.nullDevice

        try filter.run()
        try nm.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        nm.waitUntilExit()
        filter.waitUntilExit()
        guard nm.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            throw PalMacError.message("Could not inspect the Palworld executable.")
        }
        for line in text.split(whereSeparator: \.isNewline) where line.hasSuffix(" \(symbol)") {
            guard let first = line.split(separator: " ").first,
                  let address = UInt64(first, radix: 16) else { continue }
            return address
        }
        throw PalMacError.message("This Palworld build does not expose the expected mod-loader switch.")
    }

    static func textMapping(executable: URL) throws -> (vmAddress: UInt64, fileOffset: UInt64) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        process.arguments = ["-l", executable.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else {
            throw PalMacError.message("Could not inspect the executable layout.")
        }

        var inText = false
        var vmAddress: UInt64?
        var fileOffset: UInt64?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            if fields[0] == "segname" {
                inText = fields[1] == "__TEXT"
            } else if inText, fields[0] == "vmaddr" {
                vmAddress = UInt64(fields[1].replacingOccurrences(of: "0x", with: ""), radix: 16)
            } else if inText, fields[0] == "fileoff" {
                fileOffset = UInt64(fields[1])
                break
            }
        }
        guard let vmAddress, let fileOffset else {
            throw PalMacError.message("Could not locate the executable's __TEXT segment.")
        }
        return (vmAddress, fileOffset)
    }

    static func offset(executable: URL) throws -> UInt64 {
        let address = try symbolAddress(executable: executable)
        let mapping = try textMapping(executable: executable)
        guard address >= mapping.vmAddress else {
            throw PalMacError.message("The mod-loader symbol has an invalid address.")
        }
        return address - mapping.vmAddress + mapping.fileOffset
    }

    static func state(executable: URL) throws -> State {
        let data = try Data(contentsOf: executable, options: .mappedIfSafe)
        let patchOffset = try offset(executable: executable)
        guard patchOffset + 4 <= data.count else {
            throw PalMacError.message("The mod-loader switch is outside the executable.")
        }
        let bytes = data.subdata(in: Int(patchOffset)..<Int(patchOffset + 4))
        if bytes == disabledInstruction { return .disabled }
        if bytes == enabledInstruction { return .enabled }
        return .unknown
    }

}

struct PalMacManager {
    let layout: PalworldLayout
    private let fileManager = FileManager.default

    func verifyInstallation() throws -> [String: String] {
        guard fileManager.fileExists(atPath: layout.executable.path),
              fileManager.fileExists(atPath: layout.infoPlist.path) else {
            throw PalMacError.message("Palworld.app was not found at \(layout.app.path).")
        }
        let plistData = try Data(contentsOf: layout.infoPlist)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil)
        guard let dictionary = plist as? [String: Any],
              dictionary["CFBundleIdentifier"] as? String == "com.pocketpair.palworld.mac" else {
            throw PalMacError.message("The selected app is not the native Mac App Store build of Palworld.")
        }
        return [
            "version": dictionary["CFBundleShortVersionString"] as? String ?? "unknown",
            "revision": dictionary["CFBundleVersion"] as? String ?? "unknown",
            "loaderSwitch": try LoaderSwitchDetector.state(executable: layout.executable).rawValue
        ]
    }

    func prepareManagedAccess(userID: UInt32, groupID: UInt32) throws {
        let installation = try verifyInstallation()
        try requireSupportedLoaderState(installation["loaderSwitch"])

        let roots = [layout.palMacRoot, layout.pakMods]
        for root in roots {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let unrealRoot = layout.unrealRoot.standardizedFileURL.resolvingSymlinksInPath()
        let ownership: [FileAttributeKey: Any] = [
            .ownerAccountID: NSNumber(value: userID),
            .groupOwnerAccountID: NSNumber(value: groupID)
        ]

        for root in roots {
            let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedRoot.path.hasPrefix(unrealRoot.path + "/") else {
                throw PalMacError.message("A managed mod folder resolves outside Palworld.")
            }

            try fileManager.setAttributes(ownership, ofItemAtPath: resolvedRoot.path)
            guard let enumerator = fileManager.enumerator(
                at: resolvedRoot,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []
            ) else { continue }

            for case let item as URL in enumerator {
                let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                try fileManager.setAttributes(ownership, ofItemAtPath: item.path)
            }
        }
    }

    func install(package source: URL) throws -> ModInfo {
        let info = try ModPackage.load(from: source)
        let packageRoot = try ModPackage.packageRoot(source)
        let archives = try ModPackage.archiveSet(from: packageRoot, info: info)
        let installation = try verifyInstallation()
        try requireSupportedLoaderState(installation["loaderSwitch"])
        let revision = Int(installation["revision"] ?? "0") ?? 0
        if let minimum = info.minRevision, minimum > revision {
            throw PalMacError.message(
                "This mod requires Palworld revision \(minimum), but the installed revision is \(revision)."
            )
        }
        try fileManager.createDirectory(at: layout.managedMods, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.pakMods, withIntermediateDirectories: true)
        _ = try verifiedManagedRoot(layout.managedMods)
        _ = try verifiedManagedRoot(layout.pakMods)
        try requireFreeSpace(for: archives.totalBytes)

        let managedDestination = try managedDirectory(for: info.packageName)
        if fileManager.fileExists(atPath: managedDestination.path) {
            throw PalMacError.message("\(info.packageName) is already installed. Uninstall it before replacing it.")
        }
        try fileManager.createDirectory(at: managedDestination, withIntermediateDirectories: true)
        _ = try verifiedDirectory(managedDestination, under: layout.managedMods)
        try fileManager.copyItem(
            at: packageRoot.appendingPathComponent("Info.json"),
            to: managedDestination.appendingPathComponent("Info.json")
        )
        if let thumbnail = info.thumbnail {
            let thumbnailSource = try ModPackage.safeRegularFile(
                thumbnail,
                under: packageRoot,
                maximumBytes: ModPackage.maximumThumbnailBytes,
                purpose: "Thumbnail"
            )
            try fileManager.copyItem(
                at: thumbnailSource,
                to: managedDestination.appendingPathComponent(thumbnailSource.lastPathComponent)
            )
        }

        var deployedFiles: [String] = []
        var deployedDirs: [String] = []
        do {
            let modPakDestination = try deploymentDirectory(for: info.packageName)
            try fileManager.createDirectory(at: modPakDestination, withIntermediateDirectories: true)
            _ = try verifiedDirectory(modPakDestination, under: layout.pakMods)
            deployedDirs.append(relativeToRoot(modPakDestination))

            for file in archives.files {
                let destination = modPakDestination.appendingPathComponent(file.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    throw PalMacError.message(
                        "A deployed file already exists: \(destination.lastPathComponent)"
                    )
                }
                let partial = destination.appendingPathExtension("partial")
                try fileManager.copyItem(at: file, to: partial)
                try fileManager.moveItem(at: partial, to: destination)
                deployedFiles.append(relativeToRoot(destination))
            }

            let now = ISO8601DateFormatter().string(from: Date())
            let manifest = InstallManifest(
                workshopId: 0,
                lastWorkshopUpdateTimeUtc: now,
                lastInstallTimeUtc: now,
                files: deployedFiles,
                dirs: deployedDirs
            )
            let manifestData = try JSONEncoder.pretty.encode(manifest)
            try manifestData.write(
                to: managedDestination.appendingPathComponent("InstallManifest.json"),
                options: .atomic
            )

            var state = try PalMacState.load(from: layout.state)
            if !state.activeMods.contains(info.packageName) {
                state.activeMods.append(info.packageName)
            }
            try state.save(to: layout.state)
            return info
        } catch {
            for relative in deployedFiles {
                try? fileManager.removeItem(at: layout.unrealRoot.appendingPathComponent(relative))
            }
            for relative in deployedDirs.reversed() {
                try? fileManager.removeItem(at: layout.unrealRoot.appendingPathComponent(relative))
            }
            try? fileManager.removeItem(at: managedDestination)
            throw error
        }
    }

    func uninstall(packageName: String) throws {
        try validatePackageName(packageName)
        let managed = try managedDirectory(for: packageName)
        let manifestURL = managed.appendingPathComponent("InstallManifest.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            let manifest = try trustedManifest(for: packageName)
            for relative in manifest.files {
                let deployed = try safeDeploymentFile(relative, packageName: packageName)
                try? fileManager.removeItem(at: deployed)
                try? fileManager.removeItem(
                    at: deployed.appendingPathExtension("disabled")
                )
            }
            for relative in manifest.dirs.sorted(by: { $0.count > $1.count }) {
                let directory = try safeDeploymentDirectory(relative, packageName: packageName)
                try? fileManager.removeItem(at: directory)
            }
        }
        if fileManager.fileExists(atPath: managed.path) {
            try fileManager.removeItem(at: managed)
        }
        var state = try PalMacState.load(from: layout.state)
        state.activeMods.removeAll { $0 == packageName }
        try state.save(to: layout.state)
    }

    func setEnabled(packageName: String, enabled: Bool) throws {
        try validatePackageName(packageName)
        if fileManager.fileExists(atPath: layout.executable.path) {
            try requireSupportedLoaderState(
                LoaderSwitchDetector.state(executable: layout.executable).rawValue
            )
        }
        let managed = try managedDirectory(for: packageName)
        let manifestURL = managed.appendingPathComponent("InstallManifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PalMacError.message("\(packageName) is not installed or has no install manifest.")
        }
        let manifest = try trustedManifest(for: packageName)

        for relative in manifest.files {
            let deployed = try safeDeploymentFile(relative, packageName: packageName)
            let disabled = deployed.appendingPathExtension("disabled")
            if enabled {
                if !fileManager.fileExists(atPath: deployed.path),
                   fileManager.fileExists(atPath: disabled.path) {
                    try fileManager.moveItem(at: disabled, to: deployed)
                }
            } else if fileManager.fileExists(atPath: deployed.path) {
                if fileManager.fileExists(atPath: disabled.path) {
                    try fileManager.removeItem(at: disabled)
                }
                try fileManager.moveItem(at: deployed, to: disabled)
            }
        }

        var state = try PalMacState.load(from: layout.state)
        state.activeMods.removeAll { $0 == packageName }
        if enabled {
            state.activeMods.append(packageName)
        }
        try state.save(to: layout.state)
    }

    private func validatePackageName(_ packageName: String) throws {
        let range = NSRange(packageName.startIndex..., in: packageName)
        guard !packageName.isEmpty,
              ModPackage.packageNamePattern.firstMatch(in: packageName, range: range) != nil else {
            throw PalMacError.message("Invalid package name.")
        }
    }

    private func requireSupportedLoaderState(_ state: String?) throws {
        guard state == LoaderSwitchDetector.State.disabled.rawValue else {
            throw PalMacError.message(
                "PalMac detected an unsupported or unknown dormant-loader state. Restore the App Store build if it was modified."
            )
        }
    }

    private func relativeToRoot(_ url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(layout.unrealRoot.standardizedFileURL.path.count + 1))
    }

    private func verifiedManagedRoot(_ root: URL) throws -> URL {
        let unrealRoot = layout.unrealRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        guard candidate.path == resolved.path,
              resolved.path.hasPrefix(unrealRoot.path + "/") else {
            throw PalMacError.message("A PalMac managed folder is a symbolic link or escaped Palworld.")
        }
        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw PalMacError.message("A PalMac managed folder is not a real directory.")
        }
        return resolved
    }

    private func verifiedDirectory(_ directory: URL, under root: URL) throws -> URL {
        let verifiedRoot = try verifiedManagedRoot(root)
        let candidate = directory.standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        guard candidate.path == resolved.path,
              resolved.path.hasPrefix(verifiedRoot.path + "/") else {
            throw PalMacError.message("A mod directory is a symbolic link or escaped its managed root.")
        }
        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw PalMacError.message("A mod directory is not a real directory.")
        }
        return resolved
    }

    private func managedDirectory(for packageName: String) throws -> URL {
        try validatePackageName(packageName)
        return layout.managedMods.appendingPathComponent(packageName).standardizedFileURL
    }

    private func deploymentDirectory(for packageName: String) throws -> URL {
        try validatePackageName(packageName)
        let candidate = layout.pakMods.appendingPathComponent(packageName).standardizedFileURL
        if fileManager.fileExists(atPath: candidate.path) {
            _ = try verifiedDirectory(candidate, under: layout.pakMods)
        }
        return candidate
    }

    private func trustedManifest(for packageName: String) throws -> InstallManifest {
        let managed = try managedDirectory(for: packageName)
        _ = try verifiedDirectory(managed, under: layout.managedMods)
        let manifestURL = managed.appendingPathComponent("InstallManifest.json")
        let values = try manifestURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= ModPackage.maximumInfoBytes else {
            throw PalMacError.message("The install manifest is missing, linked, or too large.")
        }
        let manifest = try JSONDecoder().decode(
            InstallManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        // Validate every path before any file operation takes place.
        for relative in manifest.files {
            _ = try safeDeploymentFile(relative, packageName: packageName)
        }
        for relative in manifest.dirs {
            _ = try safeDeploymentDirectory(relative, packageName: packageName)
        }
        return manifest
    }

    private func safeDeploymentFile(_ relative: String, packageName: String) throws -> URL {
        let deployment = try deploymentDirectory(for: packageName)
        let candidate = layout.unrealRoot.appendingPathComponent(relative).standardizedFileURL
        guard candidate.deletingLastPathComponent().path == deployment.path,
              ModPackage.archiveExtensions.contains(candidate.pathExtension.lowercased()) else {
            throw PalMacError.message("Install manifest contains an unsafe file path: \(relative)")
        }
        return candidate
    }

    private func safeDeploymentDirectory(_ relative: String, packageName: String) throws -> URL {
        let deployment = try deploymentDirectory(for: packageName)
        let candidate = layout.unrealRoot.appendingPathComponent(relative).standardizedFileURL
        guard candidate.path == deployment.path else {
            throw PalMacError.message("Install manifest contains an unsafe directory path: \(relative)")
        }
        return candidate
    }

    private func requireFreeSpace(for packageBytes: Int64) throws {
        let values = try layout.pakMods.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let reserve: Int64 = 1 * 1_024 * 1_024 * 1_024
        guard packageBytes <= max(0, available - reserve) else {
            throw PalMacError.message(
                "Not enough free disk space to install this package while keeping a 1 GB reserve."
            )
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
