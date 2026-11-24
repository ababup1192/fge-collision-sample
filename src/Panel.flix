// Panel — 右のパネル（章のタブ・スライダー・チップ・組のリスト・今の JSON の値）と、マウスで押した時の動き。
// 押せる物は widgets の 1 つの一覧にまとめ、描く（view）のも押した物を探す（handleMouse）のも同じ一覧を読む。
mod Panel {
    use fge::{App, Color, FontAtlas, Num, Rect2, RawDraw, Render, TextDraw, Vec2}
    use Hits.Kind
    use Tuning.BossShape
    use World.{Knob, LineCheck, Mode}

    /// 押した時にすること。
    pub enum Action {
        case SelectMode(Mode)
        case Grab(Knob)                 // スライダーをつかむ
        case FlipBit(Kind, Bool, Int32) // 第 2 章のチップ（物・マスクか・bit）
        case SetShape(BossShape)
        case SetCheck(LineCheck)
        case ToggleColliders
    }

    /// 押せる物 1 つ（枠と、押した時にすること）。
    pub type alias Widget = { rect = Rect2.Rect2, action = Action }

    def left(): Float64 = World.fieldWidth() + 12.0

    def width(): Float64 = 1280.0 - left() - 10.0

    def rect(x: Float64, y: Float64, w: Float64, h: Float64): Rect2.Rect2 = { position = { x = x, y = y }, size = { x = w, y = h } }

    /// スライダーの線の長さ（右に値の字を置く分を空ける）。
    def trackWidth(): Float64 = width() - 90.0

    /// 第 2 章のチップの左端（レイヤーの 4 つとマスクの 4 つ）。
    def chipX(isMask: Bool, j: Int32): Float64 = (if (isMask) left() + 298.0 else left() + 132.0) + Int32.toFloat64(j) * 38.0

    def chipKinds(): List[Kind] = Kind.Hero :: Kind.Enemy :: Kind.EnemyBullet :: Kind.HeroShot :: Nil

    def bits(): List[Int32] = 1 :: 2 :: 4 :: 8 :: Nil

    /// 今の章で押せる物の全部。
    pub def widgets(w: World.World): List[Widget] =
        let tabs = (Mode.Radius :: Mode.LayerMask :: Mode.BossShape :: Mode.SpawnLine :: Nil) |> List.zipWithIndex
            |> List.map(entry -> { rect = rect(left() + Int32.toFloat64(fst(entry)) * 113.0, 10.0, 106.0, 56.0), action = Action.SelectMode(snd(entry)) });
        let toggle = { rect = rect(World.fieldWidth() - 232.0, 12.0, 220.0, 44.0), action = Action.ToggleColliders };
        let slider = (knob, y) -> { rect = rect(left(), y, trackWidth(), 32.0), action = Action.Grab(knob) };
        let own = match w#mode {
            case Mode.Radius    => slider(Knob.HeroRadius, 214.0) :: slider(Knob.BulletRadius, 300.0) :: Nil
            case Mode.LayerMask =>
                chipKinds() |> List.zipWithIndex |> List.flatMap(row -> {
                    let (i, kind) = row;
                    let y = 214.0 + Int32.toFloat64(i) * 46.0;
                    (false :: true :: Nil) |> List.flatMap(isMask -> bits() |> List.zipWithIndex |> List.map(b ->
                        { rect = rect(chipX(isMask, fst(b)), y, 34.0, 38.0), action = Action.FlipBit(kind, isMask, snd(b)) }))
                })
            case Mode.BossShape =>
                let shapes = (BossShape.Circle :: BossShape.Capsule :: BossShape.Polygon :: Nil) |> List.zipWithIndex
                    |> List.map(entry -> { rect = rect(left() + Int32.toFloat64(fst(entry)) * 152.0, 176.0, 144.0, 52.0), action = Action.SetShape(snd(entry)) });
                match Tuning.rec(w#tuning)#bossShape {
                    case BossShape.Circle  => slider(Knob.BossCircleRadius, 290.0) :: shapes
                    case BossShape.Capsule => slider(Knob.BossCapsuleRadius, 290.0) :: shapes
                    case BossShape.Polygon => shapes
                }
            case Mode.SpawnLine =>
                { rect = rect(left(), 184.0, width(), 48.0), action = Action.SetCheck(LineCheck.EveryFrame) }
                    :: { rect = rect(left(), 240.0, width(), 48.0), action = Action.SetCheck(LineCheck.NewOnly) } :: Nil
        };
        toggle :: tabs ::: own

    // ── マウス ──

    /// 押した物を探して動かす。スライダーは押している間ずっと、つまみがマウスの x についてくる。
    pub def handleMouse(frame: App.Frame, w: World.World): World.World =
        let cursor = frame#cursor;
        let w1 =
            if (not frame#mouseClicked) w
            else widgets(w) |> List.find(wd -> isUnder(cursor, wd)) |> Option.map(wd -> press(wd, w)) |> Option.getWithDefault(w);
        match w1#drag {
            case Some(knob) if frame#mouseDown => slide(knob, cursor#x, w1)
            case Some(_)                       => { drag = None | w1 }
            case None                          => w1
        }

    def isUnder(p: Vec2.Vec2, wd: Widget): Bool = match wd#action {
        case Action.Grab(_) => Slider.grabs(p, wd#rect)
        case _              => Rect2.hasPoint(p, wd#rect)
    }

    def press(wd: Widget, w: World.World): World.World = match wd#action {
        case Action.SelectMode(mode)           => World.enterMode(mode, w)
        case Action.Grab(knob)                 => { drag = Some(knob) | w }
        case Action.FlipBit(kind, isMask, bit) => World.flipBit(kind, isMask, bit, w)
        case Action.SetShape(shape)            => World.setBossShape(shape, w)
        case Action.SetCheck(check)            => World.setLineCheck(check, w)
        case Action.ToggleColliders            => World.toggleColliders(w)
    }

    /// つかんでいるスライダーの値を、マウスの x から決め直す。
    def slide(knob: Knob, x: Float64, w: World.World): World.World =
        let (lo, hi) = World.knobRange(knob);
        widgets(w) |> List.find(wd -> wd#action `isGrabOf` knob)
            |> Option.map(wd -> World.setKnob(knob, Slider.valueAt({ min = lo, max = hi, track = wd#rect }, x), w))
            |> Option.getWithDefault(w)

    def isGrabOf(a: Action, knob: Knob): Bool = match a {
        case Action.Grab(k) => k == knob
        case _              => false
    }

    // ── 描く ──

    def z(): Int32 = 60

    /// 章の題（動画の章の題と同じ字。パネルの幅に入らない題は、切れ目で 2 行に分ける）。
    def titleLines(mode: Mode): List[String] = match mode {
        case Mode.Radius    => "絵に触れたのに、なぜ無傷？" :: Nil
        case Mode.LayerMask => "敵の弾は、なぜ敵をすり抜ける？" :: Nil
        case Mode.BossShape => "細長いボスを丸で囲うと？" :: Nil
        case Mode.SpawnLine => "出現ラインを越えた" :: "瞬間だけ知りたい" :: Nil
    }

    def knobLabel(knob: Knob): String = match knob {
        case Knob.HeroRadius        => "自機のコライダーの半径"
        case Knob.BulletRadius      => "敵の弾のコライダーの半径"
        case Knob.BossCircleRadius  => "ボスの円の半径"
        case Knob.BossCapsuleRadius => "カプセルの太さ（半径）"
    }

    def knobColor(knob: Knob): Color = match knob {
        case Knob.HeroRadius        => Look.heroColor()
        case Knob.BulletRadius      => Look.enemyColor()
        case _                      => Look.bossColor()
    }

    pub def view(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let background =
            { at = { x = World.fieldWidth(), y = 0.0 }, item = RawDraw.box({ x = 1280.0 - World.fieldWidth(), y = 720.0 }, Look.panelColor(), z()) }
                :: { at = { x = World.fieldWidth(), y = 0.0 }, item = RawDraw.box({ x = 3.0, y = 720.0 }, Color.rgb(0.30, 0.34, 0.48), z() + 1) } :: Nil;
        let heading = titleLines(w#mode) |> List.zipWithIndex
            |> List.map(entry -> Look.text(atlas, 30.0, Look.textColor(), z() + 1, { x = left(), y = 80.0 + Int32.toFloat64(fst(entry)) * 38.0 }, snd(entry)));
        let widgetItems = widgets(w) |> List.flatMap(wd -> widgetView(atlas, w, wd));
        background ::: heading ::: widgetItems ::: modeView(atlas, w) ::: pairsView(atlas, w) ::: jsonView(atlas, w)

    /// 押せる物 1 つの絵。
    def widgetView(atlas: FontAtlas, w: World.World, wd: Widget): List[Render.PlacedItem] =
        let r = wd#rect;
        let button = (on, label, size) -> {
            let fill = if (on) Look.textColor() else Look.chipOffColor();
            let ink = if (on) Look.panelColor() else Look.dimColor();
            { at = r#position, item = RawDraw.box(r#size, fill, z() + 2) |> Render.rounded(8.0) |> Render.outline(Color.rgb(0.36, 0.40, 0.56), 2.0) }
                :: centeredText(atlas, size, ink, Rect2.center(r), label) :: Nil
        };
        match wd#action {
            case Action.SelectMode(mode) => button(mode == w#mode, Int32.toString(modeNumber(mode)), 36.0)
            case Action.Grab(knob)       =>
                let (lo, hi) = World.knobRange(knob);
                Slider.view(atlas, z() + 2, { label = knobLabel(knob), value = World.knobValue(knob, w), min = lo, max = hi,
                                             track = r, color = knobColor(knob), active = w#drag == Some(knob) })
            case Action.FlipBit(kind, isMask, bit) =>
                let c = Hits.colliderOf(kind, World.fieldWidth(), w#tuning);
                let on = Int32.bitwiseAnd(if (isMask) c#mask else c#layer, bit) != 0;
                button(on, Int32.toString(bit), 26.0)
            case Action.SetShape(shape) =>
                let label = match shape {
                    case BossShape.Circle  => "円"
                    case BossShape.Capsule => "カプセル"
                    case BossShape.Polygon => "多角形"
                };
                button(Tuning.rec(w#tuning)#bossShape == shape, label, 26.0)
            case Action.SetCheck(check) =>
                let label = match check {
                    case LineCheck.EveryFrame => "毎コマ見る（今のリスト）"
                    case LineCheck.NewOnly    => "増えた組だけ見る"
                };
                button(w#lineCheck == check, label, 26.0)
            case Action.ToggleColliders =>
                // 盤の右上に置く（パネルの外）。
                let label = if (w#showColliders) "コライダー: 表示" else "コライダー: 隠す";
                { at = r#position, item = RawDraw.box(r#size, Color.rgb(0.05, 0.06, 0.10), 40) |> Render.fade(0.75) |> Render.rounded(8.0)
                                              |> Render.outline(Look.enemyColor(), 2.0) }
                    :: centeredText(atlas, 24.0, Look.textColor(), Rect2.center(r), label) :: Nil
        }

    def centeredText(atlas: FontAtlas, size: Float64, color: Color, center: Vec2.Vec2, content: String): Render.PlacedItem =
        let s = TextDraw.size(content, atlas, size);
        Look.text(atlas, size, color, z() + 4, { x = center#x - s#x / 2.0, y = center#y - s#y / 2.0 }, content)

    def modeNumber(mode: Mode): Int32 = match mode {
        case Mode.Radius    => 1
        case Mode.LayerMask => 2
        case Mode.BossShape => 3
        case Mode.SpawnLine => 4
    }

    def note(atlas: FontAtlas, y: Float64, content: String): Render.PlacedItem =
        { at = { x = left(), y = y }, item = Render.textWrapped(content, atlas, { fontSize = 24.0, wrapWidth = width(), tint = Look.dimColor(), zIndex = z() + 1 }) }

    /// 章ごとの、押せる物以外の字。
    def modeView(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] = match w#mode {
        case Mode.Radius => note(atlas, 352.0, "白い丸が自機のコライダー。弾は絵ではなく、この丸に入った時だけ当たる。") :: Nil
        case Mode.LayerMask =>
            let header = Look.text(atlas, 24.0, Look.dimColor(), z() + 1, { x = chipX(false, 0), y = 178.0 }, "レイヤー")
                :: Look.text(atlas, 24.0, Look.dimColor(), z() + 1, { x = chipX(true, 0), y = 178.0 }, "マスク") :: Nil;
            let names = chipKinds() |> List.zipWithIndex |> List.flatMap(row -> {
                let (i, kind) = row;
                Look.runs(atlas, 24.0, z() + 1, { x = left(), y = 220.0 + Int32.toFloat64(i) * 46.0 },
                    (Int32.toString(Hits.numberOf(kind)) + " ", Look.kindColor(false, kind)) :: (kindName(kind), Look.textColor()) :: Nil)
            });
            header ::: names ::: note(atlas, 400.0, "FGE では、どちらかのマスクに相手のレイヤーの数字が入っていれば組になる。") :: Nil
        case Mode.BossShape =>
            let yes = Hits.overlapsBoss(w#hero, World.bossAt(), w#tuning);
            let call = Look.runs(atlas, 24.0, z() + 1, { x = left(), y = 352.0 },
                ("checkOverlap", Look.engineColor()) :: ("(", Look.textColor()) :: ("自機の丸", Look.heroColor()) :: (", ", Look.textColor())
                    :: ("ボスの形", Look.bossColor()) :: (")", Look.textColor()) :: Nil);
            let answer = Look.runs(atlas, 36.0, z() + 1, { x = left(), y = 388.0 },
                ("→ ", Look.textColor()) :: (if (yes) ("はい（当たった）", Look.addedColor()) else ("いいえ", Look.textColor())) :: Nil);
            let shapeNote = if (Tuning.rec(w#tuning)#bossShape == BossShape.Polygon) note(atlas, 254.0, "頂点は、絵の輪郭をなぞった 26 個。") :: Nil else Nil;
            shapeNote ::: call ::: answer
        case Mode.SpawnLine =>
            let row = (y, label, pairs, color) ->
                Look.text(atlas, 24.0, Look.dimColor(), z() + 1, { x = left(), y = y + 4.0 }, label)
                    :: tupleRuns(atlas, w, { x = left() + 116.0, y = y }, pairs, color);
            row(306.0, "今のコマ", w#current, None) ::: row(346.0, "前のコマ", w#previous, None)
                ::: row(386.0, "増えた組", w#added, Some(Look.addedColor())) ::: note(atlas, 428.0, "増えた組 = 今のリスト − 前のリスト") :: Nil
    }

    def kindName(kind: Kind): String = match kind {
        case Kind.Hero        => "自機"
        case Kind.Enemy       => "敵"
        case Kind.EnemyBullet => "敵の弾"
        case Kind.HeroShot    => "自分の弾"
        case Kind.SpawnLine   => "出現ライン"
    }

    /// 組のリストを "[(1, 3), (2, 4)×5]" の形で描く。番号はその物の色（color を渡すと全部その色）。
    /// 同じ種類どうしの組は 1 つにまとめて ×数 を付ける（弾は何発もあるため）。
    def tupleRuns(atlas: FontAtlas, w: World.World, at: Vec2.Vec2, pairs: List[(Int32, Int32)], color: Option[Color]): List[Render.PlacedItem] =
        let plain = Option.getWithDefault(Look.textColor(), color);
        let numberColor = kind -> Option.getWithDefault(Look.kindColor(w#mode == Mode.BossShape, kind), color);
        let groups = pairs |> List.map(p -> (Hits.kindOf(fst(p)), Hits.kindOf(snd(p))))
            |> List.foldLeft((counts, key) -> Map.insertWith((x, y) -> x + y, key, 1, counts), Map.empty())
            |> Map.toList;
        let shown = List.take(3, groups);
        let tuple = entry -> {
            let ((a, b), n) = entry;
            ("(", plain) :: (Int32.toString(Hits.numberOf(a)), numberColor(a)) :: (", ", plain) :: (Int32.toString(Hits.numberOf(b)), numberColor(b)) :: (")", plain)
                :: (if (n > 1) ("×${Int32.toString(n)}", plain) :: Nil else Nil)
        };
        let body = shown |> List.map(tuple) |> List.intersperse((", ", plain) :: Nil) |> List.flatten;
        let more = if (List.length(groups) > 3) (", …", plain) :: Nil else Nil;
        Look.runs(atlas, 28.0, z() + 1, at, ("[", plain) :: body ::: more ::: ("]", plain) :: Nil)

    /// detectCollisions が返した、今のコマの組のリスト（全部の章）。
    def pairsView(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        Look.runs(atlas, 24.0, z() + 1, { x = left(), y = 482.0 },
            ("detectCollisions", Look.engineColor()) :: (" の答え（組のリスト）", Look.dimColor()) :: Nil)
            ::: tupleRuns(atlas, w, { x = left(), y = 514.0 }, w#current, None)

    /// 今の値を JSON の形で（スライダーやチップで変えると、ここの数が変わる）。
    def jsonView(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let t = Tuning.rec(w#tuning);
        let n = x -> Int32.toString(Num.roundInt(x));
        let i = Int32.toString;
        let lm = (key, layer, mask) -> "\"${key}\": {\"layer\": ${i(layer)}, \"mask\": ${i(mask)}}";
        let lines = match w#mode {
            case Mode.Radius    => "\"hero\": { \"radius\": ${n(t#heroRadius)} }" :: "\"enemyBullet\": { \"radius\": ${n(t#bulletRadius)} }" :: Nil
            case Mode.LayerMask => lm("hero", t#heroLayer, t#heroMask) :: lm("enemy", t#enemyLayer, t#enemyMask)
                                   :: lm("enemyBullet", t#bulletLayer, t#bulletMask) :: lm("heroShot", t#shotLayer, t#shotMask) :: Nil
            case Mode.BossShape => "\"boss\": { \"shape\": \"${Tuning.bossShapeName(t#bossShape)}\"" :: "  \"circleRadius\": ${n(t#bossCircleRadius)}"
                                   :: "  \"capsuleRadius\": ${n(t#bossCapsuleRadius)} }" :: Nil
            case Mode.SpawnLine => "\"spawnLine\": { \"height\": ${n(t#lineHeight)}" :: "  \"layer\": ${i(t#lineLayer)}, \"mask\": ${i(t#lineMask)} }" :: Nil
        };
        Look.text(atlas, 20.0, Look.dimColor(), z() + 1, { x = left(), y = 564.0 }, "今の値（assets/collision.kind.json）")
            :: (lines |> withCommas |> List.zipWithIndex |> List.map(entry ->
                   Look.text(atlas, 24.0, Look.textColor(), z() + 1, { x = left(), y = 592.0 + Int32.toFloat64(fst(entry)) * 30.0 }, snd(entry))))

    /// 最後の行を除いて、行の終わりに "," を付ける（JSON の並びの形）。
    def withCommas(lines: List[String]): List[String] =
        let last = List.length(lines) - 1;
        lines |> List.zipWithIndex |> List.map(entry -> if (fst(entry) < last) "${snd(entry)}," else snd(entry))
}
