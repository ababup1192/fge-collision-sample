// Game — App の組み立て。デスクトップ（Main）・ブラウザ版（web/WebMain）・描き出し（render/SceneRender）が同じ物を使う。
//   init   = assets/collision.kind.json の値から始める
//   update = World.step（キー・マウス → 動き → 当たり判定）
//   view   = View.frame（盤とパネル）
// make debug で起動すると、collision.kind.json を保存した時に読み直す（withDocTable の 1 行）。
mod Game {
    use fge::{App, DocTable}

    pub def app(tuning: Tuning.Tuning): App.App[World.World, {}] =
        App.game({
            init = World.initial(tuning),
            update = World.step,
            view = View.frame,
            reloads = Nil
        })
            |> App.withDocTable(DocTable.row("collision", Tuning.path(), w -> World.withTuning(Tuning.load(Tuning.path()), w)) :: Nil)
}
