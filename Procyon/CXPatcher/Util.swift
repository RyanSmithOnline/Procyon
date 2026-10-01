//
//  Util.swift
//  CXPatcher
//
//  Created by Italo Mandara on 03/02/2026.
//

import Foundation

let PATCHED_CX_APPNAME = "Crossover_patched.app"
let PATCHED_CX_X87_APPNAME = "Crossover_patched_x87.app"
let SHARED_SUPPORT_COMPONENT = "Contents/SharedSupport/CrossOver"

let WINE_DXVK_RESOURCES_PATHS: [String] = [
    "dxvk/i386-windows/d3d10core.dll",
    "dxvk/i386-windows/d3d11.dll",
    "dxvk/x86_64-windows/d3d10core.dll",
    "dxvk/x86_64-windows/d3d11.dll",
]

private let dxvkRes: [(res: String, dest: String)] = WINE_DXVK_RESOURCES_PATHS.map { path in
    (res: path, dest: "/lib/" + path)
}

private let allResources = dxvkRes + [
    (res: "d9vk/x32/d3d9.dll", dest: "/lib/wine/i386-windows/d3d9.dll"),
    (res: "d9vk/x64/d3d9.dll", dest: "/lib/wine/x86_64-windows/d3d9.dll"),
]

@discardableResult
func makeCrossoverPatchedCopy(sourceCXPath: URL, setProgress: @escaping (Double, String) -> Void, setLoading: @escaping (Bool) -> Void, isX87: Bool = false) async -> URL {
    let f = FileManager.default
    let name = isX87 ? PATCHED_CX_X87_APPNAME : PATCHED_CX_APPNAME
    let destUrl = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(name)
    let resources = allResources
        .map { item in
            (res: item.res, dest: destUrl.appendingPathComponent(SHARED_SUPPORT_COMPONENT + item.dest))
        }
    do {
        // Make sure destination app doesn't exist and if it does, delete it
        if (f.fileExists(atPath: destUrl.path())) {
            try f.removeItem(at: destUrl)
        }
        // MARK: Step 1 copy the app in the user's application folder
        try f.copyItem(at: sourceCXPath, to: destUrl)
        
        // MARK: Step 2 copy resources into place
        resources.forEach { resource in
            if let resUrl = Bundle.main.url(forResource: resource.res, withExtension: nil) {
                console.log("copying resource \(resource.res)")
                try? f.removeItem(at: resource.dest)
                try? f.copyItem(at: resUrl, to: resource.dest)
            } else {
                console.error("Resource file \(resource.res) not found")
            }
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

@discardableResult
func makeX87CrossoverPatchedCopy(sourceCXPath: URL, patchedApp: URL) async -> URL {
    return await makeCrossoverPatchedCopy(sourceCXPath: sourceCXPath, setProgress: { _, _ in }, setLoading: { _ in }, isX87: true)
}
