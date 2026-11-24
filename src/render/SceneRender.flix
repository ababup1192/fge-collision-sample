// SceneRender — 4 つの章の画面を、窓を開かずに PNG へ描き出す（README の絵と、直した後の見比べに使う）。
//   make render-all          → gallery/<場面>.png（全部）
//   make render SHOT=4-new   → debug/4-new.png（1 枚だけ）
// 各場面は、決まったキー入力で何コマか進めた World を描く（毎回同じ絵が出る）。
// WhyNot: ブラウザ版には入れない — 描き出しの道具（HeadlessRender・java.io）はデスクトップにしか無い。
mod SceneRender {
    use fge::{App, DocJson, GameEngine, HeadlessFont, HeadlessRender, JsonCodec, Render, Vec2}

    import java.io.File

    /// 描き出せる場面の名前（Makefile の SHOTS と同じ並び）。
    pub def names(): List[String] =
        "1-radius" :: "2-layermask" :: "3-boss-circle" :: "3-boss-polygon" :: "4-every" :: "4-new" :: Nil

    /// 場面の World: 章に入り、keys を押したまま n コマ進め、続けて何も押さずに m コマ進める。
    def worldOf(name: String, tuning: Tuning.Tuning): Option[World.World] =
        let start = mode -> World.enterMode(mode, World.initial(tuning));
        let up = Set#{GameEngine.Key.Up};
        match name {
            case "1-radius"       => Some(start(World.Mode.Radius) |> steps(150, Set.empty()))
            case "2-layermask"    => Some(start(World.Mode.LayerMask) |> steps(40, Set#{GameEngine.Key.Left}) |> steps(80, Set.empty()))
            case "3-boss-circle"  => Some(start(World.Mode.BossShape) |> steps(20, Set.empty()))
            case "3-boss-polygon" => Some(start(World.Mode.BossShape) |> World.setBossShape(Tuning.BossShape.Polygon) |> steps(20, Set.empty()))
            case "4-every"        => Some(start(World.Mode.SpawnLine) |> steps(44, up) |> steps(40, Set.empty()))
            case "4-new"          => Some(start(World.Mode.SpawnLine) |> World.setLineCheck(World.LineCheck.NewOnly) |> steps(41, up))
            case _                => None
        }

    def steps(n: Int32, keys: Set[GameEngine.Key], w: World.World): World.World =
        let frame = { down = keys, dt = 1.0 / 60.0 | App.emptyFrame() };
        List.foldLeft((acc, _) -> World.step(frame, acc), w, List.range(0, n))

    def ttf(): String = "assets/MPLUSRounded1c-Bold.ttf"

    def design(): Vec2.Vec2 = { x = 1280.0, y = 720.0 }

    /// project.json の textures（名前 → パス）。
    def texturesOf(): Map[String, String] \ IO =
        let json = run { DocJson.readJson("project.json") } with Fs.FileRead.runWithIO;
        json |> Result.toOption |> Option.flatMap(JsonCodec.expectObject)
             |> Option.flatMap(root -> Map.get("textures", root))
             |> Option.flatMap(JsonCodec.decodeList(j -> JsonCodec.expectObject(j) |> Option.map(obj ->
                    (JsonCodec.stringOr("name", "", obj), JsonCodec.stringOr("path", "", obj)))))
             |> Option.getWithDefault(Nil) |> List.toMap

    pub def all(): Unit \ IO = App.Headless.exitWith(allJob(App.Headless.requestFromProcess()))

    def allJob(_req: App.Headless.Request): Int32 \ IO =
        discard shotsInto("gallery", _ -> true);
        0

    /// 常駐（App.Headless.serveJobs）が /run で流す入口の束。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.job("SceneRender", "one", req -> oneJob(req)) ::
        App.Headless.job("SceneRender", "all", req -> allJob(req)) :: Nil

    pub def one(): Unit \ IO = App.Headless.exitWith(oneJob(App.Headless.requestFromProcess()))

    /// SHOT="<場面> <場面>…" だけを debug/ へ描く。
    def oneJob(req: App.Headless.Request): Int32 \ IO =
        let wanted = Map.getWithDefault("SHOT", "", App.Headless.envOf(req)) |> String.splitOn(substr = " ")
            |> List.map(String.trim) |> List.filter(n -> not String.isEmpty(n)) |> List.toSet;
        if (Set.isEmpty(wanted) or not Set.isSubsetOf(wanted, List.toSet(names()))) {
            println("[render] SHOT=<場面> に使えるのは: ${List.join(" ", names())}");
            1
        } else {
            discard shotsInto("debug", n -> Set.memberOf(n, wanted));
            0
        }

    def shotsInto(outDir: String, keep: String -> Bool): List[String] \ IO =
        discard (new File(outDir)).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let cfg = { design = design(), scale = 1, fontTtf = ttf(), fontAtlas = atlas, texturePath = texturesOf(),
                    outDir = outDir, frameW = 1280, frameH = 720 | HeadlessRender.defaults() };
        let ctx = App.viewCtxOf(atlas, design());
        let tuning = run { Tuning.load(Tuning.path()) } with Fs.FileRead.runWithIO;
        names() |> List.filter(keep) |> List.filterMap(name -> worldOf(name, tuning) |> Option.map(w -> {
            let (drawables, polygons) = Render.draw(View.frame(ctx, w));
            HeadlessRender.renderPng(cfg, drawables, polygons, name);
            App.Headless.writeShotRecord(outDir, name, None);
            println("rendered: ${outDir}/${name}.png");
            "${outDir}/${name}.png"
        }))
}
