//
//  SteamStoreAPI.swift
//  Procyon
//
//  Keyless client for Valve's public Steam Store endpoints.
//
//  Replaces the retired Procyon backend (API_HOST / API_KEY / API_PATH), which
//  is no longer reachable. `store.steampowered.com/api/appdetails` is public
//  and needs no credentials, so game metadata comes straight from Valve.
//

import Foundation

enum SteamStore {
    /// Responds with `{ "<appid>": { "success": Bool, "data": { ... } } }`.
    static let appDetailsURL = "https://store.steampowered.com/api/appdetails"

    /// Valve expects an ISO 639-1 code here, e.g. "en", "it", "de".
    static var language: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = preferred.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0) } ?? "en"
        return code.lowercased()
    }

    /// Without a country Valve omits `price_overview` entirely.
    static var countryCode: String {
        Locale.current.region?.identifier ?? "US"
    }
}

/// Valve wraps every app's payload in a per-app-id envelope.
struct StoreAppEnvelope: Decodable {
    let success: Bool
    let data: StoreAppDetails?

    enum CodingKeys: String, CodingKey {
        case success, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.decodeLenientBool(forKey: .success) ?? false
        data = try? c.decodeIfPresent(StoreAppDetails.self, forKey: .data)
    }
}

/// Valve's `appdetails` payload.
///
/// Decoded fail-soft: every field is optional and read through a `try?` helper,
/// so one unexpected field degrades to `nil` instead of failing the whole app
/// and dropping the game from the library. Steam's schema is not stable across
/// apps -- `required_age` arrives as a number or a string, `display_type` as a
/// number, `genres[].id` as a number, the critic score as a float -- so scalars
/// are read through the lenient helpers below.
struct StoreAppDetails: Decodable {
    let type: String?
    let name: String?
    let steamAppID: Int?
    let requiredAge: String?
    let isFree: Bool?
    let controllerSupport: String?
    let dlc: [Int]?
    let detailedDescription: String?
    let aboutTheGame: String?
    let shortDescription: String?
    let supportedLanguages: String?
    let headerImage: String?
    let capsuleImage: String?
    let capsuleImageV5: String?
    let website: String?
    let pcRequirements: Requirements?
    let macRequirements: Requirements?
    let linuxRequirements: Requirements?
    let legalNotice: String?
    let developers: [String]?
    let publishers: [String]?
    let priceOverview: PriceOverview?
    let packages: [Int]?
    let packageGroups: [StorePackageGroup]?
    let platforms: Platforms?
    let metacritic: StoreMetacritic?
    let categories: [Category]?
    let genres: [StoreGenre]?
    let screenshots: [Screenshot]?
    let movies: [Movie]?
    let recommendations: Recommendations?
    let achievements: StoreAchievements?
    let releaseDate: ReleaseDate?
    let supportInfo: SupportInfo?
    let background: String?
    let backgroundRaw: String?
    let contentDescriptors: ContentDescriptors?

    enum CodingKeys: String, CodingKey {
        case type, name
        case steamAppID = "steam_appid"
        case requiredAge = "required_age"
        case isFree = "is_free"
        case controllerSupport = "controller_support"
        case dlc
        case detailedDescription = "detailed_description"
        case aboutTheGame = "about_the_game"
        case shortDescription = "short_description"
        case supportedLanguages = "supported_languages"
        case headerImage = "header_image"
        case capsuleImage = "capsule_image"
        case capsuleImageV5 = "capsule_imagev5"
        case website
        case pcRequirements = "pc_requirements"
        case macRequirements = "mac_requirements"
        case linuxRequirements = "linux_requirements"
        case legalNotice = "legal_notice"
        case developers, publishers
        case priceOverview = "price_overview"
        case packages
        case packageGroups = "package_groups"
        case platforms, metacritic, categories, genres
        case screenshots, movies
        case recommendations, achievements
        case releaseDate = "release_date"
        case supportInfo = "support_info"
        case background
        case backgroundRaw = "background_raw"
        case contentDescriptors = "content_descriptors"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try? c.decode(String.self, forKey: .type)
        name = try? c.decode(String.self, forKey: .name)
        steamAppID = c.decodeLenientInt(forKey: .steamAppID)
        requiredAge = c.decodeIntOrString(forKey: .requiredAge)
        isFree = c.decodeLenientBool(forKey: .isFree)
        controllerSupport = try? c.decode(String.self, forKey: .controllerSupport)
        dlc = try? c.decode([Int].self, forKey: .dlc)
        detailedDescription = try? c.decode(String.self, forKey: .detailedDescription)
        aboutTheGame = try? c.decode(String.self, forKey: .aboutTheGame)
        shortDescription = try? c.decode(String.self, forKey: .shortDescription)
        supportedLanguages = try? c.decode(String.self, forKey: .supportedLanguages)
        headerImage = try? c.decode(String.self, forKey: .headerImage)
        capsuleImage = try? c.decode(String.self, forKey: .capsuleImage)
        capsuleImageV5 = try? c.decode(String.self, forKey: .capsuleImageV5)
        website = try? c.decode(String.self, forKey: .website)
        pcRequirements = try? c.decode(Requirements.self, forKey: .pcRequirements)
        macRequirements = try? c.decode(Requirements.self, forKey: .macRequirements)
        linuxRequirements = try? c.decode(Requirements.self, forKey: .linuxRequirements)
        legalNotice = try? c.decode(String.self, forKey: .legalNotice)
        developers = try? c.decode([String].self, forKey: .developers)
        publishers = try? c.decode([String].self, forKey: .publishers)
        priceOverview = try? c.decode(PriceOverview.self, forKey: .priceOverview)
        packages = try? c.decode([Int].self, forKey: .packages)
        packageGroups = try? c.decode([StorePackageGroup].self, forKey: .packageGroups)
        platforms = try? c.decode(Platforms.self, forKey: .platforms)
        metacritic = try? c.decode(StoreMetacritic.self, forKey: .metacritic)
        categories = try? c.decode([Category].self, forKey: .categories)
        genres = try? c.decode([StoreGenre].self, forKey: .genres)
        screenshots = try? c.decode([Screenshot].self, forKey: .screenshots)
        movies = try? c.decode([Movie].self, forKey: .movies)
        recommendations = try? c.decode(Recommendations.self, forKey: .recommendations)
        achievements = try? c.decode(StoreAchievements.self, forKey: .achievements)
        releaseDate = try? c.decode(ReleaseDate.self, forKey: .releaseDate)
        supportInfo = try? c.decode(SupportInfo.self, forKey: .supportInfo)
        background = try? c.decode(String.self, forKey: .background)
        backgroundRaw = try? c.decode(String.self, forKey: .backgroundRaw)
        contentDescriptors = try? c.decode(ContentDescriptors.self, forKey: .contentDescriptors)
    }
}

/// Valve sends `display_type` as a number on some apps and a string on others.
struct StorePackageGroup: Decodable {
    let name: String?
    let title: String?
    let description: String?
    let selectionText: String?
    let displayType: String?
    let subs: [StorePackageSub]?

    enum CodingKeys: String, CodingKey {
        case name, title, description, subs
        case selectionText = "selection_text"
        case displayType = "display_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decode(String.self, forKey: .name)
        title = try? c.decode(String.self, forKey: .title)
        description = try? c.decode(String.self, forKey: .description)
        selectionText = try? c.decode(String.self, forKey: .selectionText)
        displayType = c.decodeIntOrString(forKey: .displayType)
        subs = try? c.decode([StorePackageSub].self, forKey: .subs)
    }
}

/// `price_in_cents_with_discount` is absent on free licences.
struct StorePackageSub: Decodable {
    let packageID: Int?
    let optionText: String?
    let isFreeLicense: Bool?
    let priceInCentsWithDiscount: Int?

    enum CodingKeys: String, CodingKey {
        case optionText = "option_text"
        case isFreeLicense = "is_free_license"
        case priceInCentsWithDiscount = "price_in_cents_with_discount"
        case packageID = "packageid"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packageID = c.decodeLenientInt(forKey: .packageID)
        optionText = try? c.decode(String.self, forKey: .optionText)
        isFreeLicense = c.decodeLenientBool(forKey: .isFreeLicense)
        priceInCentsWithDiscount = c.decodeLenientInt(forKey: .priceInCentsWithDiscount)
    }
}

/// Valve sends the critic score as a JSON number that is not always integral.
struct StoreMetacritic: Decodable {
    let score: Double?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case score, url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(Double.self, forKey: .score) {
            score = s
        } else if let i = try? c.decode(Int.self, forKey: .score) {
            score = Double(i)
        } else {
            score = nil
        }
        url = try? c.decode(String.self, forKey: .url)
    }
}

/// Valve sends genre ids as numbers; `Genre` models them as strings.
struct StoreGenre: Decodable {
    let id: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case id, description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeIntOrString(forKey: .id) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
    }
}

/// Valve omits `highlighted` on apps with no spotlighted achievements.
struct StoreAchievements: Decodable {
    let total: Int?
    let highlighted: [Achievement]?
}

extension KeyedDecodingContainer {
    func decodeLenientInt(forKey key: Key) -> Int? {
        if let v = try? decode(Int.self, forKey: key) { return v }
        if let v = try? decode(Double.self, forKey: key) { return Int(v.rounded()) }
        if let v = try? decode(String.self, forKey: key) { return Int(v) }
        return nil
    }

    func decodeIntOrString(forKey key: Key) -> String? {
        if let v = decodeLenientInt(forKey: key) { return String(v) }
        if let v = try? decode(String.self, forKey: key) { return v }
        if let v = try? decode(Double.self, forKey: key) {
            return v == v.rounded() ? String(Int(v)) : String(v)
        }
        return nil
    }

    func decodeLenientBool(forKey key: Key) -> Bool? {
        if let v = try? decode(Bool.self, forKey: key) { return v }
        if let v = try? decode(Int.self, forKey: key) { return v != 0 }
        if let v = try? decode(String.self, forKey: key) {
            switch v.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}

extension SteamGame {
    /// Builds the app's `SteamGame` from a Valve store payload.
    ///
    /// Returns `nil` when Valve has no name for the app. Fields the UI reads
    /// are guaranteed non-empty; everything else degrades to `nil`.
    init?(store: StoreAppDetails, appID: String) {
        guard let name = store.name else { return nil }
        self.type = store.type ?? "game"
        self.name = name
        self.steamAppID = store.steamAppID ?? Int(appID) ?? 0
        self.requiredAge = store.requiredAge ?? "0"
        self.isFree = store.isFree ?? false
        self.controllerSupport = store.controllerSupport
        self.dlc = store.dlc
        self.detailedDescription = store.detailedDescription ?? store.shortDescription ?? ""
        self.aboutTheGame = store.aboutTheGame ?? store.detailedDescription ?? ""
        self.shortDescription = store.shortDescription ?? ""
        self.supportedLanguages = store.supportedLanguages
        self.headerImage = store.headerImage ?? ""
        self.capsuleImage = store.capsuleImage ?? ""
        self.capsuleImageV5 = store.capsuleImageV5
        self.website = store.website
        self.pcRequirements = store.pcRequirements
        self.macRequirements = store.macRequirements
        self.linuxRequirements = store.linuxRequirements
        self.legalNotice = store.legalNotice
        self.developers = store.developers
        self.publishers = store.publishers
        self.priceOverview = store.priceOverview
        self.packages = store.packages
        self.packageGroups = store.packageGroups.map { groups in
            groups.map { g in
                PackageGroup(
                    name: g.name ?? "",
                    title: g.title ?? "",
                    description: g.description ?? "",
                    selectionText: g.selectionText ?? "",
                    displayType: g.displayType ?? "",
                    subs: (g.subs ?? []).map { s in
                        PackageSub(
                            packageID: s.packageID ?? 0,
                            optionText: s.optionText ?? "",
                            isFreeLicense: s.isFreeLicense ?? false,
                            priceInCentsWithDiscount: s.priceInCentsWithDiscount ?? 0)
                    })
            }
        }
        self.platforms = store.platforms ?? Platforms(windows: true, mac: false, linux: false)
        self.metacritic = store.metacritic.map {
            Metacritic(score: $0.score.map { Int($0.rounded()) }, url: $0.url)
        }
        self.categories = store.categories
        self.genres = store.genres.map { $0.map { Genre(id: $0.id, description: $0.description) } }
        self.screenshots = store.screenshots
        self.movies = store.movies
        self.recommendations = store.recommendations
        self.achievements = store.achievements.map {
            Achievements(total: $0.total ?? 0, highlighted: $0.highlighted ?? [])
        }
        self.releaseDate = store.releaseDate ?? ReleaseDate(comingSoon: false, date: "")
        self.supportInfo = store.supportInfo
        self.background = store.background
        self.backgroundRaw = store.backgroundRaw
        self.contentDescriptors = store.contentDescriptors
        // `appdetails` only reports Steam Deck support under `ratings`, which
        // `RatingBody` (esrb/pegi/usk age ratings) cannot represent.
        self.ratings = nil
    }
}
// MARK: - Community profile

/// Keyless profile data from Steam's public community XML endpoint.
///
/// `https://steamcommunity.com/profiles/<id>/?xml=1` is public and needs no
/// key, so it restores the name, avatar and account age that the retired
/// backend used to return. Profiles that are private return a reduced
/// document; when the fields the UI needs are missing this returns `nil` and
/// callers fall back to the local `loginusers.vdf` data.
enum SteamCommunity {
    static func profileURL(steamID: String) -> URL? {
        URL(string: "https://steamcommunity.com/profiles/\(steamID)/?xml=1")
    }

    static let memberSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    static func personaState(fromOnlineState state: String) -> Int {
        switch state.lowercased() {
        case "online": return 1
        case "in-game": return 1
        case "busy": return 2
        case "away": return 3
        case "snooze": return 4
        case "looking to trade": return 5
        case "looking to play": return 6
        default: return 0
        }
    }

    static func fetchProfile(steamID: String) async -> UserInfo? {
        guard let url = profileURL(steamID: steamID),
              let data = try? await HTTPClient.get(url, retryLimit: 2),
              let doc = try? XMLDocument(data: data, options: []) else {
            return nil
        }

        func value(_ xpath: String) -> String? {
            guard let node = try? doc.nodes(forXPath: xpath).first else { return nil }
            let text = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty ?? true) ? nil : text
        }

        guard let personaName = value("//steamID"),
              let avatar = value("//avatarMedium") ?? value("//avatarIcon") else {
            return nil
        }
        let avatarFull = value("//avatarFull") ?? avatar
        let resolvedID = value("//steamID64") ?? steamID
        let privacyState = value("//privacyState")?.lowercased()
        let visibility = Int(value("//visibilityState") ?? "")
            ?? (privacyState == "public" ? 3 : 1)
        let memberSince = value("//memberSince")
        let created = memberSince.flatMap { memberSinceFormatter.date(from: $0) }

        return UserInfo(
            steamID: resolvedID,
            communityVisibilityState: visibility,
            profileState: privacyState == "public" ? 1 : 0,
            personaName: personaName,
            profileURL: "https://steamcommunity.com/profiles/\(resolvedID)",
            avatar: avatar,
            avatarMedium: avatar,
            avatarFull: avatarFull,
            avatarHash: "",
            lastLogOff: nil,
            personaState: personaState(fromOnlineState: value("//onlineState") ?? ""),
            primaryClanID: value("//primaryClanID") ?? "",
            timeCreated: created.map { Int($0.timeIntervalSince1970) } ?? 0,
            personaStateFlags: 0,
            locCountryCode: nil,
            locStateCode: nil
        )
    }
}
