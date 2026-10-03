//
//  L10n.swift
//  Vela
//
//  Created by ryuta miyamoto on 2026/10/02.
//

import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    // 言語名は切り替え先が分かるよう、常にその言語自身の表記で表示する
    var displayName: String {
        switch self {
        case .english:  return "English"
        case .japanese: return "日本語"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

// アプリ内の表示言語。再起動せずに切り替えられるよう、システムの Localizable.strings ではなく
// Observable な設定値として持つ。L10n 経由で language を読んだ SwiftUI の View は切り替え時に自動で再描画される
@Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    private static let udKey = "Vela.language"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.udKey) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.udKey)
        language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}

// UI 文言の一覧。英語 / 日本語の対訳をここに集約する
enum L10n {
    private static func tr(_ en: String, _ ja: String) -> String {
        switch LanguageSettings.shared.language {
        case .english:  return en
        case .japanese: return ja
        }
    }

    // MARK: Menu Bar
    static var language: String    { tr("Language", "言語") }
    static var newTab: String      { tr("New Tab", "新規タブ") }
    static var closeTab: String    { tr("Close Tab", "タブを閉じる") }
    static var closeWindow: String { tr("Close Window", "ウインドウを閉じる") }
    static var showPreviousTab: String { tr("Show Previous Tab", "前のタブを表示") }
    static var showNextTab: String     { tr("Show Next Tab", "次のタブを表示") }

    // MARK: Undo / Redo（ファイル一覧にフォーカスがあるときの Edit メニュー項目）
    static var undo: String { tr("Undo", "取り消す") }
    static var redo: String { tr("Redo", "やり直す") }

    static func undoAction(_ actionName: String) -> String {
        tr("Undo \(actionName)", "「\(actionName)」を取り消す")
    }

    static func redoAction(_ actionName: String) -> String {
        tr("Redo \(actionName)", "「\(actionName)」をやり直す")
    }

    // MARK: Tab Bar
    static var newTabHelp: String         { tr("New Tab (⌘T)", "新規タブ (⌘T)") }
    static var closeTabHelp: String       { tr("Close Tab (⌘W)", "タブを閉じる (⌘W)") }
    static var scrollTabsLeftHelp: String  { tr("Show Tabs on the Left", "左のタブを表示") }
    static var scrollTabsRightHelp: String { tr("Show Tabs on the Right", "右のタブを表示") }

    // MARK: Toolbar
    static var enterPath: String       { tr("Enter Path", "パスを入力") }
    static var search: String          { tr("Search", "検索") }
    static var showHiddenFiles: String { tr("Show Hidden Files", "隠しファイルを表示") }
    static var hideHiddenFiles: String { tr("Hide Hidden Files", "隠しファイルを非表示") }

    // MARK: Sidebar
    static var favorites: String { tr("Favorites", "よく使う項目") }
    static var remove: String    { tr("Remove", "削除") }

    static var newGroup: String          { tr("New Group…", "新規グループ…") }
    static var newGroupName: String      { tr("New Group", "新規グループ") }
    static var renameGroup: String       { tr("Rename Group…", "グループ名を変更…") }
    static var deleteGroup: String       { tr("Delete Group", "グループを削除") }
    static var groupNamePrompt: String   { tr("Enter a name for the group.", "グループの名前を入力してください。") }
    static var create: String            { tr("Create", "作成") }
    static var delete: String            { tr("Delete", "削除") }

    static func deleteGroupConfirm(name: String) -> String {
        tr("Delete the group \"\(name)\"?", "グループ「\(name)」を削除しますか？")
    }

    static func deleteGroupMessage(count: Int) -> String {
        tr("\(count) \(count == 1 ? "favorite" : "favorites") in this group will also be removed. The folders themselves won't be deleted.",
           "このグループの\(count)個のお気に入りも削除されます。フォルダ自体は削除されません。")
    }

    static var favoriteHome: String         { tr("Home", "ホーム") }
    static var favoriteDesktop: String      { tr("Desktop", "デスクトップ") }
    static var favoriteDocuments: String    { tr("Documents", "書類") }
    static var favoriteDownloads: String    { tr("Downloads", "ダウンロード") }
    static var favoriteApplications: String { tr("Applications", "アプリケーション") }

    // MARK: File List
    static var columnName: String         { tr("Name", "名前") }
    static var columnDateModified: String { tr("Date Modified", "更新日") }
    static var columnSize: String         { tr("Size", "サイズ") }
    static var columnDateCreated: String  { tr("Date Created", "作成日") }
    static var columnKind: String         { tr("Kind", "種類") }

    static func searchResult(query: String, count: Int) -> String {
        tr("\"\(query)\": \(count) \(count == 1 ? "item" : "items")", "「\(query)」: \(count) 件")
    }

    // MARK: Status Bar
    static func itemCount(_ count: Int) -> String {
        tr("\(count) \(count == 1 ? "item" : "items")", "\(count)項目")
    }

    static func selectedCount(_ count: Int) -> String {
        tr("\(count) selected", "\(count)個選択")
    }

    // MARK: Context Menu
    static var newFolder: String            { tr("New Folder", "新規フォルダ") }
    static var open: String                 { tr("Open", "開く") }
    static var showPackageContents: String  { tr("Show Package Contents", "パッケージの内容を表示") }
    static var share: String                { tr("Share", "共有") }
    static var rename: String               { tr("Rename", "名前を変更") }
    static var copy: String                 { tr("Copy", "コピー") }
    static var copyName: String             { tr("Copy Name", "名前をコピー") }
    static var copyPath: String             { tr("Copy Path", "パスをコピー") }
    static var move: String                 { tr("Move", "移動") }
    static var duplicate: String            { tr("Duplicate", "複製") }
    static var makeAlias: String            { tr("Make Alias", "エイリアスを作成") }
    static var paste: String                { tr("Paste", "ペースト") }
    static var moveItemHere: String         { tr("Move Item Here", "ここに項目を移動") }
    static var openInTerminal: String       { tr("Open in Terminal", "ターミナルで開く") }

    // 複製・エイリアスの名前に付ける語（Finder と同じ表記。例: "Report copy.pdf" / "Report のコピー.pdf"）
    static var copySuffix: String  { tr(" copy", " のコピー") }
    static var aliasSuffix: String { tr(" alias", " のエイリアス") }
    static var compressToZip: String        { tr("Compress to ZIP", "ZIPに圧縮") }
    static var addToFavorites: String       { tr("Add to Favorites", "お気に入りに追加") }
    static var properties: String           { tr("Properties", "プロパティ") }
    static var moveToTrash: String          { tr("Move to Trash", "ゴミ箱に入れる") }

    static func moveItemsToTrash(_ count: Int) -> String {
        tr("Move \(count) Items to Trash", "\(count)個をゴミ箱に入れる")
    }

    // MARK: Trash Alert
    static var moveToTrashConfirm: String { tr("Move to Trash?", "ゴミ箱に入れますか？") }
    static var cancel: String             { tr("Cancel", "キャンセル") }

    static func moveToTrashMessage(name: String) -> String {
        tr("\"\(name)\" will be moved to the Trash.", "「\(name)」をゴミ箱に入れます。")
    }

    static func moveToTrashMessage(count: Int) -> String {
        tr("\(count) items will be moved to the Trash.", "\(count)個の項目をゴミ箱に入れます。")
    }

    // MARK: Rename Dialog
    static var renameConfirm: String { tr("Rename", "変更") }
    static var renameFailed: String  { tr("Couldn't Rename the Item", "名前を変更できませんでした") }

    static func renamePrompt(name: String) -> String {
        tr("Enter a new name for \"\(name)\".", "「\(name)」の新しい名前を入力してください。")
    }

    // MARK: Move Panel
    static var moveHere: String { tr("Move Here", "ここに移動") }

    static func chooseMoveDestination(name: String) -> String {
        tr("Choose a destination folder for \"\(name)\"", "「\(name)」の移動先フォルダを選択")
    }
}
