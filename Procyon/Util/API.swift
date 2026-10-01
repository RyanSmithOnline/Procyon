//
//  API.swift
//  Procyon
//
//  Game metadata retrieval.
//
//  Talks to Valve's public, keyless Steam Store endpoints (see
//  SteamStoreAPI.swift). The previous Procyon backend (API_HOST / API_KEY)
//  is gone, so there is no server to depend on.
//

import Foundation

enum APIError: Error {
    case badURL
}

final class SteamAPI: @unchecked Sendable {
    var progress: Double = 0

    private var cacheBlacklist: [String] = BLACKLIST
    private var cache: [String: SteamGame] = [:]
    private let lock = NSLock()

    private var cacheBlacklistURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ProcyonSteamCacheBlacklist.plist")
    }
    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ProcyonSteamCache.plist")
    }

    /// Caches written by builds that still talked to the retired backend.
    /// Nothing reads them any more, so they are deleted once at startup rather
    /// than left behind on upgraded installs.
    private static let legacyCacheNames = [
        "ProcyonSteamProfileDataCache.plist",
        "ProcyonSteamOwnedGamesIDsCache.plist",
    ]

    private func removeLegacyBackendCaches() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        for name in Self.legacyCacheNames {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private func loadCache() {
        console.log("Loading caches...")
        self.removeLegacyBackendCaches()
        self.loadGameCache()
        self.loadBlacklistCache()
    }

    init() {
        self.loadCache()
        if self.cache.isEmpty {
            console.warn("Cache is empty")
        }
        if self.cacheBlacklist.isEmpty {
            console.warn("Blacklist Cache is empty")
        }
    }

    // MARK: - Persistence

    private func loadGameCache() {
        do {
            let data = try Data(contentsOf: cacheURL)
            self.cache = try JSONDecoder().decode([String: SteamGame].self, from: data)
            if !self.cache.isEmpty {
                console.warn("Cache loaded: \(self.cache.count) games")
            }
        } catch {
            console.log("No game cache yet, will fetch from the store")
        }
    }

    /// Written once per library load rather than once per game: with a 1000-game
    /// library the per-game write re-serialised the whole cache 1000 times.
    private func saveGameCache() {
        do {
            let encoded = try JSONEncoder().encode(self.cache)
            try encoded.write(to: self.cacheURL, options: [.atomic])
            console.warn("Cache saved: \(self.cache.count) games")
        } catch {
            console.error(String(reflecting: error))
        }
    }

    func deleteGameCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        self.cache.removeAll()
        console.warn("Cache deleted")
    }

    private func loadBlacklistCache() {
        do {
            let data = try Data(contentsOf: cacheBlacklistURL)
            self.cacheBlacklist = try JSONDecoder().decode([String].self, from: data)
            if !self.cacheBlacklist.isEmpty {
                console.warn("Blacklist Cache loaded: \(self.cacheBlacklist.count)")
            }
        } catch {
            console.log("No blacklist cache yet")
        }
    }

    private func saveBlacklistCache() {
        do {
            let encoded = try JSONEncoder().encode(self.cacheBlacklist)
            try encoded.write(to: self.cacheBlacklistURL, options: [.atomic])
            console.warn("Blacklist cache saved")
        } catch {
            console.error(String(reflecting: error))
        }
    }

    func deleteBlacklistCache() {
        try? FileManager.default.removeItem(at: cacheBlacklistURL)
        self.cacheBlacklist.removeAll()
        console.warn("Blacklist Cache deleted")
    }

    // MARK: - Cache access

    private func isBlacklisted(_ appID: String) -> Bool {
        lock.withLock { cacheBlacklist.contains(appID) }
    }

    private func cachedGame(_ appID: String) -> SteamGame? {
        lock.withLock { cache[appID] }
    }

    private func storeInCache(_ appID: String, _ game: SteamGame) {
        lock.withLock { cache[appID] = game }
    }

    private func addToBlacklist(_ appID: String) {
        lock.withLock {
            guard !cacheBlacklist.contains(appID) else { return }
            cacheBlacklist.append(appID)
        }
    }

    // MARK: - Fetching

    /// Fetches store metadata for one app.
    ///
    /// - Throws: `HTTPError.throttled` when Steam rate-limits us. Callers must
    ///   not treat that as "this game has no store page" — it's temporary, so
    ///   it must not be blacklisted.
    func fetchGameInfo(appID: String) async throws -> SteamGame? {
        if isBlacklisted(appID) {
            console.log("skipping \(appID) as it's blacklisted")
            return nil
        }
        if let cached = cachedGame(appID) {
            console.cache(appID, key: "gameCache")
            return cached
        }
        guard var components = URLComponents(string: SteamStore.appDetailsURL) else {
            throw APIError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "appids", value: appID),
            URLQueryItem(name: "l", value: SteamStore.language),
            URLQueryItem(name: "cc", value: SteamStore.countryCode)
        ]
        guard let url = components.url else {
            throw APIError.badURL
        }
        console.log("fetching \(appID) from the steam store")
        let payload = try await HTTPClient.get(url, as: [String: StoreAppEnvelope].self)
        guard let envelope = payload[appID], envelope.success, let details = envelope.data else {
            console.warn("Game with id: \(appID) has no store page, blacklisting")
            addToBlacklist(appID)
            return nil
        }
        guard let game = SteamGame(store: details, appID: appID) else {
            return nil
        }
        storeInCache(appID, game)
        return game
    }

    /// Builds the game list, emitting each game as soon as it resolves so the
    /// grid fills in progressively instead of blocking on the slowest game.
    ///
    /// Cached games resolve instantly and never touch the network, so a warm
    /// start paints the whole library at once.
    func fetchGamesInfo(
        meta: [GamesMeta],
        onGame: @escaping @MainActor @Sendable (Game) async -> Void = { _ in },
        setProgress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws -> [Game] {
        let total = meta.count
        guard total > 0 else {
            setProgress(100)
            return []
        }
        self.progress = 0
        await setProgress(0)

        // Written only by this (single) task in group-child order, so the
        // result array needs no lock.
        var items = [Game?](repeating: nil, count: total)
        var completed = 0

        // Games that failed because Steam rate-limited us, retried once the
        // pacer has recovered. Dropping them instead would silently shrink the
        // library whenever a big fetch trips throttling.
        var throttled: [(original: Int, meta: GamesMeta)] = []

        /// - Parameter slots: indices into `items` that these fetches fill.
        func drain(_ work: [(original: Int, meta: GamesMeta)]) async {
            let window = await RequestPacer.shared.window
            await withTaskGroup(of: (Int, Outcome).self) { group in
                var next = 0
                func addNext() {
                    guard next < work.count else { return }
                    let slot = next
                    next += 1
                    let entry = work[slot]
                    group.addTask {
                        (slot, await self.buildGame(from: entry.meta))
                    }
                }
                for _ in 0..<max(1, min(window, work.count)) { addNext() }
                while let (slot, outcome) = await group.next() {
                    let original = work[slot].original
                    switch outcome {
                    case .game(let game):
                        items[original] = game
                        await onGame(game)
                    case .unavailable:
                        break
                    case .throttled:
                        throttled.append((original, work[slot].meta))
                    }
                    completed += 1
                    self.progress = Double(completed) / Double(total) * 100.0
                    await setProgress(min(self.progress, 100))
                    addNext()
                }
            }
        }

        await drain(meta.enumerated().map { ($0.offset, $0.element) })

        if !throttled.isEmpty {
            console.warn("Rate limited; retrying \(throttled.count) games after a pause")
            // Give the CDN time to lift the block before spending more requests.
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            completed = 0
            let retry = throttled
            throttled = []
            await drain(retry)
            if !throttled.isEmpty {
                console.warn("\(throttled.count) games still rate limited; they will appear after the next refresh")
            }
        }

        self.progress = 100
        await setProgress(100)

        let built = items.compactMap { $0 }
        console.cacheRelease("The following game's data cache was used", key: "gameCache")
        saveGameCache()
        saveBlacklistCache()
        console.log("Library ready: \(built.count)/\(total) games")
        return built
    }

    /// Why a single game fetch ended the way it did.
    private enum Outcome {
        case game(Game)
        /// No store page exists. Permanently uninteresting, so it is cached as
        /// blacklisted to avoid re-asking on every launch.
        case unavailable
        /// Temporary: we were rate limited. Worth retrying later.
        case throttled
    }

    /// Builds one `Game`, swallowing per-game failures so a single bad app can
    /// never abort the whole library load.
    private func buildGame(from item: GamesMeta) async -> Outcome {
        let bDownloaded = Double(item.BytesDownloaded ?? "0") ?? 0
        let bToDownload = Double(item.BytesToDownload ?? "0") ?? 0
        let downloadProgress: Double = item.isDownloaded()
            ? 100
            : (bToDownload > 0 ? (bDownloaded / bToDownload) * 100 : 0)
        do {
            guard let gameInfo = try await fetchGameInfo(appID: item.appid) else {
                return .unavailable
            }
            return .game(Game(
                from: gameInfo,
                id: item.id,
                isNative: item.isNative,
                downloadProgress: downloadProgress,
                isInstalled: !item.installdir.isEmpty,
                appNames: []
            ))
        } catch let error as HTTPError {
            // Rate limiting is temporary, so it must not blacklist the app or
            // count as "no store page" — the retry pass picks these back up.
            if case .throttled(let status, _) = error {
                console.warn("Game \(item.appid) deferred: HTTP \(status)")
                return .throttled
            }
            console.warn("Game with id: \(item.appid) failed gracefully")
            console.error(String(reflecting: error))
            return .unavailable
        } catch {
            console.warn("Game with id: \(item.appid) failed gracefully")
            console.error(String(reflecting: error))
            return .unavailable
        }
    }
}