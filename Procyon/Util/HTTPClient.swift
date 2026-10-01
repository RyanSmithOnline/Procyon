//
//  HTTPClient.swift
//  Procyon
//
//  Minimal async HTTP helper built on URLSession.
//
//  Replaces Alamofire.
//
//  Two things matter here beyond plain requests:
//
//  1. Bounded-concurrency fan-out, so a 1000-game library loads in tens of
//     seconds instead of minutes.
//  2. Adaptive throttling. Steam fronts the Store API with Akamai, which
//     answers bursts of requests with HTTP 403 (not just 429). Hammering it
//     hard enough gets the whole client IP blocked for a while. So the client
//     paces itself, and backs off hard when it sees a 403 or 429.
//

import Foundation

enum HTTPError: Error, LocalizedError {
    case badURL
    case invalidResponse
    case httpStatus(Int)
    /// The server told us to slow down. Recoverable, unlike other statuses.
    case throttled(status: Int, retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Could not build the request URL"
        case .invalidResponse:
            return "The server returned an invalid response"
        case .httpStatus(let code):
            return "The server returned HTTP \(code)"
        case .throttled(let status, let retryAfter):
            if let retryAfter {
                return "Rate limited (HTTP \(status)); retrying in \(Int(retryAfter))s"
            }
            return "Rate limited (HTTP \(status))"
        }
    }

    /// Whether trying the same request again later is worth it.
    var isRetryable: Bool {
        switch self {
        case .throttled:
            return true
        case .badURL, .invalidResponse:
            return false
        case .httpStatus(let code):
            return (500..<600).contains(code)
        }
    }
}

/// Paces requests and reacts to throttling by narrowing the window.
///
/// Deliberately an actor: the pacing decision is shared mutable state, and
/// this is the only place that keeps it.
actor RequestPacer {
    static let shared = RequestPacer()

    private var currentWindow: Int
    private let minWindow = 2
    private let maxWindow = 12
    /// Seconds to wait before issuing the next request.
    private var interval: TimeInterval
    private let minInterval: TimeInterval = 0.05
    private var nextAllowed = Date.distantPast

    init(window: Int = 6, interval: TimeInterval = 0.08) {
        self.currentWindow = window
        self.interval = interval
    }

    /// Blocks until the pacer allows another request.
    func wait() async {
        let now = Date()
        if nextAllowed > now {
            let delay = nextAllowed.timeIntervalSince(now)
            nextAllowed = nextAllowed.addingTimeInterval(interval)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } else {
            nextAllowed = now.addingTimeInterval(interval)
        }
    }

    /// Called after every response. A throttle halves throughput; sustained
    /// success slowly gives it back, so one 403 doesn't permanently cripple a
    /// large library load.
    func record(status: Int) {
        switch status {
        case 403, 429:
            currentWindow = max(minWindow, currentWindow / 2)
            interval = min(2.0, interval * 2 + 0.25)
        case 200..<300:
            if currentWindow < maxWindow {
                currentWindow += 1
            }
            interval = max(minInterval, interval * 0.9)
        default:
            break
        }
    }

    /// Asks callers to wait at least this long after a throttle response.
    func penalty(for status: Int, retryAfter: TimeInterval?) -> TimeInterval {
        record(status: status)
        return max(retryAfter ?? 0, interval * 4)
    }

    var window: Int { currentWindow }
}

enum HTTPClient {
    /// One shared pool for every request. `URLSession` is thread-safe, and a
    /// single instance is what lets 1000 games reuse connections instead of
    /// opening a new one per fetch.
    nonisolated(unsafe) private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 12
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        return URLSession(configuration: config)
    }()

    /// Server-suggested wait, from `Retry-After` or a delay estimate.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(header) {
            return seconds
        }
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let date = HTTPDateParser.formatter.date(from: header) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    /// GET returning decoded JSON. Retries throttled and transient failures.
    static func get<T: Decodable>(
        _ url: URL,
        as type: T.Type,
        retryLimit: Int = 4,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await get(url, retryLimit: retryLimit)
        return try decoder.decode(type, from: data)
    }

    /// GET returning raw bytes. Retries throttled and transient failures.
    @discardableResult
    static func get(_ url: URL, retryLimit: Int = 4) async throws -> Data {
        var attempt = 0
        var delay: TimeInterval = 0.5

        while true {
            await RequestPacer.shared.wait()
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw HTTPError.invalidResponse
                }

                await RequestPacer.shared.record(status: http.statusCode)

                if (200..<300).contains(http.statusCode) {
                    return data
                }

                // Akamai answers abusive bursts with 403, and Steam itself uses
                // 429. Both mean "slow down", so both get the same treatment.
                if http.statusCode == 403 || http.statusCode == 429 {
                    guard attempt < retryLimit else {
                        throw HTTPError.throttled(
                            status: http.statusCode,
                            retryAfter: retryAfter(from: http)
                        )
                    }
                    let wait = await RequestPacer.shared.penalty(
                        for: http.statusCode,
                        retryAfter: retryAfter(from: http)
                    )
                    try await Task.sleep(nanoseconds: UInt64(max(wait, delay) * 1_000_000_000))
                    delay = min(delay * 2, 8)
                    attempt += 1
                    continue
                }

                if (500..<600).contains(http.statusCode), attempt < retryLimit {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * 2, 8)
                    attempt += 1
                    continue
                }

                throw HTTPError.httpStatus(http.statusCode)
            } catch let error as HTTPError {
                // A throttle that outlived its retries is still retryable, just
                // later; surfacing it as such keeps callers from caching a
                // transient block as a permanent "no store page".
                throw error
            } catch {
                if attempt < retryLimit,
                   let urlError = error as? URLError,
                   urlError.isTransientNetworkError {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * 2, 8)
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }
}

enum HTTPDateParser {
    /// RFC 1123, the format used by the `Retry-After` HTTP-date form.
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}

extension URLError {
    var isTransientNetworkError: Bool {
        switch code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost,
             .networkConnectionLost, .dnsLookupFailed,
             .notConnectedToInternet, .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}