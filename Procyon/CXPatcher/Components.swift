//
//  Components.swift
//  Procyon
//
//  Patcher components that are fetched from their upstream releases at patch
//  time, so a patched CrossOver carries the newest DXMT and DXVK rather than
//  whatever snapshot shipped inside the app bundle.
//

import Foundation

/// A component the patcher can refresh from its upstream GitHub releases.
enum PatchComponent: String, CaseIterable {
    case dxmt
    case dxvk

    var displayName: String {
        switch self {
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        }
    }

    /// Repository the releases are published to.
    var repo: String {
        switch self {
        case .dxmt: return "3Shain/dxmt"
        case .dxvk: return "Gcenx/DXVK-macOS"
        }
    }

    /// Release asset suffix identifying the variant that can be installed.
    /// The `-builtin` builds are plain DLL/SO pairs meant to be dropped into a
    /// Wine prefix, which is exactly what the patcher does.
    var assetSuffix: String { "-builtin.tar.gz" }

    /// A file that must exist under the archive root, used to locate that root
    /// inside the extracted tarball.
    var rootMarker: String {
        switch self {
        case .dxmt: return "x86_64-unix/winemetal.so"
        case .dxvk: return "x86_64-windows/d3d11.dll"
        }
    }

    /// Which directory of the archive maps to which directory inside
    /// CrossOver's `Contents/SharedSupport/CrossOver`.
    var installDirs: [String: String] {
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
        }
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
        guard let url = URL(string: "https://api.github.com/repos/\(component.repo)/releases/latest") else {
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
        let (tag, remote) = try await latestAsset(for: component)
        let f = FileManager.default
        let dir = TarDownloader.getDownloadsDir()
            .appendingPathComponent("components", isDirectory: true)
            .appendingPathComponent("\(component.rawValue)-\(tag)", isDirectory: true)
        if let root = locateRoot(in: dir, marker: component.rootMarker) {
            console.log("\(component.displayName) \(tag) already downloaded")
            return root
        }
        try? f.removeItem(at: dir)
        try f.createDirectory(at: dir, withIntermediateDirectories: true)
        let archive = dir.appendingPathComponent("\(component.rawValue).tar.gz")
        try await download(remote, to: archive)
        try extract(archive, into: dir)
        try? f.removeItem(at: archive)
        guard let root = locateRoot(in: dir, marker: component.rootMarker) else {
            throw HTTPError.invalidResponse
        }
        console.log("\(component.displayName) \(tag) downloaded")
        return root
    }

    /// Copies an extracted component into a patched CrossOver app.
    static func install(_ component: PatchComponent, from root: URL, into app: URL) throws {
        let f = FileManager.default
        let sharedSupport = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
        for (source, destination) in component.installDirs {
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
