# Vela

A simple macOS file explorer app built with SwiftUI and AppKit.

## Requirements

- macOS 14 Sonoma or later
- Xcode 26 or later (to build from source)

## Features

### Navigation
- **Tabs** — Open multiple directories at once (`Cmd+T` for a new tab, `Cmd+W` to close a tab, `Cmd+Shift+W` to close the window). Arrow buttons appear when tabs overflow the tab bar
- **Open in New Tab** — Middle-click (wheel click) a folder in the file list or sidebar favorites to open it in a new background tab
- **Address Bar** — Click breadcrumbs to jump to any parent directory, or click to type a path directly (`Cmd+C` / `Cmd+V` work while editing)
- **Back / Forward / Up** — Toolbar buttons or keyboard (`Cmd+↑` to go up, `Cmd+↓` to open)
- **Toggle Hidden Files** — Toolbar icon or `Cmd+Shift+.`

### File Operations
- **Open** — Double-click or `Cmd+↓` (files open with their default app; `.app` packages launch)
- **Show Package Contents** — Right-click an app or package to browse its contents
- **Rename** — Select an item and press `Return`, or use the context menu, then enter the new name in the dialog
- **New Folder** — `Cmd+Shift+N` or right-click on an empty area
- **Copy** — Context menu "Copy" copies the file; `Cmd+C` copies the path as text; "Copy Name" / "Copy Path" copy the name or full path as text
- **Paste** — `Cmd+V` copies files on the clipboard into the current folder
- **Move** — Choose a destination folder via the context menu
- **Compress to ZIP** — Context menu creates `<name>.zip` next to the item (same format as Finder's Compress)
- **Share** — Context menu opens the macOS share menu
- **Properties** — Context menu opens Finder's Get Info window (macOS asks for Automation permission on first use)
- **Trash** — `Delete` key or context menu (with confirmation dialog)

### Drag & Drop
- Drag a file onto a folder to **move** it
- Hold `Option` while dragging to **copy**
- Dropping onto sidebar favorites is also supported

### Quick Look
- Select a file and press `Space` to open a Quick Look preview

### Sidebar (Favorites)
- Home, Desktop, Documents, Downloads, and Applications are added by default
- Right-click a folder → "Add to Favorites" to add it
- Drag to reorder, right-click → "Remove" to delete

### Search
- Use the toolbar search field or `Cmd+F` to filter the current directory in real time

### Sort
- Click column headers (Name / Date Modified / Size) to sort; click again to reverse

### Language
- Switch the display language from **Vela → Language** in the menu bar (English / 日本語, default: English)
- Changes apply immediately without restarting; standard macOS menu items (About, Quit, Edit, etc.) stay in English

## Project Structure

```
Vela/
├── VelaApp.swift              # App entry point
├── ContentView.swift          # Root view / tab & app state management
├── QuickLookBridge.swift      # Quick Look integration via NSViewRepresentable
├── Localization/
│   └── L10n.swift             # Display language setting & UI strings (English / Japanese)
├── Models/
│   ├── FileItem.swift         # File/directory data model
│   └── FavoriteItem.swift     # Favorites model & persistence (UserDefaults)
├── Views/
│   ├── TabBarView.swift       # Tab bar UI
│   ├── ToolbarView.swift      # Address bar, navigation buttons, search field
│   ├── SidebarView.swift      # Favorites sidebar
│   ├── FileListView.swift     # File list wrapper (filtering & sort state)
│   ├── FileTableNSView.swift  # NSTableView-based file table with drag & drop
│   └── StatusBarView.swift    # Bottom status bar (item count / selection info)
└── Services/
    └── FileService.swift      # Directory reading via FileManager
```

## Installation

1. Download `Vela-x.x.dmg` from [Releases](https://github.com/Ryuta-Miyamoto/Vela/releases)
2. Open the dmg and drag `Vela.app` into the `Applications` folder
3. The app is not signed with an Apple Developer ID, so macOS blocks it on first launch. To allow it, either:
   - Open **System Settings → Privacy & Security** and click **Open Anyway** next to the message about Vela, or
   - Run `xattr -dr com.apple.quarantine /Applications/Vela.app` in Terminal

## Build

To create a release dmg, run `scripts/build-dmg.sh` (output: `build/Vela-<version>.dmg`).

```bash
git clone https://github.com/Ryuta-Miyamoto/Vela.git
cd Vela
open Vela.xcodeproj
```

Press `Cmd+R` in Xcode to build and run.

## License

MIT License — See [LICENSE](LICENSE) for details.

---

# Vela（日本語）

macOS 向けのシンプルなファイルエクスプローラーアプリです。SwiftUI と AppKit を組み合わせて構築しています。

## 動作環境

- macOS 14 Sonoma 以降
- Xcode 26 以降（ソースからビルドする場合）

## 機能

### ナビゲーション
- **タブ** — 複数のディレクトリを同時に開ける（`Cmd+T` で新規タブ、`Cmd+W` でタブを閉じる、`Cmd+Shift+W` でウインドウを閉じる）。タブがあふれると左右のスクロールボタンを表示
- **アドレスバー** — パンくずリストをクリックして任意の親ディレクトリへ移動。クリックで直接パスを入力することも可能
- **戻る / 進む / 上へ** — ツールバーのボタン、またはキーボード（`Cmd+↑` で親ディレクトリ、`Cmd+↓` で開く）
- **隠しファイルの表示切替** — ツールバーのアイコン、または `Cmd+Shift+.`

### ファイル操作
- **開く** — ダブルクリック、または `Cmd+↓`（ファイルはデフォルトアプリで開き、`.app` などのパッケージは起動）
- **パッケージの内容を表示** — アプリやパッケージを右クリックして中身を表示
- **名前変更** — 項目を選択して `Return` キー、またはコンテキストメニューから、ダイアログに新しい名前を入力
- **新規フォルダ作成** — `Cmd+Shift+N`、またはコンテキストメニュー（空白部分を右クリック）
- **コピー** — コンテキストメニューの「コピー」でファイルをコピー。`Cmd+C` はパスをテキストとしてコピー
- **ペースト** — `Cmd+V` でクリップボードのファイルを現在のフォルダにコピー
- **移動** — コンテキストメニューの「移動」から移動先フォルダを選択
- **ZIPに圧縮** — コンテキストメニューから、項目と同じ場所に `<名前>.zip` を作成（Finder の「圧縮」と同じ形式）
- **共有** — コンテキストメニューから macOS の共有メニューを表示
- **プロパティ** — コンテキストメニューから Finder の「情報を見る」ウインドウを表示（初回は macOS がオートメーションの許可を求めます）
- **ゴミ箱** — `Delete` キー、またはコンテキストメニュー（確認ダイアログあり）

### ドラッグ＆ドロップ
- ファイルをフォルダへドラッグして**移動**
- `Option` キーを押しながらドラッグして**コピー**
- サイドバーのお気に入りフォルダへのドロップにも対応

### Quick Look
- ファイルを選択して `Space` キーで Quick Look プレビュー

### サイドバー（よく使う項目）
- ホーム・デスクトップ・書類・ダウンロード・アプリケーションがデフォルトで登録済み
- フォルダを右クリック →「お気に入りに追加」で追加
- ドラッグで並び替え、右クリック →「削除」で解除

### 検索
- ツールバーの検索フィールド、または `Cmd+F` でアクティブなディレクトリ内をリアルタイムフィルタリング

### ソート
- 名前 / 更新日 / サイズの各列ヘッダーをクリックしてソート（昇順・降順切り替え）

### 表示言語
- メニューバーの **Vela → Language** から表示言語を切り替え（English / 日本語、デフォルトは English）
- 再起動せずに即時反映。macOS 標準のメニュー項目（About・Quit・Edit など）は英語表記のまま

## ファイル構成

```
Vela/
├── VelaApp.swift              # アプリのエントリーポイント
├── ContentView.swift          # ルートビュー / タブ・アプリ状態管理
├── QuickLookBridge.swift      # NSViewRepresentable による Quick Look 連携
├── Localization/
│   └── L10n.swift             # 表示言語の設定と UI 文言（英語 / 日本語）
├── Models/
│   ├── FileItem.swift         # ファイル・ディレクトリのデータモデル
│   └── FavoriteItem.swift     # お気に入りモデルと永続化（UserDefaults）
├── Views/
│   ├── TabBarView.swift       # タブバー UI
│   ├── ToolbarView.swift      # アドレスバー・ナビゲーションボタン・検索フィールド
│   ├── SidebarView.swift      # お気に入りサイドバー
│   ├── FileListView.swift     # ファイルリストラッパー（フィルタリング・ソート状態管理）
│   ├── FileTableNSView.swift  # NSTableView ベースのファイルテーブル（ドラッグ＆ドロップ対応）
│   └── StatusBarView.swift    # 下部ステータスバー（項目数・選択情報）
└── Services/
    └── FileService.swift      # FileManager によるディレクトリ読み込み
```

## インストール

1. [Releases](https://github.com/Ryuta-Miyamoto/Vela/releases) から `Vela-x.x.dmg` をダウンロード
2. dmg を開き、`Vela.app` を `Applications` フォルダへドラッグ
3. Apple Developer ID で署名していないため、初回起動時に macOS にブロックされます。次のどちらかの方法で許可してください
   - **システム設定 → プライバシーとセキュリティ** を開き、Vela についてのメッセージの横にある **このまま開く** をクリック
   - ターミナルで `xattr -dr com.apple.quarantine /Applications/Vela.app` を実行

## ビルド方法

リリース用の dmg は `scripts/build-dmg.sh` で作成できます（出力先：`build/Vela-<バージョン>.dmg`）。

```bash
git clone https://github.com/Ryuta-Miyamoto/Vela.git
cd Vela
open Vela.xcodeproj
```

Xcode で `Cmd+R` を押してビルド＆実行します。

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。
