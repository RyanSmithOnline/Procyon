//
//  Components.swift
//  Procyon
//
//  Patcher components. DXMT and DXVK are fetched from their upstream releases
//  at patch time, so a patched CrossOver carries the newest builds rather than
//  whatever snapshot shipped inside the app bundle. Wine has no compatible
//  upstream release, so it is installed from the bundled overlay.
//

import Foundation

/// A component the patcher installs into a copied CrossOver app.
enum PatchComponent: String, CaseIterable {
    case dxmt
    case dxvk
    case wine

    var displayName: String {
        switch self {
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .wine: return "Wine"
        }
    }

    /// Whether the component is refreshed from an upstream release archive.
    ///
    /// Wine is not: `Gcenx/macOS_Wine_builds` only publishes generic
    /// `wine-devel`/`wine-staging` trees with no CrossOver-compatible asset, and
    /// dropping a Wine from a different vintage into a current CrossOver is the
    /// surest way to break a bottle. Wine is installed from the bundled overlay
    /// instead, which is version-matched to what this fork ships.
    var isFetched: Bool { self != .wine }

    /// Components installed from the app bundle rather than fetched.
    static var bundled: [PatchComponent] { allCases.filter { !$0.isFetched } }

    /// Repository the releases are published to.
    var repo: String? {
        switch self {
        case .dxmt: return "3Shain/dxmt"
        case .dxvk: return "Gcenx/DXVK-macOS"
        case .wine: return nil
        }
    }

    /// Release asset suffix identifying the variant that can be installed.
    /// The `-builtin` builds are plain DLL/SO pairs meant to be dropped into a
    /// Wine prefix, which is exactly what the patcher does.
    var assetSuffix: String { "-builtin.tar.gz" }

    /// A file that must exist under the archive root, used to locate that root
    /// inside the extracted tarball.
    var rootMarker: String? {
        switch self {
        case .dxmt: return "x86_64-unix/winemetal.so"
        case .dxvk: return "x86_64-windows/d3d11.dll"
        case .wine: return nil
        }
    }

    /// Which directory of the archive maps to which directory inside
    /// CrossOver's `Contents/SharedSupport/CrossOver`.
    var installDirs: [String: String]? {
        switch self {
        case .dxmt:
            return [
                "x86_64-unix": "lib/dxmt/x86_64-unix",
                "i386-windows": "lib/dxmt/i386-windows",
                "x86_64-windows": "lib/dxmt/x86_64-windows",
            ]
        case .dxvk:
            return [
                "i386-windows": "lib/dxvk/i386-windows",
                "x86_64-windows": "lib/dxvk/x86_64-windows",
            ]
        case .wine:
            return nil
        }
    }

    /// Files copied straight out of the app bundle, as bundle-relative resource
    /// name and a destination relative to `Contents/SharedSupport/CrossOver`.
    ///
    /// Only D9VK is overlaid. It supplies `d3d9`, which DXVK has not shipped for
    /// a long time, and it is a self-contained drop-in for a single library.
    ///
    /// The Wine core (`ntdll`, `win32u`, `winedmo`, `winegstreamer`) is
    /// deliberately *not* overlaid. The bundled copies are a different Wine
    /// vintage than the one inside the CrossOver build being patched, and
    /// `ntdll.so` is the first library every Wine process loads, so a mismatch
    /// there makes the whole runtime fail before any program starts:
    /// `wine: failed to load start.exe: c000000d`. That broke Steam and every
    /// other launch. CrossOver's own copies of these libraries stay in place.
    var bundledFiles: [(res: String, dest: String)] {
        let d9vk: [(res: String, dest: String)] = [
            (res: "d9vk/x32/d3d9_builtin.dll", dest: "/lib/wine/i386-windows/d3d9.dll"),
            (res: "d9vk/x64/d3d9_builtin.dll", dest: "/lib/wine/x86_64-windows/d3d9.dll"),
        ]
        guard self == .wine else { return [] }
        return d9vk
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let downloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

private struct GitHubRelease: Decodable {
    let tag: String
    let assets: [GitHubAsset]

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case assets
    }
}

enum ComponentUpdater {
    /// Resolves the newest installable release asset for `component`.
    static func latestAsset(for component: PatchComponent) async throws -> (tag: String, url: URL) {
        guard let repo = component.repo else {
            throw HTTPError.badURL
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw HTTPError.badURL
        }
        let release = try await HTTPClient.get(url, as: GitHubRelease.self)
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(component.assetSuffix) }) else {
            throw HTTPError.invalidResponse
        }
        return (release.tag, asset.downloadURL)
    }

    /// Downloads and extracts the newest release, reusing an already extracted
    /// copy so re-patching (and offline patching) is cheap.
    ///
    /// - Returns: the archive root holding the component's directories.
    static func prepare(_ component: PatchComponent) async throws -> URL {
        guard let marker = component.rootMarker else { throw HTTPError.badURL }
        let (tag, remote) = try await latestAsset(for: component)
        let f = FileManager.default
        let dir = TarDownloader.getDownloadsDir()
            .appendingPathComponent("components", isDirectory: true)
            .appendingPathComponent("\(component.rawValue)-\(tag)", isDirectory: true)
        if let root = locateRoot(in: dir, marker: marker) {
            console.log("\(component.displayName) \(tag) already downloaded")
            return root
        }
        try? f.removeItem(at: dir)
        try f.createDirectory(at: dir, withIntermediateDirectories: true)
        let archive = dir.appendingPathComponent("\(component.rawValue).tar.gz")
        try await download(remote, to: archive)
        try extract(archive, into: dir)
        try? f.removeItem(at: archive)
        guard let root = locateRoot(in: dir, marker: marker) else {
            throw HTTPError.invalidResponse
        }
        console.log("\(component.displayName) \(tag) downloaded")
        return root
    }

    /// Copies an extracted component into a patched CrossOver app.
    static func install(_ component: PatchComponent, from root: URL, into app: URL) throws {
        guard let installDirs = component.installDirs else { throw HTTPError.invalidResponse }
        let f = FileManager.default
        let sharedSupport = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
        for (source, destination) in installDirs {
            let from = root.appendingPathComponent(source, isDirectory: true)
            guard let files = try? f.contentsOfDirectory(at: from, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            let to = sharedSupport.appendingPathComponent(destination, isDirectory: true)
            try f.createDirectory(at: to, withIntermediateDirectories: true)
            for file in files {
                let dest = to.appendingPathComponent(file.lastPathComponent)
                try? f.removeItem(at: dest)
                try f.copyItem(at: file, to: dest)
                console.log("installed \(component.displayName) \(file.lastPathComponent)")
            }
        }
    }

    /// Wine core libraries that earlier Procyon versions overlaid into the
    /// patched app. They are a different Wine vintage than the CrossOver build
    /// being patched, and a stale copy left behind by an older version keeps
    /// the runtime broken (`failed to load start.exe: c000000d`) even after
    /// updating, so patching removes them again.
    private static let legacyWineOverlay = [
        "lib/wine/x86_64-unix/ntdll.so",
        "lib/wine/x86_64-unix/winedmo.so",
        "lib/wine/x86_64-unix/win32u.so",
        "lib/wine/x86_64-unix/winegstreamer.so",
        "lib/wine/i386-windows/ntdll.dll",
        "lib/wine/i386-windows/win32u.dll",
        "lib/wine/x86_64-windows/ntdll.dll",
        "lib/wine/x86_64-windows/win32u.dll",
        "lib/wine/x86_64-windows/winegstreamer.dll",
    ]

    /// Removes a Wine core library previously overlaid by an older Procyon, so
    /// the patched app falls back to the matching copy inside CrossOver.
    static func removeLegacyWineOverlay(from app: URL) {
        let f = FileManager.default
        for relative in legacyWineOverlay {
            let dest = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT + "/" + relative)
            guard f.fileExists(atPath: dest.path(percentEncoded: false)) else { continue }
            do {
                try f.removeItem(at: dest)
                console.log("removed stale Wine overlay \(relative)")
            } catch {
                console.error("couldn't remove stale Wine overlay \(relative): \(String(reflecting: error))")
            }
        }
    }

    /// Copies a component's bundled files into a patched CrossOver app.
    static func installBundled(_ component: PatchComponent, into app: URL) {
        if component == .wine {
            removeLegacyWineOverlay(from: app)
        }
        let f = FileManager.default
        for file in component.bundledFiles {
            let dest = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT + file.dest)
            guard let source = Bundle.main.url(forResource: file.res, withExtension: nil) else {
                console.error("bundled resource \(file.res) not found, leaving CrossOver's copy in place")
                continue
            }
            try? f.removeItem(at: dest)
            do {
                try f.copyItem(at: source, to: dest)
                console.log("installed \(component.displayName) \(file.dest)")
            } catch {
                console.error("couldn't install \(file.res): \(String(reflecting: error))")
            }
        }
    }

    private static func download(_ remote: URL, to dest: URL) async throws {
        let (temp, response) = try await URLSession.shared.download(from: remote)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HTTPError.invalidResponse
        }
        let f = FileManager.default
        if f.fileExists(atPath: dest.path(percentEncoded: false)) {
            try f.removeItem(at: dest)
        }
        try f.moveItem(at: temp, to: dest)
    }

    private static func extract(_ archive: URL, into dir: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        task.arguments = ["-xf", archive.path(percentEncoded: false), "-C", dir.path(percentEncoded: false)]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(
                domain: "ComponentUpdater",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "couldn't extract \(archive.lastPathComponent)"]
            )
        }
    }

    /// Release archives wrap their payload in a single directory whose name
    /// changes with every version, so find it by a known file instead of by name.
    private static func locateRoot(in dir: URL, marker: String) -> URL? {
        let f = FileManager.default
        var level: [URL] = [dir]
        for _ in 0..<3 {
            var next: [URL] = []
            for candidate in level {
                if f.fileExists(atPath: candidate.appendingPathComponent(marker).path(percentEncoded: false)) {
                    return candidate
                }
                let children = (try? f.contentsOfDirectory(at: candidate, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                next.append(contentsOf: children.filter { child in
                    (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                })
            }
            if next.isEmpty { return nil }
            level = next
        }
        return nil
    }
}
