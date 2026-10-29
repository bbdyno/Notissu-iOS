//
//  SettingsView.swift
//  Notissu
//
//  Copyright © 2026 Notissu. All rights reserved.
//

import SwiftUI
import NoticeKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var ads = Ads.shared

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.subscriptions) {
                    LabeledContent("구독한 게시판", value: "\(app.subscriptions.count)곳")
                }
            } footer: {
                Text("소식에는 구독한 게시판의 글이 날짜순으로 모입니다.")
            }

            if ads.isPrivacyOptionsRequired {
                Section {
                    Button("광고 개인정보 설정") {
                        Task { await ads.presentPrivacyOptions() }
                    }
                } footer: {
                    Text("맞춤 광고 동의를 다시 고를 수 있습니다.")
                }
            }

            Section {
                NavigationLink("노티쓔에 대해", value: Route.about)
            }
        }
        .navigationTitle("설정")
    }
}

/// 구독한 게시판 순서 바꾸기와 빼기. 순서는 소식 위쪽 거르기 순서가 된다.
struct SubscriptionsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        List {
            ForEach(app.subscribedBoards) { board in
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.name)
                    Text(board.college)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .onMove { from, to in
                app.subscriptions.move(fromOffsets: from, toOffset: to)
            }
            .onDelete { offsets in
                app.subscriptions.remove(atOffsets: offsets)
            }
        }
        .navigationTitle("구독한 게시판")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .overlay {
            if app.subscriptions.isEmpty {
                StatusMessage(symbol: "square.grid.2x2", text: "구독한 게시판이 없습니다.")
            }
        }
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var app

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("버전", value: version)
                LabeledContent("게시판 설정", value: "\(app.catalog.boards.count)곳 · \(app.catalog.updatedAt ?? "-")")
            }
            Section {
                Text("노티쓔는 숭실대학교 학과·대학원·학교 게시판의 공지를 모아 보여 주는 앱입니다. 학교가 운영하는 앱이 아니며, 글은 각 게시판에서 그대로 가져옵니다.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Section("도움") {
                Link("지원", destination: URL(string: "https://bbdyno.github.io/Notissu-Site/support.html")!)
                Link("개인정보 처리방침", destination: URL(string: "https://bbdyno.github.io/Notissu-Site/privacy.html")!)
                Link("문의 메일 보내기", destination: URL(string: "mailto:della.kimko@gmail.com")!)
            }
            Section("만든 곳") {
                Link("소스 코드 (GitHub)", destination: URL(string: "https://github.com/bbdyno/Notissu-iOS")!)
            }
            Section("오픈소스") {
                Link("Kanna", destination: URL(string: "https://github.com/tid-kijyun/Kanna")!)
                Link("Firebase", destination: URL(string: "https://github.com/firebase/firebase-ios-sdk")!)
                Link("Google Mobile Ads", destination: URL(string: "https://github.com/googleads/swift-package-manager-google-mobile-ads")!)
            }
        }
        .navigationTitle("노티쓔에 대해")
        .navigationBarTitleDisplayMode(.inline)
    }
}
