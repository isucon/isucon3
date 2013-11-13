# API spec

(*) がついている API については、signup で取得した api_key を下記のいずれかの方法でサーバに送信する必要がある。

* HTTPリクエストヘッダ `X-API-Key`
* Cookie `api_key`

## POST /signup

新規ユーザを作成してapi_keyを発行する

paramters
* name: /^[a-zA-Z0-9_]{2,16}$/

response
```
{
 "id": 1,
 "name": "username",
 "icon": "http://localhost/icon/default",
 "api_key": "5aca0bf6c887345abf30258c1210a3f676283c4d90cb04502ba951b0f6e8100f"
}
```
## GET /me (*)

ユーザ自身の情報を返す

response
```
{
 "id": 1,
 "name": "username",
 "icon": "http://localhost/icon/default"
}
```

## GET /icon/{user.icon}?size=[sml]

ユーザのアイコン画像を取得する

* 画像ピクセル数は引数 size に対応して下記の通り。未指定の場合は s と同様。
  * s: 32x32
  * m: 64x64
  * l: 128x128
* ファイル形式は png

## POST /icon (*)

ユーザのアイコンを更新する

* ランダム(推測困難)な url が新規発行される
* 正方形以外の画像の場合は、中心部分を正方形(短辺サイズ)に crop する
* ファイル形式は jpeg または png

parameters
* icon: binary
* file_type: (png|jpg)

response
```
{
 "icon": "http://localhost/icon/d428863918615fd27cc54d1747137d49646d7bf97d2d9dab95305c3568c0381e"
}
```

## POST /entry (*)

画像を投稿する。画像形式は jpg のみ

parameters
* image: 画像binary
* publish_level
  * 0: プライベート。投稿したユーザのみ閲覧可能
  * 1: 投稿したユーザ本人とフォロワーのみ閲覧可能
  * 2: パブリック。だれでも閲覧可能

response:
```
{
  "id": 1,
  "image": "http://localhost/image/6c45e5a9b77b4072757eeadba87ebe34092d627f7b65a1e65c9e28a0acfc92d6",
   "publish_level": 0,
   "user": {
     "id": 1,
     "name": "username",
     "icon": "http://localhost/icon/default"
   }
}
```
## POST /entry/{entry.id} (*)

画像削除する

/image/{entry.image} は即座に 404 となる

parameters:
* __method: DELETE

response:
```
{"ok": true}
```

## GET /image/{entry.image}?size=[sml]

画像を返す

entry.publish_level に応じて
* 0: プライベート。投稿したユーザのみ閲覧可能
* 1: 投稿したユーザ本人とフォロワーのみ閲覧可能
* 2: パブリック。だれでも閲覧可能

URL引数 size に対応して画像のピクセル数は以下の通り
* s: 128x128
* m: 256x256
* l: 投稿されたオリジナルサイズ

s, m で画像が正方形でない場合は中心部分を正方形(短辺サイズ)に crop する
size 未指定の場合は l 扱い

## GET /follow (*)

ユーザがフォローしている全員の情報が返る。

## POST /follow (*)

ユーザをフォローする

parameters:
* target: フォローするユーザの id

response: (フォロー完了後に)ユーザがフォローしている全員の情報が返る
```
{
  "users": [
     {
       "id": 1,
       "name": "username",
       "icon": "http://localhost/icon/default"
     },
     {
       "id": 2,
       "name": "username2",
       "icon": "http://localhost/icon/default"
     }
  ]
}
```

## POST /unfollow (*)

ユーザをフォロー解除する

parameters:
* target: フォロー解除するユーザの id

response: (フォロー解除後に)ユーザがフォローしている全員の情報が返る
```
{
  "users": [
     {
       "id": 2,
       "name": "username2",
       "icon": "http://localhost/icon/default"
     }
  ]
}
```

## GET /timeline (*)

parameters:
* latest\_entry: 未指定の場合は最新の投稿から30件、指定した場合は latest\_entry < id の投稿で latest\_entry に近いものから30件取得

timelineには以下の投稿が流れてくる。

* 自分の投稿
* フォーローしているユーザの publish_level=1 の投稿
* 任意のユーザの publish_level=2 の投稿

引数 latest_entry より新しい投稿が存在しない場合、最大30秒間 long poll する。その間に投稿された場合にはレスポンスが返る。

response:
```
{
  "latest_entry": 10,
  "entries": [
    {
      "id": 10,
      "image": "http://localhost/image/6c45e5a9b77b4072757eeadba87ebe34092d627f7b65a1e65c9e28a0acfc92d6",
      "publish_level": 2,
      "user": {
        "id": 1,
        "name": "username",
        "icon": "http://localhost/icon/default"
      }
    },
    {
      "id": 9,
      "image": "http://localhost/image/60a7853bc47511bcd4a9bd96a6eb0c0ac36dd09591f1b8752b791d1602b880e7",
      "publish_level": 1,
      "user": {
        "id": 2,
        "name": "username2",
        "icon": "http://localhost/icon/default"
      }
    }
  ]
}
```
