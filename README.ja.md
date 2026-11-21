# gaato/requesto

httpx2 や requests の利用者が書くのと同じ書き方で、MoonBit から HTTP を呼び出せます。動詞の関数、既定値を持つクライアント、値としての応答、`raise_for_status()`、範囲の中でのストリーミング、イベントフック、モックの転送層があります。下で HTTP を担うのは [gaato/mttp](https://mooncakes.io/docs/gaato/mttp) で、requesto は表層と httpx2 の既定値だけを足しています。

httpx2 や requests を知っていて、推測できる名前で書きたいなら requesto を選んでください。mttp の既定値(再試行・時間制限・リダイレクトの追跡が既定で有効)、型付きエンドポイント、サーバーが欲しいなら、mttp を直接使ってください。

名前は、日本語話者が言いがちな「request」、つまりリクエスト(*rikuesuto*)です。

マイナーリリースで API が変わることがあります。変更はそれぞれ移行の注意つきで[変更履歴](https://github.com/gaato/requesto.mbt/blob/main/CHANGELOG.md)に載せています。

[English](https://github.com/gaato/requesto.mbt/blob/main/README.md)

## インストール

```sh
moon add gaato/requesto
moon add gaato/mttp
```

アプリは両方を足します。イベントループを `@mttp.run` で始め、requesto が受け取り返す型(`@mttp.Request` や `@mttp.Response` など)は mttp のものだからです。requesto は、MoonBit が実験的としている `moonbitlang/core/async` の上で動きます。タスクを生み出すためや `async test` のために `moonbitlang/core/async` を自分で import するパッケージは、`moon.pkg` に `options("allow-experimental-packages": ["moonbitlang/core/async"])` を書きます。

## 使い方

```mbt check
///|
#derive(FromJson)
struct Account {
  id : Int32
  name : String
}

///|
pub async fn example() -> Unit raise @requesto.HTTPError {
  let client = @requesto.Client::new(
    base_url="https://api.example.com/v1",
    headers=[("Accept", "application/json")],
    auth=Bearer("token"),
  )
  defer client.close()
  let user : Account = client
    .get("users/42", params=[("expand", "teams")])
    .raise_for_status()
    .json_as()
  println("user \{user.id}: \{user.name}")
  client.patch("users/42", json={ "name": user.name + " (renamed)" })
  .raise_for_status()
  |> ignore
}
```

HTTP のメソッドはすべて、モジュールの関数(`@requesto.get(url)`)としても `Client` のメソッドとしてもあります: `get`・`post`・`put`・`patch`・`delete`・`head`・`options`、それ以外には `request(method, url)` を使います。本文を持つメソッドは、同じ `content=`・`text=`・`data=`・`json=`・`files=` の引数を取ります。

応答は、状態コードにかかわらず値として返ります。`raise_for_status()` は 200〜299 以外で `HTTPStatusError` を送出し、それ以外では応答を返すので、呼び出しをつなげられます。失敗はすべて `HTTPError` です。その各ヴァリアントは httpx2 の例外の名前(`ConnectTimeout`・`ReadTimeout`・`ConnectError`・`TooManyRedirects`・`HTTPStatusError` など)を持ちます。クラスの階層の代わりに `is_timeout()` と `is_transport_error()` があり、`mttp()` は下にある `@mttp.TransportError` を返します。

### 本文と認証

一回の呼び出しが取る本文は一つです: `content=` のバイト列、`text=`、フォームとしての `data=`、`json=`、または multipart の本文としての `files=`(テキストの欄は `data=`)。`auth=` は `Basic(user, password)`・`Bearer(token)`・`Digest(user, password)` を、クライアントにも一回の呼び出しにも取ります。Digest のチャレンジに答えるのは、リクエストを作ったオリジンに対してだけで、別のオリジンへのリダイレクトの後では答えません。

```mbt check
///|
pub async fn upload(
  client : @requesto.Client,
) -> Unit raise @requesto.HTTPError {
  client
  .post(
    "reports",
    data=[("title", "weekly")],
    files=[@requesto.Part::file("file", "week.csv", "text/csv", b"a,b\n")],
    auth=Digest("user", "password"),
  )
  .raise_for_status()
  |> ignore
}
```

### ストリーミング

`client.stream` は、本文がまだ接続の上にある応答を関数に渡し、関数が戻ったら閉じます。`read()` で一括に、または `each_bytes`(ダウンロード)・`each_line`(テキストのフィード)・`each_event`(サーバー送信イベント)で少しずつ読めます:

```mbt check
///|
pub async fn follow(client : @requesto.Client) -> Unit {
  client.stream("GET", "events", async fn(response) {
    response.raise_for_status() |> ignore
    response.each_event(event => println("\{event.event}: \{event.data}"))
  })
}
```

1 MiB を超える行や 16 MiB を超えるイベントは `TooLarge` を送出します(上限は `max_line_bytes=` と `max_event_bytes=` で変えられます)。

### ネットワークなしのテスト

`MockTransport::new` は mttp のサーバーが公開するのと同じ型のハンドラーを取るので、httpx2 の `ASGITransport` のように、クライアントからアプリを直接呼べます:

```mbt check
///|
fn hello_app(_ : @mttp.Request) -> @mttp.Response {
  @mttp.Response::new(200, body=Bytes(b"hello"))
}

///|
async test "the app answers" {
  let client = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => hello_app(req)),
  )
  defer client.close()
  assert_eq(client.get("https://app.test/").text(), "hello")
}
```

### トレース

呼び出しの `trace=`(httpx2 の `trace` 拡張にあたります)は、試行が接続の上で到達した各地点で呼ばれます: `Dialed(addr~)`・`TlsDone`・`Pooled(reused~)`・`Written`・`FirstByte`。リダイレクトを含むすべての試行で呼ばれます。報告するのは native と wasm のネットワークで、JS ホストの `fetch` は何も報告しません。

```mbt check
///|
pub async fn timed(client : @requesto.Client) -> Unit raise @requesto.HTTPError {
  client.get("status", trace=event => println(@debug.to_string(event)))
  |> ignore
}
```

## 既定値

httpx2 と同じです:

| 設定 | 既定値 |
| --- | --- |
| リダイレクト | 追わない。クライアントか一回の呼び出しに `follow_redirects=true` を付けると最大 20 回追う |
| 再試行 | なし。`retry=` は `@mttp.RetryPolicy` を取る |
| 時間制限 | 接続・読み込み・書き込み・プールそれぞれ 5 秒。`total_timeout=` で設定しない限り、呼び出し全体の期限はない |
| プール | 最大 100 接続、うち 20 を 5 秒間待機させておく |
| Cookie | クライアント自身の jar に保持する。`cookie_jar=` で共有できる |
| プロキシ | `HTTP_PROXY`・`HTTPS_PROXY`・`NO_PROXY` から。`trust_env=false` で無視する |

httpx2 との違いが一つあります。バッファーする本文は展開後で 64 MiB までに制限され(`max_body_bytes=`)、それより大きいとメモリを埋める代わりに `TooLarge` で失敗します。大きな本文は `stream` で読んでください。

テキストは UTF-8 としてデコードし、不正な並びは U+FFFD に置き換えます。ほかの文字コードは `content` を読んでください。`content=` の生のバイト列は、httpx2 と同じく `Content-Type` なしで送ります。JavaScript では、接続・プロキシ・TLS はホストの `fetch` 自身が扱います。

## httpx2 から移るとき

| httpx2 | requesto |
|---|---|
| `httpx2.get(url, params=..., headers=...)` | `@requesto.get(url, params=[...], headers=[...])` |
| `httpx2.Client(base_url=..., auth=...)` | `@requesto.Client::new(base_url=..., auth=Bearer(...))` |
| `client.patch(url, json=...)` | `client.patch(url, json=...)` |
| `content=b"..."` / `content="..."` | `content=b"..."` / `text="..."` |
| `r.status_code`, `r.text`, `r.json()` | `r.status_code`、`r.text()`、`r.json()`、または型へ読む `r.json_as()` |
| `with client.stream(...) as r:` | `client.stream(..., async fn(r) { ... })` |
| `r.iter_bytes()`, `r.iter_lines()` | `r.each_bytes(f)`, `r.each_line(f)` |
| `httpx_sse` の `iter_sse()` | `r.each_event(f)` |
| `files={"file": ("a.csv", data, "text/csv")}` | `files=[Part::file("file", "a.csv", "text/csv", data)]` |
| `auth=("user", "pw")`, `DigestAuth("user", "pw")` | `auth=Basic("user", "pw")`, `auth=Digest("user", "pw")` |
| `Limits(max_connections=100)` | `limits=Limits::new(max_connections=Some(100))` |
| `proxy="http://..."`, `trust_env=False` | `proxy="http://..."`, `trust_env=false` |
| `verify=False`, `verify="ca.pem"` | `trust=Insecure`, `trust=PemFile("ca.pem")` |
| `Timeout(10.0, connect=5.0)` | `Timeout::new(Some(10_000), connect=Some(5_000))`(ミリ秒) |
| `event_hooks={"request": [...], "response": [...]}` | `event_hooks=EventHooks::new(request=[...], response=[...])` |
| `extensions={"trace": log}` | `trace=event => ...` |
| `MockTransport(handler)` | `MockTransport::new(handler)` |
| `except httpx2.HTTPError` | `HTTPError` に対する `catch { e => ... }` |

`HTTPError` と `status_code` は、MoonBit で普通の `HttpError` や mttp の `status` ではなく httpx2 の綴りにしています。httpx2 から名前を推測できるようにするためです。

## mttp と並べて使う

手を加える必要のない型は mttp のものをそのまま使います: `@mttp.Request`・`@mttp.Response`・`@mttp.Headers`・`@mttp.RetryPolicy`・`&@mttp.Backend`。`client.mttp()` は下にある mttp のクライアントを返し、`build_request` は呼び出しが送るはずの `@mttp.Request` を返します。サーバー・型付きエンドポイント・ルーター・OpenAPI には、mttp と [gaato/mttp_core](https://mooncakes.io/docs/gaato/mttp_core) を直接使ってください。

## ライセンス

Apache-2.0 です。[LICENSE](https://github.com/gaato/requesto.mbt/blob/main/LICENSE) を参照してください。
