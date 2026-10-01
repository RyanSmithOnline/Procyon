//
//  SteamWebAPI.swift
//  Procyon
//
//  Optional Steam Web API support.
//
//  The retired Procyon backend used to return the list of games an account
//  owns, which let the library show owned-but-not-installed games. Valve's
//  public `IPlayerService/GetOwnedGames` endpoint can provide that list, but it
//  needs a (free) Steam Web API key belonging to the account. This file is that
//  client, plus a small Keychain wrapper so the key is never written to a plist.
//

import Foundation
import Security

enum SteamWebAPI {
    /// The Keychain account name the user's API key is stored under.
    static let apiKeyAccount = "steamWebAPIKey"

    static let ownedGamesEndpoint = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"

    static func ownedGamesURL(apiKey: String, steamID: String) -> URL? {
        var components = URLComponents(string: ownedGamesEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamid", value: steamID),
            URLQueryItem(name: "include_appinfo", value: "0"),
            URLQueryItem(name: "include_played_free_games", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }

    /// Returns the app IDs the account owns.
    ///
    /// Throws on failure so callers can fall back to a cached list. A private
    /// profile yields an empty `games` array rather than an error.
    static func fetchOwnedAppIDs(apiKey: String, steamID: String) async throws -> [Int] {
        guard let url = ownedGamesURL(apiKey: apiKey, steamID: steamID) else {
            throw APIError.badURL
        }
        let payload = try await HTTPClient.get(url, as: OwnedGamesResponse.self)
        return (payload.response.games ?? []).map(\.appid)
    }
}

struct OwnedGamesResponse: Decodable {
    let response: OwnedGamesBody
}

struct OwnedGamesBody: Decodable {
    let game_count: Int?
    let games: [OwnedGame]?
}

struct OwnedGame: Decodable {
    let appid: Int
}

/// Minimal generic-password Keychain wrapper.
enum Keychain {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "itmandar.procyon"
    }

    static func set(_ value: String, for account: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
