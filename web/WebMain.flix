// ブラウザ版の入口（make web = bin/fge export-web だけが組む。src の外に置くのは、デスクトップの make check の木に入れないため）。
// デスクトップと同じ Game.app を、ブラウザの道具（WebLayer・WebFs）の上で動かす。
// ブラウザでは JSON の保存即反映が効かないので、値は右のパネルのスライダーとチップで変える。
mod WebMain {
    use fge::{App, WebFs, WebLayer}

    pub def main(): Unit \ IO =
        run {
            App.launchWithDevTools(App.DevTools.none(), Game.app(Tuning.load(Tuning.path())))
        } with WebLayer.withProject(".")
          with WebFs.runFileRead
          with WebFs.runFileWrite
}
