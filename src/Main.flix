// デスクトップ版の入口（make run / make debug）。App の中身は Game.app。
use fge::{App, LwjglLayer}

def main(): Unit \ IO =
    if (LwjglLayer.ensureMainThread()) ()
    else {
        run {
            App.loadAndLaunch(() -> Game.app(Tuning.load(Tuning.path())) |> App.withDebug(App.debugFromEnv()))
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
    }
