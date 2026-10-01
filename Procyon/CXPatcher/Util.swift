//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 03/02/2026.
//

import AppKit
import Foundation

let PATCHED_CX_APPNAME = "Crossover_patched.app"
let PATCHED_CX_X87_APPNAME = "Crossover_patched_x87.app"
let SHARED_SUPPORT_COMPONENT = "Contents/SharedSupport/CrossOver"

/// Snapshots shipped inside the app bundle, used when a component could not be
/// fetched (offline, rate limited, or an unexpected release layout).
private let bundledDXVK: [String] = [
    "dxvk/i386-windows/d3d10core.dll",
    "dxvk/i386-windows/d3d11.dll",
    "dxvk/x86_64-windows/d3d10core.dll",
    "dxvk/x86_64-windows/d3d11.dll",
]

/// Fetches the newest DXMT and DXVK releases and installs them, together with the
/// bundled Wine overlay and D9VK, into a fresh copy of the user's CrossOver app.
///
/// Wine is not fetched: there is no upstream Wine release that is safe to drop
/// into a current CrossOver, so the bundled overlay, which is matched to what
/// this fork ships, is always installed.
@discardableResult
func makeCrossoverPatchedCopy(sourceCXPath: URL, setProgress: @escaping (Double, String) -> Void, setLoading: @escaping (Bool) -> Void, isX87: Bool = false) async -> URL {
    let f = FileManager.default
    let name = isX87 ? PATCHED_CX_X87_APPNAME : PATCHED_CX_APPNAME
    let destUrl = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(name)
    setLoading(true)

    // MARK: Step 1 fetch the latest components, best effort
    let fetchedComponents = PatchComponent.allCases.filter(\.isFetched)
    var fetched: [PatchComponent: URL] = [:]
    for (index, component) in fetchedComponents.enumerated() {
        setProgress(Double(index) / Double(fetchedComponents.count) * 40, "Fetching \(component.displayName)…")
        do {
            fetched[component] = try await ComponentUpdater.prepare(component)
        } catch {
            console.warn("\(component.displayName) download failed, using the bundled snapshot: \(String(reflecting: error))")
        }
    }

    do {
        // Make sure destination app doesn't exist and if it does, delete it
        if (f.fileExists(atPath: destUrl.path())) {
            try f.removeItem(at: destUrl)
        }
        // MARK: Step 2 copy the app in the user's application folder
        setProgress(40, "Copying CrossOver…")
        try f.copyItem(at: sourceCXPath, to: destUrl)

        // MARK: Step 3 install the components
        setProgress(60, "Installing components…")
        for component in fetchedComponents {
            guard let root = fetched[component] else { continue }
            try ComponentUpdater.install(component, from: root, into: destUrl)
        }
        // DXVK only falls back to the bundled snapshot: without it the patched
        // app keeps whatever DXVK CrossOver shipped.
        if fetched[.dxvk] == nil {
            installBundled(dxvk: bundledDXVK, into: destUrl)
        }
        for component in PatchComponent.bundled {
            ComponentUpdater.installBundled(component, into: destUrl)
        }

        // Create cxplog marker
        let marker = destUrl.appendingPathComponent("Contents/cxplog.txt")
        try "Patched by Procyon".write(to: marker, atomically: true, encoding: .utf8)

        setProgress(100.0, "Patch complete!")
        setLoading(false)
        return destUrl
    } catch {
        console.error("makeCrossoverPatchedCopy failed: \(String(reflecting: error))")
        setLoading(false)
        return sourceCXPath
    }
}

private func installBundled(dxvk paths: [String], into app: URL) {
    let f = FileManager.default
    for path in paths {
        let dest = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT + "/lib/" + path)
        guard let source = Bundle.main.url(forResource: path, withExtension: nil) else {
            console.error("Resource file \(path) not found")
            continue
        }
        console.log("copying resource \(path)")
        try? f.removeItem(at: dest)
        try? f.copyItem(at: source, to: dest)
    }
}

@discardableResult
func makeX87CrossoverPatchedCopy(sourceCXPath: URL, patchedApp: URL) async -> URL {
    return await makeCrossoverPatchedCopy(sourceCXPath: sourceCXPath, setProgress: { _, _ in }, setLoading: { _ in }, isX87: true)
}

/// Brings a just-launched game's window to the front.
///
/// `activate(options:)` rather than `.activateAllWindows`: Wine game windows
/// sometimes fail to come forward when every window is asked to activate at
/// once, and a plain activate reliably raises the game.
func activateApp(_ gameName: String) {
    let app = NSWorkspace.shared.runningApplications.first(where: { gameName.contains($0.localizedName ?? "none") })
    console.log("attempting to put your game in the foreground")
    console.log(app?.executableURL?.lastPathComponent ?? app?.localizedName ?? "couldn't get app")
    app?.activate()
}
