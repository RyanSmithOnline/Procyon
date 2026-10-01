//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 03/02/2026.
//

import AppKit
import Combine
import UniformTypeIdentifiers

let DEFAULT_BOTTLE_PATH = "Library/Application Support/CrossOver/Bottles/"
let BLACKLIST = [
    "228980", // Steamworks
]
let debugEnabled: Bool = {
    let env = ProcessInfo.processInfo.environment["PROCYON_DEBUG"]?.lowercased()
    switch env {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return false
    }
}()
let useLogger: Bool = false

func prettyPrinted(dict: Dictionary<String, Any>) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "{}"
}

func addSteamFolderPaths(_ url: URL) {
    do {
        if (try getIDsFromFolder(dest: url).isEmpty) {
            console.warn("\(url) Folder is empty")
            return
        }
    } catch {
        console.warn("Failed to validate steam folder")
        console.error(String(reflecting: error))
    }
    do {
        try persistFolderAccess(url: url)
    } catch {
        console.error("Failed to save steam folder")
        console.error(String(reflecting: error))
    }
}

func removeSteamFolderPath(_ path: String) {
    let url = URL(string: path)!
    removePersistedFolderAccess(url: url)
}

func getSteamFolderPaths() -> [String] {
    return resolvePersistedFolders().map { $0.absoluteString }
}

func extractAppIDRegex(from filename: String) -> String? {
    let pattern = #"^appmanifest_(\d+)\.acf$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
    guard let match = regex?.firstMatch(in: filename, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: filename) else { return nil }
    return String(filename[idRange])
}

func extractFolderNameRegex(_ path: String) -> String {
    let pattern = #"^file:\/\/\/Volumes\/(.+)\/steamapps\/$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let decodedpath = path.removingPercentEncoding ?? path
    let range = NSRange(decodedpath.startIndex..<decodedpath.endIndex, in: decodedpath)
    guard let match = regex?.firstMatch(in: decodedpath, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: decodedpath) else { return decodedpath }
    return String(decodedpath[idRange])
}

//let id = extractAppIDRegex(from: "appmanifest_8870.acf") // "8870"

func getIDsFromFolder(dest: URL) throws -> [String] {
    /**
     scans a folder and returns an array of steam games ids
     */
    try withSecurityScope(for: dest) {
        let f = FileManager.default
        let urls = try f.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        return urls
            .filter { $0.pathExtension == "acf"}
            .map {
                extractAppIDRegex(from: $0.lastPathComponent) ?? "0"
            }
            .filter { !BLACKLIST.contains($0) }
    } ?? []
}

func getIsNative(fromURL: URL) -> Bool {
    if !folderContainsFile(withExtension: "exe", at: fromURL) && folderContainsFile(withExtension: "app", at: fromURL) {
        return true
    }
    return false
}

func safeShell(_ command: String) throws {
    let task = Process()

    task.standardInput = FileHandle.nullDevice
    // Launch commands print the real reason a game failed to start, so capture
    // them when debugging instead of sending them to /dev/null.
    if debugEnabled {
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        console.log(String(data: data, encoding: .utf8) ?? "")
        return
    }
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")

    try task.run()
}

let DEFAULT_STEAM_MAC_PATH = "/Library/Application Support/Steam/config/"
let DEFAULT_STEAM_WINE_PATH = "/drive_c/Program Files (x86)/Steam/config/"

func getSteamUserDataFallback (usingBottlePath: URL) -> UserInfo? {
    let steamLoginUsersPath = usingBottlePath.appendingPathComponent(DEFAULT_STEAM_WINE_PATH)
        .appendingPathComponent("loginusers.vdf")
    guard let steamSettingsFile = try? String(contentsOfFile: steamLoginUsersPath.path(percentEncoded: false), encoding: .utf8) else { return nil }
    let parsed = parseVDFToDict(from: steamSettingsFile)
    let users = parsed["users"] as? [String: Any]
    if let key = users?.keys.first {
        let user = users![key] as? [String: Any]
        let personaName = user?["PersonaName"] as? String ?? ""
        let avatar = usingBottlePath.appendingPathComponent("/drive_c/Program Files (x86)/Steam/config/avatarcache/").appendingPathComponent(key).appendingPathExtension("png").absoluteString
        let fallbackProfileData = UserInfo(
            steamID: key,
            communityVisibilityState: 0,
            profileState: 0,
            personaName: personaName,
            profileURL: "https://steamcommunity.com/profiles/\(key)",
            avatar: avatar,
            avatarMedium: avatar,
            avatarFull: avatar,
            avatarHash: "",
            lastLogOff: 0,
            personaState: 0,
            primaryClanID: "",
            timeCreated: 0,
            personaStateFlags: 0,
            locCountryCode: nil,
            locStateCode: nil
        )
        return fallbackProfileData
    }
    return nil
}

func getSteamLibraryFolders(from: URL) -> [URL] {
    let f = FileManager.default
    var steamLibraries: [URL] = []
    let drives = getBottleDrives(bottleURL: from)
    console.log("drives: \(String(describing: drives))")
    let steamSettingsPaths = [
        from.appendingPathComponent(DEFAULT_STEAM_WINE_PATH)
            .appendingPathComponent("libraryfolders.vdf"),
        f.homeDirectoryForCurrentUser
            .appendingPathComponent(DEFAULT_STEAM_MAC_PATH)
            .appendingPathComponent("libraryfolders.vdf")
    ].filter{ f.fileExists(atPath: $0.path(percentEncoded: false)) }
    for steamSettingsPath in steamSettingsPaths {
        do {
            let steamSettingsFile = try String(contentsOfFile: steamSettingsPath.path(percentEncoded: false), encoding: .utf8)
            let parsed = parseVDFToDict(from: steamSettingsFile)
            if let libraries = parsed["libraryfolders"] as? [String: Any] {
                for (_, value) in libraries { // Refactor this mess
                    if let val = (value as? [String: Any]) {
                        if let path = val["path"] as? String{
                            let driveAlias = String(path.split(separator: ":\\")[0]) + ":"
                            let splitPath = path.split(separator: ":")
                            if (splitPath.count > 1){
                                let partial = splitPath[1].replacingOccurrences(of: "\\\\", with: "/")
                                if let newPath = drives[driveAlias]?.appendingPathComponent(partial).appendingPathComponent("/steamapps") {
                                    steamLibraries.append(newPath)
                                } else {
                                    console.log("couldn't find Windows Steam config")
                                }
                            } else {
                                let macNewPath = URL(fileURLWithPath: path).appendingPathComponent("/steamapps")
                                steamLibraries.append(macNewPath)
                            }
                        }
                    }
                }
            }
        } catch {
            console.error(String(reflecting: error))
            return []
        }
    }
    console.log("all steam libraries \(steamLibraries.debugDescription)")
    return steamLibraries
}

func validateAddSteamFolder(_ url: URL, to folders: inout [String]) {
    if folders.contains(url.absoluteString) {
        console.log("\(url.absoluteString) folder exists!")
        return
    }
    addSteamFolderPaths(url)
    folders.append(url.absoluteString)
}

func mapPersonaState(_ state: Int) -> String {
    let states = ["Offline", "Online", "Busy", "Away", "Snooze", "looking to trade", "looking to play"]
    if (0..<states.count).contains(state){
        return states[state]
    }
    return "Unknown"
}

func getAppNames(isNative: Bool, gameURL: URL?) -> [String] {
    let ext = isNative ? "app" : "exe"
    let f = FileManager.default
    var results: [String] = []
    if(gameURL == nil) {
        return []
    }
    guard let enumerator = f.enumerator(at: gameURL!, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
        return []
    }
    for case let fileURL as URL in enumerator  {
        if(fileURL.pathExtension == ext) {
            results.append(fileURL.lastPathComponent)
        }
    }
    return results
}

/// Base for the watchers that tail a log inside the Windows Steam installation.
class SteamLogWatcher {
    let steamID: String
    let steamPath: String
    let fileName: String
    /// Looks like 'C:\Program Files (x86)\Steam\logs\<fileName>'
    var logPath: String { "\(steamPath)/logs/\(fileName)" }

    init(steamID: String, steamPath: String, fileName: String) {
        self.steamID = steamID
        self.steamPath = steamPath
        self.fileName = fileName
    }
}

/// Waits for Steam to finish its cloud sync pass before quitting, so saves are
/// flushed to the cloud instead of being lost with the process.
class SteamCloudSyncWatcher: SteamLogWatcher {
    init(steamID: String, steamPath: String) {
        super.init(steamID: steamID, steamPath: steamPath, fileName: "cloud_log.txt")
    }

    func waitForSteamCloudSync() async throws {
        let deadline = Date().addingTimeInterval(60)
        var polling = true
        while polling {
            try await Task.sleep(nanoseconds: 100_000_000)
            let content = try String(contentsOfFile: logPath, encoding: .utf8)
            if Date() > deadline {
                console.log("\(steamID): Cloud sync timed out")
                polling = false
            } else if content.contains(steamID) && content.contains("Cloud sync complete") {
                console.log("\(steamID): Cloud sync complete")
                polling = false
            }
        }
    }
}

/// Resolves the executable Steam actually launched for an app.
///
/// Guessing from the game's install directory means walking every file in it and
/// matching process names, which picks up launcher stubs and helper exes and
/// misses games that rename or relocate their binary. Steam records the real
/// process in `gameprocess_log.txt`, so read that instead.
class SteamLaunchWatcher: SteamLogWatcher {
    init(steamID: String, steamPath: String) {
        super.init(steamID: steamID, steamPath: steamPath, fileName: "gameprocess_log.txt")
    }

    func getGameExe() async throws -> String {
        let appIDMarker = "AppID \(steamID) adding PID"
        var appExe = ""
        let deadline = Date().addingTimeInterval(90)
        var polling = true
        let pattern = /[^\\]+\.exe/
        while polling {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                let content = try String(contentsOfFile: logPath, encoding: .utf8)
                for line in content.split(separator: "[") where line.contains(appIDMarker) {
                    appExe = String(line.firstMatch(of: pattern)?.output ?? "not found")
                    polling = false
                }
                console.log("File \(fileName) found")
            } catch {
                console.error(String(describing: error))
                console.error("File \(fileName) seems missing, retrying...")
            }
            if Date() > deadline {
                console.log("\(steamID): App name fetching timed out")
                polling = false
            }
        }
        return appExe
    }

    /// Waits for the resolved executable to show up in the process list.
    ///
    /// - Returns: the matched executable name, or an empty string on timeout.
    func trackLaunch() async throws -> String {
        var polling = true
        var returnedValue = ""
        let appName = try await getGameExe()
        let deadline = Date().addingTimeInterval(90)
        console.log("App name found: \(appName)")
        while polling {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if Date() > deadline {
                console.log("\(steamID): Launch tracking timed out")
                polling = false
            }
            let running = NSWorkspace.shared.runningApplications
                .flatMap { [$0.executableURL?.lastPathComponent ?? "none", $0.bundleURL?.lastPathComponent ?? "none"] }
                .filter { $0.contains(".exe") }
            if running.contains(appName) {
                returnedValue = appName
                polling = false
            }
        }
        return returnedValue
    }
}

/// Watches a launched game and tears the session down when it exits.
///
/// For Windows games the exe name comes from Steam's own launch log, which is
/// both faster and more accurate than walking the install directory. Native
/// games have no such log, so they fall back to polling for a process name.
func getGameTracker(appNames: [String], cxAppPath: String, bottleName: String, onLoad: @escaping (_ appName: String) -> Void, onTerminate: @escaping () -> Void, isNative: Bool, steamID: Int?, steamPath: String) async throws -> TerminationObserver {
    let tOb = TerminationObserver(then: { output in
        console.log(output.userInfo?.description ?? "no userInfo")
        let terminatedAppProcessName = output.userInfo?[AnyHashable("NSApplicationName")] as? String ?? "unknown"
        let terminatedAppPath = output.userInfo?[AnyHashable("NSApplicationPath")] as? String ?? "unknown"
        let terminatedAppName = String(terminatedAppPath.split(separator: "/").last ?? "unknown")
        if (appNames.contains(terminatedAppName) || appNames.contains(terminatedAppProcessName)) {
            console.log("\(appNames) -> \(terminatedAppName) or \(terminatedAppProcessName) has been terminated, closing steam...")
            Task {
                if !isNative, let steamID {
                    // SteamCloudSyncWatcher isn't for native steam games
                    let cloudSyncWatcher = SteamCloudSyncWatcher(steamID: String(steamID), steamPath: steamPath)
                    try await cloudSyncWatcher.waitForSteamCloudSync()
                }
                try await quitSteam(cxAppPath: cxAppPath, bottleName: bottleName, isNative: isNative)
                if !isNative {
                    try await closeWineActivities()
                }
                onTerminate()
                console.log("onTerminate() was called")
            }
        }
    })

    if let steamID, !isNative, !steamPath.isEmpty {
        do {
            let appName = try await SteamLaunchWatcher(steamID: String(steamID), steamPath: steamPath).trackLaunch()
            if !appName.isEmpty {
                console.log("found game \(appName), loading...")
                onLoad(appName)
            } else {
                console.log("\(appNames.joined(separator: ", ")), timeout...")
                onTerminate()
            }
        } catch {
            console.error("launch tracking failed: \(String(reflecting: error))")
            onTerminate()
        }
    } else {
        try await trackPlaying(apps: appNames, then: { matched in
            console.log("found game \(matched), loading...")
            onLoad(matched)
        }, onTimeout: {
            console.log("\(appNames.joined(separator: ", ")), timeout...")
            onTerminate()
        }, isNative: isNative)
    }
    return tOb
}

enum TarDownloader {
    public static func getDownloadsDir() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("\(appName)/downloads")
    }
    
    public static func deleteAllDownloadCache() {
        let downloadDir = TarDownloader.getDownloadsDir()
        try? FileManager.default.removeItem(at: downloadDir)
        deleteUsrDefOptionStartsWith(prefix: "downloads")
    }
}
