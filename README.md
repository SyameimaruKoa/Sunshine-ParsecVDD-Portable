# Sunshine + Parsec VDD Portable Launcher

**Windowsでポータブル版Sunshineを使うときだけ起動し、Parsec VDDの仮想モニターを生成・維持・削除するランチャー。**

サービス登録、VBS、ParsecDisplayアプリの常駐は不要。Sunshineの実験的なキャプチャ方式を使用するため、Sunshineをログイン中のユーザーとして手動起動する構成を想定する。

## 動作

1. ランチャーがPowerShellを独立プロセスとして起動し、CMDはすぐ終了する。
2. 既存の `Start-Sunshine-ParsecVDD-v2.ps1` がParsec VDDの仮想モニターを1台生成し、維持信号を送る。
3. ユーザー権限でポータブル版 `sunshine.exe` を起動する。
4. Sunshineを正常終了すると、仮想モニターを削除する。PowerShellも終了する。

**Ctrl+Cや「バッチ ジョブを終了しますか？」は通常の起動・終了では不要。** Sunshineのトレイアイコンから終了すること。

## 必要環境

- Windows 10/11 x64、Windows PowerShell 5.1
- ポータブル版 [Sunshine](https://github.com/LizardByte/Sunshine/releases)（`sunshine.exe` を直接起動する方式）
- [Parsec Virtual Display Driver](https://github.com/nomi-san/parsec-vdd) が **setup.exeでインストール済み**、デバイスマネージャーの `Parsec Virtual Display Adapter` が正常
- **Windowsにサインインしたセッション**（ログイン画面からの完全無人起動には非対応）

**ParsecDisplay GUI、VDDのCLI、Sunshineサービスの導入は不要**。本ランチャーはParsec VDDのドライバーに直接IOCTLを送る。

## インストール

本リポジトリの次の4ファイルを `sunshine.exe` と同じフォルダーにコピーする。

```text
Sunshine/
    sunshine.exe                           (ユーザーが別途用意)
    Sunshine-Headless.cmd
    Launch-Sunshine-Headless.ps1
    Create-Sunshine-Shortcut.ps1
    Start-Sunshine-ParsecVDD-v2.ps1
```

`sunshine.exe` の例: `C:\Users\<ユーザー名>\Documents\Sunshine\sunshine.exe`。

**既存の設定、`apps.json`、`sunshine.conf`、MPO、Game DVR、電源プランは変更しない。** `sunshine-vdd` のサービス用インストーラーとは別実装。

### ワンクリック起動

**`Sunshine-Headless.cmd` をダブルクリック**する。CMDは即終了し、SunshineとParsec仮想モニターは利用中だけ稼働する。

### デスクトップショートカット（任意）

一度だけ `Sunshine-Headless.cmd --shortcut` を実行する。作られた「Sunshine Headless」のショートカットは**PowerShellに直接リンクする**ため、起動時にCMDやVBSを経由しない。

> インストール先を移動した場合は、ショートカットを作り直すこと。

## 終了

Sunshineのトレイアイコンから通常終了する。制御スクリプトが終了を検知し、`finally` でVDDの仮想モニターを削除する。**VDDのドライバー本体はインストールされたまま**。

仮想モニター維持の信号が停止した場合、Parsec VDD側の監視機構により仮想モニターは約1秒で削除される設計。異常終了時のWindows環境は未検証のため、万一画面が戻らなければWindowsのディスプレイ設定を確認する。

## コマンドとヘルプ

```bat
Sunshine-Headless.cmd
Sunshine-Headless.cmd --debug
Sunshine-Headless.cmd --shortcut
Sunshine-Headless.cmd -h
Sunshine-Headless.cmd --help
```

`--debug` は独立したPowerShellウィンドウで起動し、エラーを表示する。バッチ自体は待機しない。PS1単体にも `-h` があり、コメントベースの `Get-Help` に対応する。

通常起動時のログは `Sunshine-Headless.log`。コンソール非表示で失敗したらまずログを確認する。

## Sunshineの画面設定

仮想モニターを生成した状態でSunshineのログ（`Currently available display devices`）を確認し、**Parsec仮想モニターの `device_id`** を配信対象に設定する。PnPアダプターIDの `ROOT\DISPLAY\...` と、SunshineのモニターGUIDは異なるので混同しないこと。

ノートPCの蓋を閉じてもスリープしないよう電源設定を確認する。蓋を閉じて内蔵ディスプレイが切断されても、Parsec VDDの画面が有効なら配信可能な構成となる。

## 制約と注意

- Sunshineがすでに起動中なら、元のPS1が二重起動を拒否する。
- 仮想モニターの生成・寿命管理は `Start-Sunshine-ParsecVDD-v2.ps1` の処理に依存する。このファイルは既存の動作を保つため**変更していない**。
- ポータブルSunshineのGame Capture / WGC方式はそのまま利用できるが、描画・配信の成否は環境とSunshine設定に依存する。
- **通常動作中はPowerShellのプロセスが1つ残る**（仮想モニター維持のため）。Sunshineが終了すればこのプロセスも終了する。バックグラウンドサービスとしての常時稼働はしない。
- 動作テストはソース・エンコーディング・ZIP整合性確認まで。Windows実機での起動・Headless配信はまだ検証していない。

## ファイル形式

- `*.ps1`：UTF-8 **BOM付き**、CRLF
- `*.cmd`：Shift-JIS（CP932）、CRLF（先頭で `chcp 932`）
- `README.md`：UTF-8

## 出典・謝辞

- [nomi-san/parsec-vdd](https://github.com/nomi-san/parsec-vdd) - Parsec VDD IOCTLとAPI情報（MITライセンス）
- [Roei-Bracha/sunshine-vdd](https://github.com/Roei-Bracha/sunshine-vdd) - Sunshine連携の参考資料。本リポジトリはサービス再起動型の導入処理を使用しない。
- [LizardByte/Sunshine](https://github.com/LizardByte/Sunshine) - 配信ホスト本体。本リポジトリにはバイナリを含めない。
