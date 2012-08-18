# 起動
EDAM_ENVでクライアントの名前を入れる

    EDAM_ENV=server plackup app.psgi -p 5000
    EDAM_ENV=client1 plackup app.psgi -p 5001
    EDAM_ENV=client2 plackup app.psgi -p 5002