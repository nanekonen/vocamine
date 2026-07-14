# Glossalyze Frontend

教材から英単語・熟語を抽出し、自分専用の単語帳で学習するためのFlutterアプリです。

## 主な機能

- メールアドレスまたはGoogle OAuthによるログイン
- 初回レベル設定と、レベルに応じた既知語のバックグラウンド登録
- iOS VisionKit / Android ML Kitによる書類の輪郭検出・自動補正・複数ページスキャン
- 画像・PDF教材の読み込み
- 教材のフォルダ分け、ページ追加、プレビュー表示
- 教材内の語彙を「全体・既知・未知・訳なし」に分類
- 教材から単語帳への個別登録・一括登録
- 単語帳とフォルダの作成・整理
- 単語カード、4択問題、テスト形式での学習
- 単語帳直下および配下の単語帳をまとめた学習
- 習得語彙数、登録語彙数、習得語彙率、直近の教材を表示するダッシュボード
- 画面幅に応じたPC・スマートフォン向けレイアウト

## 技術構成

- Flutter / Dart
- Riverpod
- GoRouter
- Supabase Auth
- Glossalyze Backend API

## ローカル起動

Flutter SDKを用意し、このディレクトリで依存関係を取得します。

```bash
cd vocamine_front
flutter pub get
```

Web版を起動する場合：

```bash
flutter run -d chrome \
  --dart-define=VOCAMINE_API_BASE_URL=http://localhost:8000/api/v1 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

`VOCAMINE_API_BASE_URL`を省略した場合は、`http://localhost:8000/api/v1`を使用します。`SUPABASE_PUBLISHABLE_KEY`が未設定の場合、ログインは利用できません。

## ビルド時の設定値

| 変数 | 必須 | 説明 |
|---|---:|---|
| `VOCAMINE_API_BASE_URL` | Yes | `/api/v1`まで含むバックエンドURL |
| `SUPABASE_URL` | Yes | SupabaseプロジェクトURL |
| `SUPABASE_PUBLISHABLE_KEY` | Yes | Supabase Authで使用する公開キー |

変数名の`VOCAMINE_`は既存デプロイとの互換性のため残している内部識別子です。画面上の製品名は`Glossalyze`です。

## Webリリースビルド

通常のビルド：

```bash
flutter build web --release \
  --dart-define=VOCAMINE_API_BASE_URL=https://api.example.com/api/v1 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Cloudflare Pagesでは、次の環境変数を設定して`./scripts/cloudflare_build.sh`を実行します。

- `FLUTTER_VERSION`
- `VOCAMINE_API_BASE_URL`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

ビルド成果物は`build/web`に出力されます。SPAの各URLをFlutterへ戻すよう、ホスティング側のフォールバック設定も必要です。

## 確認

```bash
flutter analyze
flutter test
```

Android・iOSの表示名も`Glossalyze`に設定しています。既存インストールとの互換性を保つため、Dartパッケージ名やBundle IDなど一部の内部識別子には旧名が残っています。

ネイティブ書類スキャンはiOS・Androidアプリで利用できます。Flutter WebではOSの書類スキャナAPIを呼び出せないため、画像またはPDFの読み込みを使用します。Android版の書類スキャンにはGoogle Play Servicesが必要です。
