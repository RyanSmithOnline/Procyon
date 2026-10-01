//
//  ImageLoader.swift
//  Procyon
//
//  Small async image loader with a two-tier cache.
//
//  Replaces Kingfisher, the heaviest of the three dependencies and the one
//  that mattered most for large libraries: header art for 1000 games is
//  thousands of images, and a shared URLCache alone is not enough.
//

import SwiftUI
import AppKit

/// Decoded-image cache. Requests are coalesced so a thumbnail appearing in
/// several places issues one fetch, and decoding happens off the main actor.
actor ImageCache {
    static let shared = ImageCache()

    private var images: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    /// Below the 1000-game working set so one scroll does not evict everything.
    private let limit = 600

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 12
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )
        return URLSession(configuration: config)
    }()

    func image(for url: URL) async -> NSImage? {
        if let cached = images[url] {
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task<NSImage?, Never> { [session] in
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    console.warn("[ImageCache] http \(http.statusCode) url=\(url.absoluteString)")
                    return nil
                }
                guard let image = NSImage(data: data) else {
                    console.warn("[ImageCache] decode failed url=\(url.absoluteString) scheme=\(url.scheme ?? "nil") bytes=\(data.count)")
                    return nil
                }
                return image
            } catch {
                console.warn("[ImageCache] fetch failed url=\(url.absoluteString) scheme=\(url.scheme ?? "nil") error=\(error)")
                return nil
            }
        }
        inFlight[url] = task
        let loaded = await task.value
        inFlight[url] = nil
        if let loaded {
            images[url] = loaded
            evictIfNeeded()
        }
        return loaded
    }

    private func evictIfNeeded() {
        guard images.count > limit else { return }
        images.removeAll(keepingCapacity: true)
    }

    func count() -> Int { images.count }
}

/// Fetches once, then renders `content` with the image, `placeholder` while
/// loading, or `fallback` if the fetch fails or there is no URL.
struct CachedImage<Content: View, Placeholder: View, Fallback: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let fallback: () -> Fallback

    @State private var image: NSImage?
    @State private var failed: Bool = false

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else if failed {
                fallback()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                failed = true
                return
            }
            failed = false
            image = nil
            let fetched = await ImageCache.shared.image(for: url)
            if let fetched {
                image = fetched
            } else {
                failed = true
            }
        }
    }
}

extension CachedImage where Fallback == Placeholder {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(url: url, content: content, placeholder: placeholder, fallback: placeholder)
    }
}

/// Full-width header art: library tiles, game header, screenshots.
struct HeaderImage: View {
    let url: URL?
    var aspectRatio: CGFloat = 2.15

    var body: some View {
        CachedImage(
            url: url,
            content: { image in
                image
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: .fit)
            },
            placeholder: { ProgressView() },
            fallback: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Circular avatar used by the profile widget.
struct AvatarImage: View {
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        CachedImage(
            url: url,
            content: { image in
                image.resizable().scaledToFit()
            },
            placeholder: { ProgressView() },
            fallback: {
                ZStack {
                    Circle().fill(.quaternary)
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: size * 0.5))
                }
            }
        )
        .mask(Circle())
        .frame(width: size, height: size)
    }
}