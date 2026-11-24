# 当たり判定サンプルの入口。
#   make             … ゲームを起動する（ウィンドウが開く）
#   make debug       … 起動して、assets/collision.kind.json を保存したらすぐ反映する
#   make check       … 型検査だけ
#   make test        … テスト
#   make render SHOT=1-radius … 1 つの章の画面を debug/1-radius.png へ描き出す（場面の名前は下の SHOTS）
#   make render-all  … 全部の場面を gallery/ へ描き出す
#   make web         … ブラウザ版を build/web へ書き出す
#   make help        … 共通の口の一覧
#
# エンジンの場所はマシンごとに違うので、git に入れない local.mk に書く:
#   ENGINE := /abs/path/to/flix_game_engine
-include local.mk
ENGINE ?= ../flix_game_engine

# 描き出せる場面の名前（source of truth は SceneRender.names）。
SHOTS := 1-radius 2-layermask 3-boss-circle 3-boss-polygon 4-every 4-new

ifeq ($(shell test -f "$(ENGINE)/mk/game.mk" && echo ok),)
$(error ENGINE が見当たりません ($(ENGINE)/mk/game.mk が無い) — local.mk に「ENGINE := /abs/path/to/flix_game_engine」を書くか、make <対象> ENGINE=... で指定してください)
endif

space := $(subst ,, )
include $(subst $(space),\$(space),$(ENGINE))/mk/game.mk

.PHONY: web
# WhyNot: FLIX_JAR を渡さずに任せない — export-web は既定で engine の bin/flix.jar を使い、その版が flix.toml の版と違うと
# 依存の toml を読めずに止まる。make check と同じ jar（bin/flix が引く物）を渡す。
web: ## | ブラウザ版を build/web へ書き出す
	@$(FGE_PICK); FLIX_JAR="$(FGE_FLIX_JAR)" "$$fge" export-web .
