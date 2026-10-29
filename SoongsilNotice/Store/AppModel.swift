//
//  AppModel.swift
//  Notissu
//
//  Copyright © 2026 Notissu. All rights reserved.
//

import Foundation
import Observation
import NoticeKit

enum AppTab: String, CaseIterable, Identifiable {
    case feed, boards, saved, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "소식"
        case .boards: return "게시판"
        case .saved: return "저장"
        case .settings: return "설정"
        }
    }

    var symbol: String {
        switch self {
        case .feed: return "text.alignleft"
        case .boards: return "square.grid.2x2"
        case .saved: return "bookmark"
        case .settings: return "gearshape"
        }
    }
}

/// 공지 한 건과 그 공지가 올라온 게시판.
struct NoticeRef: Hashable, Identifiable {
    let boardID: String
    let item: NoticeItem

    var id: String { item.id }
}

/// 목록 칸 안에서 이동하는 화면.
enum Route: Hashable {
    case board(Board)
    case notice(NoticeRef)
    case pinned
    case subscriptions
    case about
}

/// 모든 창이 함께 쓰는 상태. 게시판 설정, 구독, 읽음 표시를 들고 있다.
@MainActor
@Observable
final class AppModel {
    private static let remoteCatalogURL = URL(string: "https://raw.githubusercontent.com/bbdyno/Notissu-iOS/master/Packages/NoticeKit/Sources/NoticeKit/Resources/boards.json")!
    private static var cachedCatalogURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("boards.json")
    }

    enum Key {
        static let subscriptions = "subscriptions"
        static let readURLs = "readURLs"
        static let primedBoards = "primedBoards"
        static let onboarded = "onboarded"
    }

    private(set) var catalog: BoardCatalog
    private(set) var client: NoticeClient

    var subscriptions: [String] {
        didSet { UserDefaults.standard.set(subscriptions, forKey: Key.subscriptions) }
    }
    var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Key.onboarded) }
    }

    private(set) var readURLs: Set<String>
    private var readOrder: [String]
    private var primedBoards: Set<String>

    init() {
        let bundled = (try? BoardCatalog.bundled()) ?? BoardCatalog(version: 0, updatedAt: nil, presets: [:], boards: [])
        let cached = (try? Data(contentsOf: Self.cachedCatalogURL)).flatMap { try? BoardCatalog.decode($0) }
        let catalog = [cached, bundled].compactMap { $0 }.max { $0.version < $1.version } ?? bundled
        self.catalog = catalog
        self.client = NoticeClient(catalog: catalog)

        let defaults = UserDefaults.standard
        subscriptions = defaults.stringArray(forKey: Key.subscriptions) ?? []
        isOnboarded = defaults.bool(forKey: Key.onboarded)
        let read = defaults.stringArray(forKey: Key.readURLs) ?? []
        readOrder = read
        readURLs = Set(read)
        primedBoards = Set(defaults.stringArray(forKey: Key.primedBoards) ?? [])
    }

    // MARK: - 게시판

    func board(id: String) -> Board? {
        catalog.board(id: id)
    }

    var subscribedBoards: [Board] {
        subscriptions.compactMap(board(id:))
    }

    func isSubscribed(_ board: Board) -> Bool {
        subscriptions.contains(board.id)
    }

    func toggleSubscription(_ board: Board) {
        if let index = subscriptions.firstIndex(of: board.id) {
            subscriptions.remove(at: index)
        } else {
            subscriptions.append(board.id)
        }
    }

    /// 원격 최신 설정을 받아 기본본보다 같거나 새 버전이면 바꿔 쓰고 사본을 남긴다.
    func refreshCatalog() async {
        guard let (data, _) = try? await URLSession.shared.data(from: Self.remoteCatalogURL),
              let remote = try? BoardCatalog.decode(data),
              remote.version >= catalog.version,
              !remote.boards.isEmpty else {
            return
        }
        try? data.write(to: Self.cachedCatalogURL, options: .atomic)
        catalog = remote
        client = NoticeClient(catalog: remote)
    }

    // MARK: - 읽음

    func isRead(_ ref: NoticeRef) -> Bool {
        readURLs.contains(ref.item.url.absoluteString)
    }

    func markRead(_ ref: NoticeRef) {
        markRead([ref.item.url.absoluteString])
    }

    /// 게시판을 처음 받아 왔을 때는 이미 있던 글을 모두 읽은 것으로 둔다.
    /// 그래야 처음 구독한 게시판의 옛 글에 안 읽음 점이 잔뜩 붙지 않는다.
    func prime(boardID: String, items: [NoticeItem]) {
        guard !primedBoards.contains(boardID) else { return }
        primedBoards.insert(boardID)
        UserDefaults.standard.set(Array(primedBoards), forKey: Key.primedBoards)
        markRead(items.map(\.url.absoluteString))
    }

    private func markRead(_ urls: [String]) {
        let fresh = urls.filter { !readURLs.contains($0) }
        guard !fresh.isEmpty else { return }
        readURLs.formUnion(fresh)
        readOrder.append(contentsOf: fresh)
        // 너무 오래된 기록은 버린다.
        if readOrder.count > 4000 {
            let dropped = readOrder.prefix(readOrder.count - 4000)
            readURLs.subtract(dropped)
            readOrder.removeFirst(dropped.count)
        }
        UserDefaults.standard.set(readOrder, forKey: Key.readURLs)
    }
}

/// 창 하나의 화면 이동 상태. 듀오에서 같은 앱을 두 창으로 띄워도 서로 섞이지 않게 창마다 따로 둔다.
@MainActor
@Observable
final class Navigator {
    var selectedTab: AppTab = .feed
    var paths: [AppTab: [Route]] = [:]
    /// 넓은 화면에서 본문 칸에 열린 공지.
    var selection: NoticeRef?

    func path(for tab: AppTab) -> [Route] {
        paths[tab] ?? []
    }

    func setPath(_ path: [Route], for tab: AppTab) {
        paths[tab] = path
    }

    func open(_ ref: NoticeRef, isSplit: Bool) {
        if isSplit {
            selection = ref
        } else {
            paths[selectedTab, default: []].append(.notice(ref))
        }
    }

    /// 접고 펼칠 때 열어 둔 공지를 이어 준다.
    func adapt(toSplit isSplit: Bool) {
        if isSplit {
            var path = paths[selectedTab] ?? []
            if case .notice(let ref) = path.last {
                path.removeLast()
                paths[selectedTab] = path
                selection = ref
            }
            // 목록 칸에는 공지 화면을 두지 않는다.
            for tab in AppTab.allCases {
                paths[tab] = paths[tab]?.filter {
                    if case .notice = $0 { return false }
                    return true
                }
            }
        } else if let ref = selection {
            paths[selectedTab, default: []].append(.notice(ref))
            selection = nil
        }
    }
}
