//
//  ProfileWidget.swift
//  Procyon
//
//  Created by Italo Mandara on 03/03/2026.
//

import SwiftUI

struct ProfileWidget: View {
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var isLoading: Bool = true
    @State private var profileData: UserInfo? = nil
    @State private var showProfile: Bool = false
    
    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                ProgressView().scaleEffect(0.5)
            } else if let p = profileData {
                Button {
                    showProfile = true
                } label: {
                    HStack {
                        AvatarImage(url: URL(string: p.avatar))
                        Text(p.personaName).lineLimit(1)
                    }.frame(maxWidth: 150, alignment: .init(horizontal: .leading, vertical: .center))
                }
                .buttonStyle(.plain)
            } else {
                if let bottlePath = URL(string: appGlobals.selectedBottle) {
                    if let fallbackProfileData = getSteamUserDataFallback(usingBottlePath: bottlePath) {
                        HStack {
                            AvatarImage(url: URL(string: fallbackProfileData.avatar))
                            Text(fallbackProfileData.personaName).lineLimit(1)
                        }.frame(maxWidth: 150, alignment: .init(horizontal: .leading, vertical: .center))
                    }
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            Modal("Steam profile", showModal: $showProfile) {
                VStack() {
                    if isLoading {
                        VStack {
                            ProgressView("Loading profile…")
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else if let p = profileData {
                        let lastLogOff = (p.lastLogOff ?? 0) > 0
                            ? Date(timeIntervalSince1970: Double(p.lastLogOff!)).formatted()
                            : "Unknown"
                        let timeCreated = p.timeCreated > 0
                            ? Date(timeIntervalSince1970: Double(p.timeCreated)).formatted()
                            : "Unknown"
                        let visibility = [3: "Public", 1: "Private"][p.communityVisibilityState] ?? "Unknown"
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack {
                                    AvatarImage(url: URL(string: p.avatarFull), size: 150)
                                        .frame(maxWidth: .infinity)
                                }
                                .frame(width: 82, height: 82)
                                .cornerRadius(20)
                                .padding(.trailing, 10)
                                VStack (alignment: .leading){
                                    HStack (alignment: .bottom){
                                        Text(p.personaName).font(.largeTitle)
                                        if (p.locCountryCode != nil){
                                            Flag(countryCode: p.locCountryCode!).font(.largeTitle)
                                        }
                                    }
                                    HStack {
                                        Tag(visibility)
                                        Tag(mapPersonaState(p.personaState))
                                    }
                                }
                            }.padding(.bottom)
                            if (p.profileState == 1){
                                Text("Community profile configured")
                                Text("A \"Steam Community profile configured\" means you have completed the initial setup of your profile, enabling you to use social features like adding friends, posting in hubs, and trading. It requires setting up an avatar, username, and often, spending at least $5.00 USD to unlock features from \"limited account\" status.").font(.footnote)
                            } else {
                                Text("Community profile needs to be configured")
                                Text("This means you haven't completed the initial setup of your profile, at the moment you can't use social features like adding friends, posting in hubs, and trading. To configure it, set up an avatar, username, and often, spending at least $5.00 USD will unlock your status.").font(.footnote)
                            }
                            
                            Text("Steam ID: \n\(p.steamID)")
                            Text("Profile URL: \n\(p.profileURL)")
                            //                    Text("avatarHash: \(p.avatarHash)")
                            //                    Text("primaryClanID: \(p.primaryClanID)")
                            Text("Account created on: \n\(timeCreated)")
                            Text("Last Time you logged off: \n\(lastLogOff)")
                            //                    Text("personaStateFlags: \(p.personaStateFlags)")
                            //                    Text("locStateCode: \(p.locStateCode ?? "-")")
                            Spacer()
                            VStack(alignment: .leading) {
                                ProminentButton("Refresh Profile", systemImage: "arrow.clockwise") {
                                    isLoading = true
                                    Task(priority: .background){
                                        await load()
                                    }
                                }
                            }.padding(.top)
                        }
                        .padding(.vertical)
                        .cornerRadius(20)
                    } else {
                        Text("No profile data")
                    }
                }.frame(width: 500, height: 450, alignment: .center)
            }
        }
        .onAppear(perform: {
            Task(priority: .background) {
                await load()
            }
        })
    }
    
    @MainActor
    private func load() async {
        defer {
            isLoading = false
        }
        guard let bottlePath = URL(string: appGlobals.selectedBottle),
              let local = getSteamUserDataFallback(usingBottlePath: bottlePath) else {
            profileData = nil
            console.error("Couldn't read the profile from loginusers.vdf")
            return
        }
        // Prefer Steam's public community profile, which has the real avatar
        // and account age; fall back to the local loginusers.vdf data when
        // offline or when the profile is private.
        if let remote = await SteamCommunity.fetchProfile(steamID: local.steamID) {
            profileData = remote
            console.log("Profile loaded from Steam community (\(remote.personaName))")
        } else {
            profileData = local
            console.log("Profile loaded from local loginusers.vdf (\(local.personaName))")
        }
    }
}



#Preview {
    ProfileWidget()
}
