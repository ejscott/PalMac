import Foundation
import Testing
@testable import PalMacKit

@Test func stateRoundTrip() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("State.json")
    defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }

    try PalMacState(activeMods: ["Second", "First", "First"]).save(to: temporary)
    let loaded = try PalMacState.load(from: temporary)
    #expect(loaded.schemaVersion == 1)
    #expect(loaded.activeMods == ["First", "Second"])
}

@Test func validatesMinimalPakPackage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let paks = root.appendingPathComponent("Paks")
    try FileManager.default.createDirectory(at: paks, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let json = """
    {
      "ModName": "Mount Probe",
      "PackageName": "PalMacMountProbe",
      "Version": "1.0.0",
      "InstallRule": [{"Type": "Paks", "Targets": ["./Paks"]}]
    }
    """
    try json.write(to: root.appendingPathComponent("Info.json"), atomically: true, encoding: .utf8)
    try Data([0x00]).write(to: paks.appendingPathComponent("probe.pak"))

    let info = try ModPackage.load(from: root)
    #expect(info.packageName == "PalMacMountProbe")
}

@Test func rejectsTraversalTarget() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = parent.appendingPathComponent("Package")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let json = """
    {
      "ModName": "Unsafe",
      "PackageName": "Unsafe",
      "Version": "1.0.0",
      "InstallRule": [{"Type": "Paks", "Targets": [".."]}]
    }
    """
    try json.write(to: root.appendingPathComponent("Info.json"), atomically: true, encoding: .utf8)
    #expect(throws: Error.self) {
        _ = try ModPackage.load(from: root)
    }
}

@Test func rejectsPakDirectorySymlinkOutsidePackage() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = parent.appendingPathComponent("Package")
    let outside = parent.appendingPathComponent("Outside")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("Paks"),
        withDestinationURL: outside
    )

    let json = """
    {
      "ModName": "Symlink",
      "PackageName": "Symlink",
      "Version": "1.0.0",
      "InstallRule": [{"Type": "Paks", "Targets": ["./Paks"]}]
    }
    """
    try json.write(to: root.appendingPathComponent("Info.json"), atomically: true, encoding: .utf8)
    #expect(throws: Error.self) {
        _ = try ModPackage.load(from: root)
    }
}

@Test func disableAndEnableRenamesDeployedPak() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = root.appendingPathComponent("Palworld.app")
    let layout = PalworldLayout(app: app)
    let packageName = "ToggleProbe"
    let managed = layout.managedMods.appendingPathComponent(packageName)
    let deployed = layout.pakMods
        .appendingPathComponent(packageName)
        .appendingPathComponent("ToggleProbe_P.pak")
    try FileManager.default.createDirectory(
        at: managed,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: deployed.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try Data([0x01]).write(to: deployed)
    let relative = String(
        deployed.path.dropFirst(layout.unrealRoot.path.count + 1)
    )
    let manifest = InstallManifest(
        workshopId: 0,
        lastWorkshopUpdateTimeUtc: "2026-01-01T00:00:00Z",
        lastInstallTimeUtc: "2026-01-01T00:00:00Z",
        files: [relative],
        dirs: []
    )
    try JSONEncoder.pretty.encode(manifest).write(
        to: managed.appendingPathComponent("InstallManifest.json")
    )
    try PalMacState(activeMods: [packageName]).save(to: layout.state)

    let manager = PalMacManager(layout: layout)
    try manager.setEnabled(packageName: packageName, enabled: false)
    #expect(!FileManager.default.fileExists(atPath: deployed.path))
    #expect(FileManager.default.fileExists(atPath: deployed.appendingPathExtension("disabled").path))
    #expect(try PalMacState.load(from: layout.state).activeMods.isEmpty)

    try manager.setEnabled(packageName: packageName, enabled: true)
    #expect(FileManager.default.fileExists(atPath: deployed.path))
    #expect(!FileManager.default.fileExists(atPath: deployed.appendingPathExtension("disabled").path))
    #expect(try PalMacState.load(from: layout.state).activeMods == [packageName])
}

@Test func packageInspectorRejectsUnsupportedFilesInPaksTarget() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let paks = root.appendingPathComponent("Paks")
    try FileManager.default.createDirectory(at: paks, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let json = """
    {
      "ModName": "Windows Package",
      "PackageName": "WindowsPackage",
      "Version": "1.0.0",
      "InstallRule": [{"Type": "Paks", "Targets": ["./Paks"]}]
    }
    """
    try json.write(to: root.appendingPathComponent("Info.json"), atomically: true, encoding: .utf8)
    try Data([0x00]).write(to: paks.appendingPathComponent("Content.ucas"))
    try Data([0x00]).write(to: paks.appendingPathComponent("Loader.dll"))

    let report = PalMacService(appURL: root.appendingPathComponent("Missing.app"))
        .inspectPackage(at: root)
    #expect(!report.canInstall)
    #expect(report.errors.contains { $0.contains("Unsupported file") })
}

@Test func packageInspectorRejectsBrokenIoStorePair() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let paks = root.appendingPathComponent("Paks")
    try FileManager.default.createDirectory(at: paks, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let json = """
    {
      "ModName": "Broken Pair",
      "PackageName": "BrokenPair",
      "Version": "1.0.0",
      "InstallRule": [{"Type": "Paks", "Targets": ["./Paks"]}]
    }
    """
    try json.write(to: root.appendingPathComponent("Info.json"), atomically: true, encoding: .utf8)
    try Data([0x00]).write(to: paks.appendingPathComponent("Content.ucas"))

    let report = PalMacService(appURL: root.appendingPathComponent("Missing.app"))
        .inspectPackage(at: root)
    #expect(!report.canInstall)
    #expect(report.errors.contains { $0.contains("missing its matching .utoc") })
}

@Test func rejectsExecutableDisguisedAsPak() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let paks = root.appendingPathComponent("Paks")
    try FileManager.default.createDirectory(at: paks, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let json = """
    {
      "ModName": "Disguised Executable",
      "PackageName": "DisguisedExecutable",
      "Version": "1.0.0",
      "InstallRule": [{"Type": "Paks", "Targets": ["./Paks"]}]
    }
    """
    try json.write(to: root.appendingPathComponent("Info.json"), atomically: true, encoding: .utf8)
    try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: paks.appendingPathComponent("payload.pak"))

    let report = PalMacService(appURL: root.appendingPathComponent("Missing.app"))
        .inspectPackage(at: root)
    #expect(!report.canInstall)
    #expect(report.errors.contains { $0.contains("executable header") })
}

@Test func rejectsInfoSymlink() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = parent.appendingPathComponent("Package")
    let externalInfo = parent.appendingPathComponent("External.json")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let json = """
    {
      "ModName": "Linked Metadata",
      "PackageName": "LinkedMetadata",
      "Version": "1.0.0",
      "InstallRule": [{"Type": "Paks", "Targets": ["./Paks"]}]
    }
    """
    try json.write(to: externalInfo, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("Info.json"),
        withDestinationURL: externalInfo
    )

    #expect(throws: Error.self) {
        _ = try ModPackage.load(from: root)
    }
}

@Test func tamperedManifestCannotDeleteGameContent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let layout = PalworldLayout(app: root.appendingPathComponent("Palworld.app"))
    let packageName = "Tampered"
    let managed = layout.managedMods.appendingPathComponent(packageName)
    let deployment = layout.pakMods.appendingPathComponent(packageName)
    let originalGameFile = layout.unrealRoot.appendingPathComponent(
        "Pal/Content/Paks/Pal-Mac.pak"
    )
    try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: deployment, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: originalGameFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0x01]).write(to: originalGameFile)

    let unsafeRelative = String(
        originalGameFile.path.dropFirst(layout.unrealRoot.path.count + 1)
    )
    let manifest = InstallManifest(
        workshopId: 0,
        lastWorkshopUpdateTimeUtc: "2026-01-01T00:00:00Z",
        lastInstallTimeUtc: "2026-01-01T00:00:00Z",
        files: [unsafeRelative],
        dirs: []
    )
    try JSONEncoder.pretty.encode(manifest).write(
        to: managed.appendingPathComponent("InstallManifest.json")
    )

    let manager = PalMacManager(layout: layout)
    #expect(throws: Error.self) {
        try manager.uninstall(packageName: packageName)
    }
    #expect(FileManager.default.fileExists(atPath: originalGameFile.path))
    #expect(FileManager.default.fileExists(atPath: managed.path))
}

@Test func discoversInstalledMetadataWithoutSourcePakDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let layout = PalworldLayout(app: root.appendingPathComponent("Palworld.app"))
    let managed = layout.managedMods.appendingPathComponent("MetadataOnly")
    try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let json = """
    {
      "ModName": "Metadata Only",
      "PackageName": "MetadataOnly",
      "Version": "1.2.0",
      "InstallRule": [{"Type": "Paks", "Targets": ["./Paks"]}]
    }
    """
    try json.write(to: managed.appendingPathComponent("Info.json"), atomically: true, encoding: .utf8)
    try PalMacState(activeMods: ["MetadataOnly"]).save(to: layout.state)

    let mods = try PalMacService(appURL: layout.app).installedMods()
    #expect(mods.count == 1)
    #expect(mods.first?.packageName == "MetadataOnly")
    #expect(mods.first?.isEnabled == true)
}
