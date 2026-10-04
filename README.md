# Vela

A simple macOS file explorer app built with SwiftUI and AppKit.

## Requirements

- macOS 14 Sonoma or later
- Xcode 26 or later (to build from source)

## Features

### Navigation
- **Tabs** — Open multiple directories at once (`Cmd+T` for a new tab, `Cmd+W` to close a tab, `Cmd+Shift+W` to close the window). Arrow buttons appear when tabs overflow the tab bar
- **Switch Tabs** — `Ctrl+Tab` / `Ctrl+Shift+Tab` or `Cmd+Shift+]` / `Cmd+Shift+[` for the next / previous tab; `Cmd+1`–`Cmd+8` jump to that tab and `Cmd+9` to the last tab
- **Open in New Tab** — Middle-click (wheel click) a folder in the file list or sidebar favorites to open it in a new background tab
- **Address Bar** — Click breadcrumbs to jump to any parent directory, or click to type a path directly (`Cmd+C` / `Cmd+V` work while editing)
- **Back / Forward / Up** — Toolbar buttons or keyboard (`Cmd+↑` to go up, `Cmd+↓` to open)
- **Toggle Hidden Files** — Toolbar icon or `Cmd+Shift+.`
- **Type to Select** — Type the first letters of a name in the file list to jump to that item
- **Restore Tabs** — The tabs open when you quit (and the selected tab) reopen on the next launch
- **Auto Refresh** — The file list updates automatically when files are added, removed, renamed or modified by other apps

### Dual Pane
- **View → Dual Pane** (`Ctrl+Cmd+2`) or the toolbar's split button shows two file lists side by side, each with its own tabs and address bar
- The toolbar, sidebar, status bar and tab shortcuts act on the active pane (marked by an accent line). Click a pane or press `Tab` in the file list to switch
- **Copy / Move to Other Pane** — `F5` / `F6` (`fn+F5` / `fn+F6` on most Mac keyboards) or the context menu copies or moves the selection into the folder shown in the other pane
- **Show This Folder in Other Pane** and **Swap Panes** in the View menu
- Drag the divider to resize the panes (double-click to split evenly). The mode, both panes' tabs and the split are restored on the next launch
- Closing the last tab of a pane returns to a single pane

### File Operations
- **Open** — Double-click or `Cmd+↓` (files open with their default app; `.app` packages launch)
- **Open With** — Context menu lists the default app and other apps that can open the file, plus **Other…** to choose any app
- **Show Package Contents** — Right-click an app or package to browse its contents
- **Rename** — Select an item and press `Return`, or use the context menu, then enter the new name in the dialog
- **New Folder** — `Cmd+Shift+N` or right-click on an empty area
- **Copy** — Context menu "Copy" copies the file; `Cmd+C` copies the path as text; "Copy Name" / "Copy Path" copy the name or full path as text
- **Paste** — `Cmd+V` copies files on the clipboard into the current folder (pasting into the same folder makes a copy named `<name> copy`)
- **Move Item Here (Cut & Paste)** — `Cmd+Option+V` moves files on the clipboard into the current folder. Also available from the context menu on an empty area
- **Duplicate** — `Cmd+D` or context menu creates `<name> copy` in the same folder
- **Make Alias** — `Ctrl+Cmd+A` or context menu creates a Finder alias (`<name> alias`)
- **Open in Terminal** — Context menu on a folder or an empty area, the toolbar terminal button, or right-click the address bar
- **Move** — Choose a destination folder via the context menu
- **Compress to ZIP** — Context menu creates `<name>.zip` next to the item (same format as Finder's Compress)
- **Share** — Context menu opens the macOS share menu
- **Properties** — Context menu opens Finder's Get Info window (macOS asks for Automation permission on first use)
- **Trash** — `Delete` key or context menu (with confirmation dialog)
- **Undo / Redo** — `Cmd+Z` / `Cmd+Shift+Z` while the file list is focused undo and redo rename, move, copy, paste, duplicate, make alias, new folder, Compress to ZIP and Trash (undone copies and new items go to the Trash)
- **Background Copy & Move** — Copies, pastes, duplicates, moves and drops run in the background, so large transfers don't freeze the app. The status bar shows the progress with a button to stop; operations started meanwhile wait their turn. Copies clone on APFS and keep metadata like Finder. Errors (e.g. an item with the same name already exists) are shown in an alert

### Drag & Drop
- Drag a file onto a folder to **move** it
- Hold `Option` while dragging to **copy**
- Drop onto an empty area of the list to move or copy into the folder being shown (e.g. from the other pane or from Finder)
- Dropping onto sidebar favorites and volumes is also supported

### Quick Look
- Select a file and press `Space` to open a Quick Look preview

### Sidebar (Favorites)
- Home, Desktop, Documents, Downloads, and Applications are added by default
- Right-click a folder → "Add to Favorites" to add it
- Drag to reorder, right-click → "Remove" to delete

### Sidebar (Locations)
- Lists the startup disk and mounted external, disk image and network volumes, updated as they are mounted and unmounted
- Click the eject button (or right-click → Eject) to eject a volume. Tabs showing an ejected volume go back to the home folder

### Search
- Use the toolbar search field or `Cmd+F` to filter the current directory in real time
- Click the magnifying glass to choose the scope: **This Folder** or **This Folder and Subfolders**. The latter searches all subfolders by name in the background (package contents are skipped, hidden files follow the hidden files setting, up to 5,000 results) and adds a Location column showing where each result is

### Sort
- Click column headers (Name / Date Modified / Date Created / Size / Kind) to sort; click again to reverse

### Columns
- Right-click the column header to show or hide Date Modified, Date Created, Size and Kind (Date Created is hidden by default)
- Column visibility and widths are remembered

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
│   ├── FileDisplaySettings.swift # Shared display settings (hidden files, search scope)
│   ├── FavoriteItem.swift     # Favorites model & persistence (UserDefaults)
│   └── VolumesStore.swift     # Mounted volumes for the sidebar & eject
├── Views/
│   ├── TabBarView.swift       # Tab bar UI (one per pane in dual pane mode)
│   ├── ToolbarView.swift      # Address bar, navigation buttons, search field
│   ├── SidebarView.swift      # Favorites & Locations sidebar
│   ├── FileListView.swift     # File list wrapper (filtering, search results & sort state)
│   ├── FileTableNSView.swift  # NSTableView-based file table with drag & drop
│   └── StatusBarView.swift    # Bottom status bar (item count / selection info / copy progress)
└── Services/
    ├── FileService.swift      # Directory reading via FileManager
    ├── FileOperations.swift   # Undoable file operations (move, trash, create)
    ├── FileOperationQueue.swift # Background copy & move with progress and cancel
    ├── SubfolderSearch.swift  # Background search by name in subfolders
    └── DirectoryWatcher.swift # FSEvents-based auto refresh of the current directory
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
- **頭文字ジャンプ** — ファイル一覧で名前の先頭の文字を入力すると、その項目へ移動
- **タブの復元** — 終了時に開いていたタブ（と選択中のタブ）を次回起動時に復元
- **自動更新** — 他のアプリでファイルが追加・削除・名前変更・更新されると、一覧に自動で反映

### 2ペイン表示
- **表示 → 2ペイン表示**（`Ctrl+Cmd+2`）またはツールバーの分割ボタンで、ファイル一覧を左右に並べて表示。ペインごとにタブとアドレスバーを持つ
- ツールバー・サイドバー・ステータスバー・タブのショートカットはアクティブなペイン（アクセントカラーの線で表示）に対して働く。ペインをクリックするか、ファイル一覧で `Tab` キーを押して切り替え
- **反対側のペインにコピー / 移動** — `F5` / `F6`（多くの Mac のキーボードでは `fn+F5` / `fn+F6`）またはコンテキストメニューで、選択項目を反対側のペインに表示中のフォルダへコピー・移動
- 表示メニューの **反対側のペインで同じフォルダを開く** と **左右のペインを入れ替え**
- 境界線をドラッグして幅を調整（ダブルクリックで半分ずつに戻す）。表示状態・両ペインのタブ・分割位置は次回起動時に復元
- ペインの最後のタブを閉じると 1 ペイン表示に戻る

### ファイル操作
- **開く** — ダブルクリック、または `Cmd+↓`（ファイルはデフォルトアプリで開き、`.app` などのパッケージは起動）
- **このアプリケーションで開く** — コンテキストメニューに、デフォルトのアプリとそのファイルを開ける他のアプリを表示。**その他…** で任意のアプリを選択
- **パッケージの内容を表示** — アプリやパッケージを右クリックして中身を表示
- **名前変更** — 項目を選択して `Return` キー、またはコンテキストメニューから、ダイアログに新しい名前を入力
- **新規フォルダ作成** — `Cmd+Shift+N`、またはコンテキストメニュー（空白部分を右クリック）
- **コピー** — コンテキストメニューの「コピー」でファイルをコピー。`Cmd+C` はパスをテキストとしてコピー
- **ペースト** — `Cmd+V` でクリップボードのファイルを現在のフォルダにコピー（同じフォルダへのペーストは「<名前> のコピー」を作成）
- **ここに項目を移動（カット＆ペースト）** — `Cmd+Option+V` でクリップボードのファイルを現在のフォルダへ移動。空白部分の右クリックメニューからも可能
- **複製** — `Cmd+D`、またはコンテキストメニューで同じフォルダに「<名前> のコピー」を作成
- **エイリアスを作成** — `Ctrl+Cmd+A`、またはコンテキストメニューで Finder のエイリアス（「<名前> のエイリアス」）を作成
- **ターミナルで開く** — フォルダや空白部分の右クリックメニュー、ツールバーのターミナルボタン、アドレスバーの右クリックから
- **移動** — コンテキストメニューの「移動」から移動先フォルダを選択
- **ZIPに圧縮** — コンテキストメニューから、項目と同じ場所に `<名前>.zip` を作成（Finder の「圧縮」と同じ形式）
- **共有** — コンテキストメニューから macOS の共有メニューを表示
- **プロパティ** — コンテキストメニューから Finder の「情報を見る」ウインドウを表示（初回は macOS がオートメーションの許可を求めます）
- **ゴミ箱** — `Delete` キー、またはコンテキストメニュー（確認ダイアログあり）
- **取り消し / やり直し** — ファイル一覧にフォーカスがある状態で `Cmd+Z` / `Cmd+Shift+Z`。名前変更・移動・コピー・ペースト・複製・エイリアス作成・新規フォルダ・ZIP圧縮・ゴミ箱を取り消せる（コピーや新規作成の取り消しではゴミ箱へ移動）
- **バックグラウンドでのコピー・移動** — コピー・ペースト・複製・移動・ドロップはバックグラウンドで実行され、大きなファイルでもアプリが固まらない。ステータスバーに進捗と中止ボタンを表示し、実行中に始めた操作は順番待ちになる。Finder と同じく APFS ではクローンで複製し、メタデータも保持。同名の項目がある場合などのエラーはアラートで表示

### ドラッグ＆ドロップ
- ファイルをフォルダへドラッグして**移動**
- `Option` キーを押しながらドラッグして**コピー**
- 一覧の空白部分へのドロップで、表示中のフォルダへ移動・コピー（反対側のペインや Finder から）
- サイドバーのお気に入りフォルダやボリュームへのドロップにも対応

### Quick Look
- ファイルを選択して `Space` キーで Quick Look プレビュー

### サイドバー（よく使う項目）
- ホーム・デスクトップ・書類・ダウンロード・アプリケーションがデフォルトで登録済み
- フォルダを右クリック →「お気に入りに追加」で追加
- ドラッグで並び替え、右クリック →「削除」で解除

### サイドバー（場所）
- 起動ディスクと、マウント中の外付け・ディスクイメージ・ネットワークのボリュームを表示（マウント・取り出しに合わせて自動で更新）
- 取り出しボタン（または右クリック →「取り出す」）でボリュームを取り出し。取り出したボリュームを表示していたタブはホームフォルダに戻る

### 検索
- ツールバーの検索フィールド、または `Cmd+F` でアクティブなディレクトリ内をリアルタイムフィルタリング
- 虫眼鏡アイコンをクリックして検索範囲を **このフォルダ** / **このフォルダとサブフォルダ** から選択。後者はすべてのサブフォルダを名前でバックグラウンド検索し（パッケージの中は対象外、隠しファイルは表示設定に従う、最大 5,000 件）、各結果の場所を示す「場所」列を表示

### ソート
- 名前 / 更新日 / 作成日 / サイズ / 種類の各列ヘッダーをクリックしてソート（昇順・降順切り替え）

### 列
- 列ヘッダーを右クリックして、更新日・作成日・サイズ・種類の表示 / 非表示を切り替え（作成日は初期状態で非表示）
- 列の表示状態と幅は保存され、次回以降も引き継がれる

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
│   ├── FileDisplaySettings.swift # 共通の表示設定（隠しファイル・検索範囲）
│   ├── FavoriteItem.swift     # お気に入りモデルと永続化（UserDefaults）
│   └── VolumesStore.swift     # サイドバーに表示するボリュームと取り出し
├── Views/
│   ├── TabBarView.swift       # タブバー UI（2ペイン表示ではペインごと）
│   ├── ToolbarView.swift      # アドレスバー・ナビゲーションボタン・検索フィールド
│   ├── SidebarView.swift      # お気に入り・場所のサイドバー
│   ├── FileListView.swift     # ファイルリストラッパー（フィルタリング・検索結果・ソート状態管理）
│   ├── FileTableNSView.swift  # NSTableView ベースのファイルテーブル（ドラッグ＆ドロップ対応）
│   └── StatusBarView.swift    # 下部ステータスバー（項目数・選択情報・コピーの進捗）
└── Services/
    ├── FileService.swift      # FileManager によるディレクトリ読み込み
    ├── FileOperations.swift   # 取り消し可能なファイル操作（移動・ゴミ箱・作成）
    ├── FileOperationQueue.swift # 進捗表示・中止に対応したバックグラウンドのコピー・移動
    ├── SubfolderSearch.swift  # サブフォルダを含む名前のバックグラウンド検索
    └── DirectoryWatcher.swift # FSEvents による表示中ディレクトリの自動更新
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
