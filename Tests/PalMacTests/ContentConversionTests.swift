import Foundation
import Testing

@Test func contentConversionPlanReportsMacOverrides() throws {
    let root = try conversionTemporaryDirectory(named: "Plan")
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("LegacySource")
    let overlay = root.appendingPathComponent("MacOverlay")
    let assetPath = "Pal/Content/Pal/Model/Test"
    let sourceAssets = source.appendingPathComponent(assetPath)
    let overlayAssets = overlay.appendingPathComponent(assetPath)
    try FileManager.default.createDirectory(
        at: sourceAssets,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: overlayAssets,
        withIntermediateDirectories: true
    )
    try Data("mesh".utf8).write(
        to: sourceAssets.appendingPathComponent("SK_Test.uasset")
    )
    try Data("windows".utf8).write(
        to: sourceAssets.appendingPathComponent("T_Test.uasset")
    )
    try Data("mac".utf8).write(
        to: overlayAssets.appendingPathComponent("T_Test.uasset")
    )
    try Data("bulk".utf8).write(
        to: overlayAssets.appendingPathComponent("T_Test.ubulk")
    )

    let result = try runConversionPlanner(
        source: source,
        overlay: overlay,
        output: root.appendingPathComponent("Build")
    )

    #expect(result.status == 0, Comment(rawValue: result.output))
    #expect(
        result.output.contains("2 source file(s), 2 Mac overlay file(s)"),
        Comment(rawValue: result.output)
    )
    #expect(
        result.output.contains(
            "1 source file(s) replaced by Mac-cooked data"
        ),
        Comment(rawValue: result.output)
    )
    #expect(
        result.output.contains("Plan only"),
        Comment(rawValue: result.output)
    )
}

@Test func contentConversionPlanRejectsUnsupportedFiles() throws {
    let root = try conversionTemporaryDirectory(named: "RejectsDLL")
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("LegacySource")
    let sourceAssets = source.appendingPathComponent(
        "Pal/Content/Pal/Model/Test"
    )
    try FileManager.default.createDirectory(
        at: sourceAssets,
        withIntermediateDirectories: true
    )
    try Data("MZ".utf8).write(
        to: sourceAssets.appendingPathComponent("Loader.dll")
    )

    let result = try runConversionPlanner(
        source: source,
        overlay: nil,
        output: root.appendingPathComponent("Build")
    )

    #expect(result.status != 0, Comment(rawValue: result.output))
    #expect(
        result.output.contains("unsupported cooked file"),
        Comment(rawValue: result.output)
    )
}

@Test func contentConversionPlanRejectsSymbolicLinks() throws {
    let root = try conversionTemporaryDirectory(named: "RejectsSymlink")
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("LegacySource")
    let sourceAssets = source.appendingPathComponent(
        "Pal/Content/Pal/Model/Test"
    )
    try FileManager.default.createDirectory(
        at: sourceAssets,
        withIntermediateDirectories: true
    )
    let target = root.appendingPathComponent("Target.uasset")
    try Data("asset".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(
        at: sourceAssets.appendingPathComponent("Linked.uasset"),
        withDestinationURL: target
    )

    let result = try runConversionPlanner(
        source: source,
        overlay: nil,
        output: root.appendingPathComponent("Build")
    )

    #expect(result.status != 0, Comment(rawValue: result.output))
    #expect(
        result.output.contains("contains a symbolic link"),
        Comment(rawValue: result.output)
    )
}

@Test func contentConversionBuildCreatesPalMacPackage() throws {
    let root = try conversionTemporaryDirectory(named: "Build")
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("LegacySource")
    let sourceAssets = source.appendingPathComponent(
        "Pal/Content/Pal/Model/Test"
    )
    try FileManager.default.createDirectory(
        at: sourceAssets,
        withIntermediateDirectories: true
    )
    try Data("mesh".utf8).write(
        to: sourceAssets.appendingPathComponent("SK_Test.uasset")
    )

    let tools = root.appendingPathComponent("Tools")
    try FileManager.default.createDirectory(
        at: tools,
        withIntermediateDirectories: true
    )
    let unrealPak = tools.appendingPathComponent("UnrealPak")
    let retoc = tools.appendingPathComponent("retoc")
    try """
    #!/bin/zsh
    print -r -- "legacy" > "$1"
    """.write(to: unrealPak, atomically: true, encoding: .utf8)
    try """
    #!/bin/zsh
    set -e
    if [[ "$1" == "to-zen" ]]; then
      output="$5"
      base="${output%.utoc}"
      print -r -- "pak" > "$base.pak"
      print -r -- "ucas" > "$base.ucas"
      print -r -- "utoc" > "$base.utoc"
    fi
    """.write(to: retoc, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: unrealPak.path
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: retoc.path
    )

    let output = root.appendingPathComponent("Output")
    let result = try runConversionBuild(
        source: source,
        output: output,
        unrealPak: unrealPak,
        retoc: retoc
    )

    #expect(result.status == 0, Comment(rawValue: result.output))
    let package = output.appendingPathComponent("TestConversion")
    let infoData = try Data(
        contentsOf: package.appendingPathComponent("Info.json")
    )
    let info = try #require(
        JSONSerialization.jsonObject(with: infoData) as? [String: Any]
    )
    #expect(info["PackageName"] as? String == "TestConversion")
    #expect(info["ModName"] as? String == "Test Conversion")
    #expect(info["MinRevision"] as? Int == 100933)
    for extensionName in ["pak", "ucas", "utoc"] {
        #expect(
            FileManager.default.fileExists(
                atPath: package.appendingPathComponent(
                    "Paks/TestConversion_P.\(extensionName)"
                ).path
            )
        )
    }
    #expect(
        FileManager.default.fileExists(
            atPath: output.appendingPathComponent(
                "TestConversion.zip.sha256"
            ).path
        )
    )
}

private func runConversionPlanner(
    source: URL,
    overlay: URL?,
    output: URL
) throws -> (status: Int32, output: String) {
    let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Scripts/build-content-conversion.zsh")

    var arguments = [
        script.path,
        "--source-root", source.path,
        "--package-name", "TestConversion",
        "--mod-name", "Test Conversion",
        "--output-root", output.path,
        "--plan-only",
    ]
    if let overlay {
        arguments.insert(
            contentsOf: ["--overlay-root", overlay.path],
            at: 3
        )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (
        process.terminationStatus,
        String(decoding: data, as: UTF8.self)
    )
}

private func runConversionBuild(
    source: URL,
    output: URL,
    unrealPak: URL,
    retoc: URL
) throws -> (status: Int32, output: String) {
    let script = conversionScriptURL()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [
        script.path,
        "--source-root", source.path,
        "--package-name", "TestConversion",
        "--mod-name", "Test Conversion",
        "--output-root", output.path,
        "--min-revision", "100933",
        "--unreal-pak", unrealPak.path,
        "--retoc", retoc.path,
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (
        process.terminationStatus,
        String(decoding: data, as: UTF8.self)
    )
}

private func conversionScriptURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Scripts/build-content-conversion.zsh")
}

private func conversionTemporaryDirectory(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "PalMacTests-\(name)-\(UUID().uuidString)"
        )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}
