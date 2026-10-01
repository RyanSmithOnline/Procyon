//
//  SteamLocalLibrary.swift
//  Procyon
//
//  Reads the games a Steam account owns out of Steam's own on-disk caches, so
//  owned-but-not-installed games can be shown with no API key and no account
//  login. Purely local and offline.
//

import Foundation

/// Sources, in order of coverage:
///  * `appcache/librarycache/<appid>/` – library artwork cache, one folder per
///    app in the account's library. This is the main source.
///  * `userdata/<id>/config/librarycache/<appid>.json` – per-user library page
///    cache.
///  * `userdata/<id>/config/localconfig.vdf` – per-app state/playtime for apps
///    the account has interacted with.
enum SteamLocalLibrary {
    private static let wineRoot = "/drive_c/Program Files (x86)/Steam"
    private static let macRoot = "/Library/Application Support/Steam"

    /// Steam install roots worth inspecting: the selected CrossOver bottle and,
    /// when present, the native macOS Steam install.
    private static func steamRoots(bottlePath: URL?) -> [URL] {
        var roots: [URL] = []
        if let bottlePath {
            roots.append(bottlePath.appendingPathComponent(wineRoot))
        }
        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(macRoot))
        return roots
    }

    /// All app ids found in Steam's local caches. Best effort: a cache that is
    /// missing or unreadable is skipped.
    static func ownedAppIDs(bottlePath: URL?) -> Set<String> {
        var ids = Set<String>()
        let fm = FileManager.default
        for root in steamRoots(bottlePath: bottlePath) {
            guard fm.fileExists(atPath: root.path(percentEncoded: false)) else { continue }

            // Library artwork cache: one directory per app in the library.
            ids.formUnion(numericEntries(in: root.appendingPathComponent("appcache/librarycache")))

            // Per-user caches.
            let userdata = root.appendingPathComponent("userdata")
            guard let users = try? fm.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for user in users {
                let config = user.appendingPathComponent("config")
                ids.formUnion(numericJSONNames(in: config.appendingPathComponent("librarycache")))
                ids.formUnion(localConfigAppIDs(at: config.appendingPathComponent("localconfig.vdf")))
            }
        }
        return ids
    }

    private static func numericEntries(in directory: URL) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return Set(entries.compactMap { isNumeric($0.lastPathComponent) ? $0.lastPathComponent : nil })
    }

    private static func numericJSONNames(in directory: URL) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return Set(entries.compactMap { url in
            let stem = url.deletingPathExtension().lastPathComponent
            return url.pathExtension.lowercased() == "json" && isNumeric(stem) ? stem : nil
        })
    }

    private static func localConfigAppIDs(at url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let parsed = parseVDFToDict(from: text)
        guard let software = parsed["Software"] as? [String: Any],
              let valve = software["Valve"] as? [String: Any],
              let steam = valve["Steam"] as? [String: Any],
              let apps = steam["apps"] as? [String: Any] else { return [] }
        return Set(apps.keys.filter(isNumeric))
    }

    private static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }
}
