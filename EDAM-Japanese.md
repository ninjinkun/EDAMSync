# 2. EDAM Synchronization Overview
Evernoteの同期スキームは特定の要求セットに基づいて設計されている。
1.中央サービスがアカウントの状態を完全に把握している、クライアントサーバモデルの同期フロー
2.クライアントは様々なローカルストレージマシンとして作られる。同期スキームは特定の低レベルのストレージ表現を仮定しない。データはblock/recordレベルより論理レベルで転送されるべきである
3. Evernoteは完全同期とインクリメンタル同期をサポートしなければならない。同期の度にDB全体を転送することは受け入れられない。
4.同期は不安定なネットワーク上でも可能で無ければならない。特別な再送信処理は抜きで。最初の同期であっても、クライアントはネットワークエラーの後で転送をレジュームできるべきである。
5. 同期においては、アトミックな同期を行ってエバーノートのサービスをロックできない。このスキームでは、他のクライアントからの同期による変更を許容する。

EDAMではこの要件を、「state bas          ed replication」スキームを使って実現し、中央サービスをシンプルなデータストアとクライアントへの指示を行うものとして扱う。これはメールシステムのIMAPやMS Exchaingeに使われているモデル似ている。これらは似た要件を実現し、ロバストでスケーラブルである。

このスキームでは、Evernoteサービスは個々のクライアントの状態を追跡せず、「log based replication」で実装されているような、細かいログを保存するようなこともしない。その代わり、ユーザーごとのデータエレメント（ノート、タグ等）を保存する。アカウントが持つそれぞれのデータエレメントは、最後に変更された順序を特定するUpdete Sequence Number (USN) を持つ。このシステムはUSNを使い、アカウントの中で他のものより最近に更新されたオブジェクトを特定する。

USNはアカウントを開始した時点で1であり（これはアカウントが作った最初のオブジェクトに割り当てられる）、オブジェクトが作成、変更、削除されるごとに単調増加する。サーバーはアカウントごとにupdate countを追跡する。これは最も大きいUSNの値である。

どの時点であっても、サービスはUSNの値を使ってオブジェクトに順序をつけられる。同期においては、クライアントは最後の同期から変更があったオブジェクトのみを受けとる。これは最後に同期に成功したときのサーバのupdate countよりUSNが大きいオブジェクトである。

上記の#3-5の要求のゴールは複雑である。これらの要求のためには、プロトコルは同期中もロックすること無く、細かいブロックのようなリクエストを許可しなければならない。プロトコルはクライアントがブロックを送信している途中で、サービスの状態が変わる場合をハンドリングしなければならない。こうした情況はクライアントの扱うファイルサイズや通信のスピード、ネットワークのインタラプションなどにより起こりうる。

以上から、同期スキームは全てのレコードの保持と、同期の中で起こりうるコンフリクトの解決を、スケーラブルで"ステートレス"な作法則って行う。これはクライアントは同期する度にサーバーの状態を追跡する必要があることを意味する。そしてその情報を次回の同期の送信と受信に使う。高水準では、クライアントは以下のステップを実行する。

* サービスから新規/更新されたオブジェクトのリストを受けとる
* サーバー上の変更とローカルのデータベースを照合する
* クライアントの同期されていない更新をサービスへ送信する
* サーバーの状態を次の同期に備えて記録する

最後に同期してからクライアントが作成、変更してサービスと同期するデータを特定するために、クライアントは内部にローカルのデータの変更を記録するdirtyフラグを持ち、管理しなければならない。これはサービスにpushされるべきオブジェクトのリストを構成する。（コンフリクトが解決された後で）

例えインクリメンタル同期が可能な状態でも、ユーザーが完全同期を実行できるようにしなければならない。

# 3. Synchronization pseudo-code
以下の擬似コードはクライアントが実行するサービスとの同期を表現したものである。

## Service valiables
* updateCount - アカウントの一番大きいUSN値
* fullSyncBefore - インクリメンタル同期を実行するため、古いキャッシュを遮断する日付。この値はアカウントから削除、もしくは深刻なサーバーの不具合の場合などの履歴のポイント（オブジェトの削除についての）に対応し、クライアントのUSNを無効にする。
Client Valiables
* lastUpdateCount - 最後に同期したときのサーバーのupdateCount
* lastSyncTime - 最後に同期した時間（この時間はサービスから与えられる）

## Authentication
1. 認証にはUserStore.authencitate(username, pwd, key, secret)を使う。これはHTTPSの上で通信を行う
     a. 他の全てのオペレーションに必要なauthenticationTokenを受けとる
     b. authenticationTokenの期限を記録する.もしトークンの期限が直近のサーバーリクエストより前であれば、UserStore.refreshAuthentication()を使って新しいトークンを要求する

Sync Status
2. もしクライアントがこれまでに同期を行ったことがなければFull Syncを行う
3. NoteStore.getSyncState()を実行し、サーバーのupdateCountとfullSyncBeforeを取得する
     a. if (fullSyncBefore > lastSyncTime) Full Syncを実行
     b. if (updteCount == lastUpdateCount) サーバーにはアップデートがないのでSend Changesへ飛ぶ
     c. さもなければ Incremental Syncへ飛ぶ

## Full Sync
4. NoteStore.getSyncChunk(…, afterUSN=0, maxEntries) サービスからオブジェクトの最初のブロックを受信する。サーバーは最も最近変更されたオブジェクトから、最大maxEntries件のオブジェクトのメタデータを返し始める。これは小さな単位のオブジェクト、例えばTagやSavedSearchのようなものの場合にはデータ全体になる。しかしNoteとResorcesにいてはメタデータのみである。データの長さとオブジェクトの大きなフィールド(noteのコンテンツ、バイナリなど)のMD5ハッシュは後から別々にリクエストされるべきである。Expunged(削除された)オブジェクトは参照(GUID)のみ読み込まれる。
     a. if チャンクのchunkHighUSNがチャンクのupdateCountより小さければ、チャンクをバッファし次のチャンクをリクエストする。afterUSN = chankHighUSNとなるまでStep #4を繰り返す。チャンクの時間的なギャップに関わらず、これは安全に行われる。

5.  バッファされたチャンクをサービスの現在の状態に並べ直す
     a. サーバーのタグ(GUIDで特定される）のリストを構築する。これはSync blocksに含まれている。ブロックを検索し、リストに加えるタグを探す。GUIDが"expunged"だったらリストから消す。
     i. if サーバーにタグが存在し、かつクライアントに存在しなかったら、クライアントDBに追加する。if タグが同じ名前でGUIDが違っていたら:
          1. 存在するタグに dirty フラグが立っていたらユーザーはクライアントとサービスの両方でオフラインの間に同じ名前のタグを作ったということ。field-by-fieldマージを行うか、コンフリクトを報告して解決を待つ
          2. そうでなければクライアントのタグの名前を変更する（例えば後ろに2を追加する）
     ii. if タグがクライアントに存在し、かつサービスに存在しなければ
          1. if クライアントのタグがdirtyでない、もしくは既にサーバーにアップロードしたことがあれば、タグをクライアントから消去する
          2. そうでなければ、タグはクライアントで新しく作られたものとして、後でアップロードする
     iii. if タグがサーバーとクライアントの両方に存在したら:
          1. if USNが同じかつ dirty フラグがなければ、同期中である
          2. if USNが同じでクライアントがdirty フラグを立てていれば、後からサーバーにアップロードする
          3. if サーバーのタグのUSNが大きく、クライアントがdirtyフラグを立てていなければ、サーバーの情報でクライアントの状態を上書きする
          4.  if サーバーのタグのUSNが大きく、クライアントがdirtyフラグを立てていれば、オブジェクトはサーバーとクラインとの両方で編集されたことになる。可能ならfield-by-fieldマージを実行し、もしくはコンフリクトを報告し解決策をレポートする
     b. Saved Serchesにも同じアルゴリズムを実行する
     c. Notebookのリストにも同じアルゴリズムを実行する。もしノートブックがクライアントから消去されていたら、それに属するNotesとResourcesを消去する。
     d. LinkedNotebookにも同じアルゴリズムを実行する。これは他のユーザーアカウントのノートブックへのリンクである。このアカウントの他のデータへの直接的な関係性はない
     e. Notesにも同じアルゴリズムを実行する。ノートのコンテンツはsync blockの一部としては転送されない。新しいノートもしくは変更されたノート（MD5チェックサムとノートのメタデータの長さで検証される）はNoteStore.getNoteContent()で取得される。埋め込まれたResources data blockと認識されたテキストデータは同じである。ノートのタイトルはアカウントの中でユニークである必要は無い。クライアントは同じタイトルでもコンフリクトと見なす必要は無い
6. サーバーのデーターマージの終了時に、クライアントはサーバーのupdateCountをlastUpdateCountに、そしてサーバーの現在の時間をlastSyncTimeに保存する
7. Send Changeに飛ぶ

## Incremental Sync
8. afterUSN=latUpdateCountのところからStep#4をsync blockのリストができるまで実行する
9. buffered chunksのリストを作り、サーバーからクライアントに追加/更新を行う
     a. sync blockに含まれて居るサーバーのタグのリストを作成する(GUIDで特定される）。ブロックを検索し、リストに加えるタグを探す。GUIDが"expunged"だったらリストから消す。
          i. if サーバーにタグが存在し、かつクライアントに存在しなかったら、クライアントDBに追加する。if タグが同じ名前でGUIDが違っていたら:
               1. 存在するタグに dirty フラグが立っていたらユーザーはクライアントとサービスの両方でオフラインの間に同じ名前のタグを作ったということ。field-by-fieldマージを行うか、コンフリクトを報告して解決を待つ
               2. そうでなければクライアントのタグの名前を変更する（例えば後ろに2を追加する）
          ii. if タグがサーバーとクライアントの両方に存在したら:
               1. if クライアントがdirtyフラグを立てていなければ、サーバーの情報でクライアントの状態を上書きする
               2. if クライアントがdirtyフラグを立てていれば、オブジェクトはサーバーとクラインとの両方で編集されたことになる。可能ならfield-by-fieldマージを実行し、もしくはコンフリクトを報告し解決策をレポートする
     b. 同じアルゴリズムをResoursesにも適用する。（ResourcesのrecognitionとalternateDataを受信するのと関係する。これはサーバー上で認識が実行されるからである）
     c. Saved Serchesにも同じアルゴリズムを実行する
     d. Notebookのリストにも同じアルゴリズムを実行する。もしノートブックがクライアントから消去されていたら、それに属するNotesとResourcesを消去する。
     e. LinkedNotebookにも同じアルゴリズムを実行する。これは他のユーザーアカウントのノートブックへのリンクである。このアカウントの他のデータへの直接的な関係性はない
     f. Notesにも同じアルゴリズムを実行する。ノートのコンテンツはsync blockの一部としては転送されない。新しいノートもしくは変更されたノート（MD5チェックサムとノートのメタデータの長さで検証される）はNoteStore.getNoteContent()で取得される。埋め込まれたResources data blockと認識されたテキストデータは同じである。ノートのタイトルはアカウントの中でユニークである必要は無い。クライアントは同じタイトルでもコンフリクトと見なす必要は無い
10. サーバーからクライアントへ削除操作のためChunkのリストを構成する
     a. sync blockからexpungedしたNoteのGUID集合を組み立てる。リストのGUIDそれぞれに対して対応するNoteが存在すれば削除する。
     b. Notebookにも同様のことを行う。削除されたNotebookに属するNotesとResourcesも同様
     c. Saved Searchesにも同様のことを行う
     d. タグにも同様のことを行う
     e. LinkedNotebooksにも同様のことを行う
11. サーバーのデーターマージの終了時に、クライアントはサーバーのupdateCountをlastUpdateCountに、そしてサーバーの現在の時間をlastSyncTimeに保存する
7. Send Changeに飛ぶ

## Send Changes
13. dirtyフラグの立っているローカルアカウントのタグそれぞれについて
     a. if タグが新しい場合(ローカルのUSNがまだ未セット) サーバーにNoteStore.createTag()で送信する。サービスがコンフリクトを報告してきたら（このクライアントがサービスからblockを受信した後で他のクライアントがアップデートを行う、これは起こりそうもない）クライアントはローカルのコンフリクトを解消する。もしサーバーがリクエストと違うGUIDのタグを返してきたら、ローカルのタグのGUIDを合うように変更する。
     b. if タグが変更されていたら（ローカルのUSNがセットされている）サーバーにNoteStore.updateTag()で更新を送信し、要求されるコンフリクト解消法を行う。
     c. これらのケースではレスポンスのUSNをチェックする
          i. if USN = lastUpdateCount + 1であれば、クライアントはまだサービスと同期中である。lastUpdateCountをUSNに合うように更新する。
          ii. USN > lastUpdateCount + 1 であれば、クライアントはサービスと同期していない。更新を送信した後、Incremental Syncを実行したい
14. diaryフラグの立っているSaved Searchesにも同じアルゴリズムを適用する
15. diaryフラグの立っているNotebookにも同じアルゴリズムを適用する
16. diaryフラグの立っているNoteにも同じアルゴリズムを適用する。クライアントは新しいそれぞれのNoteについて全データ(note contens, resource data recognition data)をNoteStore.createNote()で送信し、一部が更新されている場合にはNoteStore.updateNote()を使って更新を送信する。すなわち、ノートが一度メッセージを送信したら、もう同じものを送信する必要は無い。