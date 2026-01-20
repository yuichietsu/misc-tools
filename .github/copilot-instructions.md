# Github Copilot Instructions

- 会話は日本語で行うこと
- テストや動作確認などは`tmp/`ディレクトリを使用すること
- コミットログはConventional Commits形式にしてください

## Image Toools

### Image To Android Vector Drawable

- `bin/img2vd.sh`
- 引数に入力画像パスと出力するAndroid Vector Drawableパスを指定して実行します。
  - 例: `bin/img2vd.sh input.png output.xml`
- Input画像は`ImageMagick`を使用してSVGに変換します。
- SVGからAndroid Vector Drawableへの変換には`svg2vectordrawable`を使用します。
  - `svg2vectordrawable`はNode.jsのパッケージで、ローカルインストールして使用します。
- 引数で出力するAndroid Vector Drawableの情報を指定できるようにします
  - 用途: FireTVアプリのアイコン、ランチャーアイコン、通知アイコンなど

### Image To FireTV Application Icon Set

- `bin/img2ftvappicons.sh`
- FireTVアプリケーションアイコンセットを生成します。
  - App Banner : 320x180
  - Launcher Icon : 108x108
- 引数に入力画像パスと出力ディレクトリパスを指定して実行します。
  - 例: `bin/img2ftvappicons.sh input.png output_directory`
- 画像の変換は`ImageMagick`を使用します。
- 入力画像と出力画像のアスペクト比が異なる場合、出力画像の短辺に接するように入力画面をリサイズして、センタリングします。