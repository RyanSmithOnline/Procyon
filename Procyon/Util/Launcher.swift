//
//  Launcher.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import AppKit

func resolveAppPath(_ path: String) -> String {
    if path.hasPrefix("/") {
        return path
    } else {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return (home as NSString).appendingPathComponent(path)
    }
}

func closeWineActivities() async throws {
    // Wait for graceful termination, then escalate to forceTerminate, then give a final wait
    let gracePeriod: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    let pollInterval: UInt64 = 200_000_000  // 0.2 seconds in nanoseconds
//    let forceTimeout: UInt64 = 6_000_000_000 // ~6 seconds total before force
    let absoluteTimeout: UInt64 = 12_000_000_000 // ~12 seconds absolute timeout

    
    // Capture the target apps first to avoid the list changing while iterating
    let targets = NSWorkspace.shared.runningApplications.filter { app in
        // Wine processes can report a nil executableURL, in which case the
        // bundle is the only place the process name is available.
        if let bundleURL = app.bundleURL {
            return bundleURL.lastPathComponent.lowercased().hasSuffix(".exe") || bundleURL.lastPathComponent.lowercased().contains("wine")
        }
        if let executableURL = app.executableURL {
            return executableURL.lastPathComponent.lowercased().hasSuffix(".exe") || executableURL.lastPathComponent.lowercased().contains("wine")
        }
        return false
    }

    // Send terminate to all matching apps
    for app in targets {
        if let name = (app.executableURL ?? app.bundleURL)?.lastPathComponent {
            console.warn("terminating \(name)")
        }
        app.terminate()
    }

    // Helper to check if all targets have terminated
    func allTerminated(_ apps: [NSRunningApplication]) -> Bool {
        apps.allSatisfy { $0.isTerminated }
    }

    var elapsed: UInt64 = 0
    // First grace period loop
    while !allTerminated(targets) && elapsed < gracePeriod {
        try await Task.sleep(nanoseconds: pollInterval)
        elapsed += pollInterval
    }

    // If still not all terminated after grace period, escalate with terminate
    if !allTerminated(targets) {
        for app in targets where !app.isTerminated {
            console.warn("force terminating \(app.executableURL?.lastPathComponent ?? "<unknown>")")
            app.forceTerminate()
        }
    }

    // Final wait until absolute timeout or done
    while !allTerminated(targets) && elapsed < absoluteTimeout {
        try await Task.sleep(nanoseconds: pollInterval)
        elapsed += pollInterval
    }
}

func trackPlaying(apps: [String], then: @escaping (_ matched: String) -> Void, onTimeout: @escaping () -> Void, isNative: Bool) async throws -> Void {
    let pollInterval: UInt64 = 500_000_000
    let gracePeriod: UInt64 = 60_000_000_000 // after 60 seconds give up tracking
    var elapsed: UInt64 = 0
    var targets = isNative ? NSWorkspace.shared.runningApplications : NSWorkspace.shared.runningApplications.filter { app in
        guard let url = app.executableURL else { return false }
        return url.lastPathComponent.lowercased().hasSuffix(".exe")
    }
    
    var nativeOrWineApps: [String] {
        isNative ? apps + apps.map { $0.replacingOccurrences(of: ".app", with: "") } : apps
    }
    
    while (elapsed < gracePeriod) {
        try await Task.sleep(nanoseconds: pollInterval)
        let newTargets = isNative ? NSWorkspace.shared.runningApplications : NSWorkspace.shared.runningApplications.filter { app in
            guard let url = app.executableURL else { return false }
            return url.lastPathComponent.lowercased().hasSuffix(".exe") && !targets.contains(where: { $0.processIdentifier == app.processIdentifier })
        }
        targets.append(contentsOf: newTargets)
        if let match = newTargets.first(where: { Set(nativeOrWineApps).contains($0.executableURL?.lastPathComponent) }) {
            let matched = match.executableURL?.lastPathComponent ?? ""
            if(!isNative) { // attempts to "select" the app if for some reason it isn't (happens with wine/crossover)
                match.activate(options: [.activateAllWindows])
            }
            then(matched)
            return
        }
        elapsed += pollInterval
    }
    if(elapsed < gracePeriod){
        console.warn("\(nativeOrWineApps.description) crashed")
    } else {
        console.warn("couldn't find apps \(nativeOrWineApps.description) within the allowed grace period elapsed: \(elapsed/1_000_000_000)s ")
    }
    console.log("starting timeout callback...")
    onTimeout()
}

func quitSteam(cxAppPath: String, bottleName: String, isNative: Bool) async throws -> Void {
    console.log("quitting steam...")
    if(isNative) {
        let steamBundleID = "com.valvesoftware.steam"
        if let steamApp = NSRunningApplication.runningApplications(withBundleIdentifier: steamBundleID).first {
            steamApp.terminate() // polite request to quit
        }
    } else {
        let absPath = resolveAppPath(cxAppPath)
        try safeShell("env WINEMSYNC=1 \"\(absPath)/Contents/SharedSupport/CrossOver/bin/wine\" --bottle \"\(bottleName)\" \"C:\\Program Files (x86)\\Steam\\Steam.exe\" -shutdown")
    }
}

func openSteam(cxAppPath: String?, selectedBottle: String?) {
    guard let rawCxPath = cxAppPath, !rawCxPath.isEmpty,
          let bottleStr = selectedBottle, !bottleStr.isEmpty,
          let bottleURL = URL(string: bottleStr) else {
        console.error("openSteam: missing cxAppPath (\(String(describing: cxAppPath))) or selectedBottle (\(String(describing: selectedBottle)))")
        return
    }
    
    let absoluteCxPath = resolveAppPath(rawCxPath)
    let wineBin = "\(absoluteCxPath)/Contents/SharedSupport/CrossOver/bin/wine"
    let wineserverBin = "\(absoluteCxPath)/Contents/SharedSupport/CrossOver/bin/wineserver"
    let bottleName = bottleURL.lastPathComponent
    let bottlePath = bottleURL.path(percentEncoded: false)
    let bottleParentDir = bottleURL.deletingLastPathComponent().path(percentEncoded: false)
    
    // Ensure cxbottle.conf contains WINEMSYNC=1 so CrossOver's bin/wine script loads it into environment
    try? editCXBottleConfigFile(selectedBottle: bottleStr, options: [
        "WINEMSYNC": "1",
        "CX_GRAPHICS_BACKEND": CXGraphicsBackend.d3dmetal.rawValue
    ])
    
    let f = FileManager.default
    let steamExe32 = bottleURL.appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe")
    let steamExe64 = bottleURL.appendingPathComponent("drive_c/Program Files/Steam/Steam.exe")

    var steamWindowsPath = "C:\\Program Files (x86)\\Steam\\Steam.exe"
    if f.fileExists(atPath: steamExe32.path(percentEncoded: false)) {
        steamWindowsPath = "C:\\Program Files (x86)\\Steam\\Steam.exe"
    } else if f.fileExists(atPath: steamExe64.path(percentEncoded: false)) {
        steamWindowsPath = "C:\\Program Files\\Steam\\Steam.exe"
    } else {
        console.warn("Steam.exe not found in bottle \(bottleName) at \(steamExe32.path). Attempting launch anyway...")
    }

    // Kill any existing wineserver daemon for this bottle using the actual wineserver binary
    let killCommand = "WINEPREFIX=\"\(bottlePath)\" \"\(wineserverBin)\" -k"
    try? safeShell(killCommand)
    Thread.sleep(forTimeInterval: 0.5)

    // Same runtime environment the game launcher uses, so Steam starts against
    // the same patched CrossOver build (DXMT/DXVK/MoltenVK and the GStreamer
    // paths for video) instead of a bare environment.
    let inlineEnvs = getInlineEnvs(from: GameOptions(), cxAppPath: absoluteCxPath)
    let separator = inlineEnvs.hasSuffix(" ") ? "" : " "
    let steamLaunchCommand = "env \(inlineEnvs)\(separator)CX_BOTTLE_PATH=\"\(bottleParentDir)\" WINEPREFIX=\"\(bottlePath)\" CX_ROOT=\"\(absoluteCxPath)/Contents/SharedSupport/CrossOver\" WINEMSYNC=1 \"\(wineBin)\" --bottle \"\(bottleName)\" \"\(steamWindowsPath)\""
    
    do {
        console.log("Launching Steam with command: \(steamLaunchCommand)")
        try safeShell(steamLaunchCommand)
    } catch {
        console.error("openSteam error: \(String(reflecting: error))")
    }
}

func launchWindowsGame(id: String, cxAppPath: String, selectedBottle: String, options: GameOptions? = nil, appExeURL: URL? = nil) async throws -> Void {
    guard let bottleURL = URL(string: selectedBottle) else {
        console.error("Invalid bottle URL: \(selectedBottle)")
        return
    }
    if(options == nil) {
        console.error("Missing game options for game with id \(id) - cannot launch (options = nil)")
        return
    }
    let f = FileManager.default
    let absoluteCxPath = resolveAppPath(cxAppPath)

    var command = ""
    
    // registry
    let regOptionsDictionary: [String: UInt32] = [
        "DisableHidraw":options!.disableHidraw ? 1 : 0,
        "Enable SDL": options!.enableSDL ? 1 : 0
    ]
    
    let registryURL = bottleURL.appendingPathComponent("system.reg")
    let registry = WineRegistryFile(fileURL: registryURL)
    try registry.load()
    if let controllersSection = registry.section(forPath: "System\\\\CurrentControlSet\\\\Services\\\\winebus") {
        regOptionsDictionary.keys.forEach { key in
            let value = regOptionsDictionary[key]!
            console.log("setting \(key) to \(value)")
            controllersSection.setDword(forKey: key, value: value)
        }
        try registry.save()
    } else {
        console.error("\\\\winebus section not found in system.reg file for the bottle \(selectedBottle)")
    }
    
    console.warn("applying config changes to the bottle \(selectedBottle)...")
    
    let bottleName = bottleURL.lastPathComponent
    let bottlePath = bottleURL.path(percentEncoded: false)
    let bottleParentDir = bottleURL.deletingLastPathComponent().path(percentEncoded: false)
    console.warn("attempting to run steam.exe on game id \(id)")
    let arguments = options != nil ? " " + options!.gameArguments : ""
    let x87cxAppURL = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(PATCHED_CX_X87_APPNAME)
    let steamBootOptions = "-nochatui -nofriendsui -silent -no-browser -no-cef-sandbox -skipinitialbootstrap"
    let wineEnvs = "WINEDEBUG=-all CX_BOTTLE_PATH=\"\(bottleParentDir)\" WINEPREFIX=\"\(bottlePath)\" CX_ROOT=\"\(options!.x87PatchEnabled ? x87cxAppURL.path() : absoluteCxPath)/Contents/SharedSupport/CrossOver\" WINEMSYNC=\(options!.wineMSync ? "1" : "0")"
    
    let gameLaunchCommand = appExeURL != nil ? "\"\(appExeURL!.path(percentEncoded: false))\"" : "\"C:\\Program Files (x86)\\Steam\\Steam.exe\" \(steamBootOptions) -applaunch \(String(id))"
    if (options!.x87PatchEnabled) {
        if(!f.fileExists(atPath: x87cxAppURL.path())) {
            console.error("Couldn't find \(x87cxAppURL.path())")
            return
        }
        let workdirCommand = appExeURL != nil ? "cd \"\(appExeURL!.deletingLastPathComponent().path(percentEncoded: false))\" && " : ""
        command = "\(workdirCommand)env \(getInlineEnvs(from: options!, cxAppPath: x87cxAppURL.path()) + wineEnvs) \"\(x87cxAppURL.path())/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine\" \(gameLaunchCommand) \(arguments)"
    } else {
        command = "env \(getInlineEnvs(from: options!, cxAppPath: absoluteCxPath) + wineEnvs) \"\(absoluteCxPath)/Contents/SharedSupport/CrossOver/bin/wine\" --bottle \"\(bottleName)\" \(gameLaunchCommand) \(arguments)"
    }
    
    #if DEBUG
    console.log(command)
    #endif
    try safeShell(command)
}

func launchNativeGame(id: String, cxAppPath: String, selectedBottle: String, options: GameOptions? = nil, appExeURL: URL? = nil) async throws {
    let arguments = options != nil ? " " + options!.gameArguments : ""
    let steamBootOptions = "-nochatui -nofriendsui -silent -no-browser -applaunch"
    var command = ""
    if(appExeURL != nil) {
        command = "env \(getInlineEnvs(from: options!)) open \"\(appExeURL!.path(percentEncoded: false))\" \(arguments)"
    } else {
        command = "env \(getInlineEnvs(from: options!)) /Applications/Steam.app/Contents/MacOS/steam_osx \(steamBootOptions) \(String(id)) \(arguments)"
    }
    console.warn(command)
    try safeShell(command)
}
