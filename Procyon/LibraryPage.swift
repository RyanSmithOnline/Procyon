//
//  LibraryPage.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import Combine

struct LibraryPage: View {
    @StateObject var libraryPageGlobals = LibraryPageGlobals()
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var selectedGame: SteamGame? = nil
    @State private var mntObserver: MountObserver?
    
    var body: some View {
        ZStack {
            if(libraryPageGlobals.isLaunchingGame) {
                VStack {
                    ProgressView(label: {
                        Text("Launching \(libraryPageGlobals.selectedGame?.name ?? "'Unknown'")...")
                    })
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .background {
                        if (libraryPageGlobals.selectedGame?.headerImage != nil){
                            CachedImage(
                                url: URL(string: libraryPageGlobals.selectedGame!.headerImage),
                                content: { image in image.resizable().scaledToFill() },
                                placeholder: { Color.clear }
                            )
                            .blur(radius: 10)
                            .opacity(0.4)
                        }
                    }
                }
                .background(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity).zIndex(10)
            }
            
            VStack {
                if (errorMessage != nil) {
                    Text("Error: \(errorMessage!)")
                        .lineLimit(1)
                        .foregroundStyle(.red)
                } else if (!isLoading && libraryPageGlobals.gamesMeta.isEmpty) {
                    VStack {
                        ContentUnavailableView {
                            Label("No Libraries found", systemImage: "gamecontroller")
                                .padding(.bottom)
                        } description: {
                            Text("No Steam libraries found.\nPlease add a Steam library folder.")
                            Button {
                                libraryPageGlobals.showOptions = true
                            } label: {
                                Label("Add Library", systemImage: "plus")
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    GamesList(load: load)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $libraryPageGlobals.showOptions) {
                OptionsView(load: load)
            }
            .sheet(isPresented: $libraryPageGlobals.showDetailView) {
                Modal(showModal: $libraryPageGlobals.showDetailView, collapse: true, content:  {
                    GameDetailView(game: $libraryPageGlobals.selectedGame)
                })
            }
            .overlay {
                if (isLoading) {
                    HStack(alignment: .bottom) {
                        HStack(alignment: .center) {
                            Image(.procyon).resizable()
                                .scaledToFit()
                                .frame(height: 50)
                            VStack (alignment: .leading){
                                Text("Loading your library…")
                                    .font(.footnote)
                                    .foregroundStyle(.white)
                                ProgressView(value: progress, total: 100)
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: .infinity, maxHeight: 5)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 220, height: 60)
                        .background(.accent.mix(with: .black, by: 0.6).opacity(0.9))
                        .cornerRadius(20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding()
                    .transition(.opacity)
                }
            }
            .onAppear() {
                isLoading = true // fixes missing library issue
                try? stripEnvsInCXBottleConfigFile(selectedBottle: appGlobals.selectedBottle)
                Task(priority: .background) {
                    await load()
                }
                mntObserver = MountObserver(
                    onMount: {
                        Task(priority: .background) {
                            await load()
                        }
                    },
                    onUnmount: {
                        Task(priority: .background) {
                            await load()
                        }
                    }
                )
            }
            .onDisappear {
                mntObserver = nil
            }
            .environmentObject(libraryPageGlobals)
        }
    }
    
    @MainActor
    private func load() async {
        isLoading = true
        defer {
            Task {
                isLoading = false
            }
        }
        progress = 0
        libraryPageGlobals.gamesMeta.removeAll()
        libraryPageGlobals.gamesMetaIndex.removeAll()
        libraryPageGlobals.folders = getSteamFolderPaths()
        if libraryPageGlobals.folders.isEmpty {
            console.warn("There are no folders to scan.")
        } else {
            for folder in libraryPageGlobals.folders {
                let folderURL = URL(string: folder)!
                if libraryPageGlobals.gamesMeta.contains(where: { $0.libraryFolder == folderURL }) {
                    console.log("skipping gamesMeta processing")
                    return // in memory cache just in case you disconnect/reconnect an external drive that has been scanned already
                }
                do {
                    let foldergamesMeta = try getGamesMeta(from: folderURL)
                    libraryPageGlobals.gamesMeta.append(contentsOf: foldergamesMeta)
                } catch {
                    console.error(String(reflecting: error))
                }
            }
        }
        // One index build instead of a per-thumbnail linear scan.
        libraryPageGlobals.gamesMetaIndex = Dictionary(
            libraryPageGlobals.gamesMeta.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // The library is built from the local appmanifest_*.acf files above, so
        // it only ever contains installed games. Games have to be installed
        // from Steam itself.
        do {
            // Games appear as each one resolves rather than after the slowest
            // fetch, so the grid is browsable while a big library loads.
            // `seen` is a Set so the dedupe check stays O(1) instead of making
            // the progressive path O(n^2) across a 1000-game library.
            var seen = Set<String>()
            let fetched = try await api.fetchGamesInfo(
                meta: libraryPageGlobals.gamesMeta,
                onGame: { game in
                    if seen.insert(game.id).inserted {
                        libraryPageGlobals.addGame(game)
                    }
                },
                setProgress: { self.progress = $0 }
            )
            libraryPageGlobals.setGames(fetched)
            progress = 100
        } catch {
            console.error("fetchGamesInfo \(String(reflecting: error))")
        }
    }
}

#Preview {
    ContentView()
}

