// View — 左の盤（背景・敵・弾・自機・ボス・出現ライン）と、その上に重ねるコライダーを描く。右のパネルは Panel。
// 重なり順（z）: 背景 0〜2 → 出現ライン・ボス・敵 10〜12 → 弾 14 → 自機 16 → コライダー 20〜24 → 字 30〜 → パネル 60〜。
// コライダーは「当たり判定に渡している形」そのものを描く。絵とずれている所が、動画で見た「絵と当たりの食い違い」。
mod View {
    use fge::{App, Color, CollisionShape2D, FontAtlas, Num, RawDraw, Render, Vec2}
    use Hits.Kind
    use World.Mode

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        let atlas = ctx#atlas;
        let touching = w#current |> List.flatMap(p -> fst(p) :: snd(p) :: Nil) |> List.toSet;
        let bodies = World.bodiesOf(w);
        let field = backdrop(w#t) ::: stage(w) ::: bulletsAndShots(w) ::: hero(w)
            ::: (if (w#showColliders) bodies |> List.flatMap(b -> colliderView(Set.memberOf(b#id, touching), b)) else Nil)
            ::: tags(atlas, w);
        Render.clippedAll({ position = Vec2.zero(), size = { x = World.fieldWidth(), y = World.fieldHeight() } }, field)
            ::: overlay(atlas, w) ::: Panel.view(atlas, w)

    // ── 背景（縦に流れる空） ──

    /// 背景の絵を盤の幅に合わせて 2 枚縦に並べ、ゆっくり下へ流す。上に暗い幕を 1 枚かけて、弾と字を浮かせる。
    def backdrop(t: Float64): List[Render.PlacedItem] =
        let scale = World.fieldWidth() / 1024.0;
        let tall = 1536.0 * scale;
        let offset = Num.wrapTo(tall, t * 36.0);
        let copy = dy -> { at = { x = World.fieldWidth() / 2.0, y = tall / 2.0 + offset + dy }, item = Render.sprite("bg", 0) |> Render.scaled(scale) };
        copy(0.0) :: copy(0.0 - tall)
            :: { at = Vec2.zero(), item = RawDraw.box({ x = World.fieldWidth(), y = World.fieldHeight() }, Color.rgb(0.03, 0.04, 0.10), 2) |> Render.fade(0.35) }
            :: Nil

    // ── 敵・ボス・出現ライン ──

    def stage(w: World.World): List[Render.PlacedItem] =
        let hitEnemies = w#current |> List.flatMap(p -> fst(p) :: snd(p) :: Nil) |> List.filter(id -> Hits.kindOf(id) == Kind.Enemy) |> List.toSet;
        let enemies = World.enemiesOf(w#mode) |> List.zipWithIndex |> List.map(entry -> {
            let (i, at) = entry;
            let bob = Num.sin(w#t * 2.0 + Int32.toFloat64(i)) * 4.0;
            let sprite = Render.sprite("grunt", 12) |> Render.scaled(0.5);
            // 組になっている間は赤く光らせる（当たったのが分かるように）。
            let look = if (Set.memberOf(Hits.idOf(Kind.Enemy, i), hitEnemies)) sprite |> Render.tinted(Color.rgb(1.0, 0.45, 0.5)) else sprite;
            { at = { x = at#x, y = at#y + bob }, item = look }
        });
        match w#mode {
            case Mode.BossShape => { at = World.bossAt(), item = Render.sprite("boss", 10) |> Render.scaled(Hits.bossWidth() / 800.0) } :: enemies
            case Mode.SpawnLine => spawnLine(w) ::: bossesSent(w)
            case _              => enemies
        }

    /// 出現ライン（青緑の帯）。
    def spawnLine(w: World.World): List[Render.PlacedItem] =
        let h = Tuning.rec(w#tuning)#lineHeight;
        let c = World.lineAt();
        let pulse = 0.35 + 0.15 * Num.sin(w#t * 3.0);
        { at = { x = 0.0, y = c#y - h / 2.0 }, item = RawDraw.box({ x = World.fieldWidth(), y = h }, Look.lineColor(), 10) |> Render.fade(pulse) }
            :: { at = { x = 0.0, y = c#y - 2.0 }, item = RawDraw.box({ x = World.fieldWidth(), y = 4.0 }, Look.lineColor(), 11) }
            :: Nil

    /// 第 4 章で出したボス（上に小さく並べる。8 体を超えた分は数だけ）。
    def bossesSent(w: World.World): List[Render.PlacedItem] =
        List.range(0, Int32.min(8, w#bosses)) |> List.map(i ->
            { at = { x = 90.0 + Int32.toFloat64(Int32.modulo(i, 4)) * 180.0, y = 110.0 + Int32.toFloat64(i / 4) * 70.0 },
              item = Render.sprite("boss", 10) |> Render.scaled(160.0 / 800.0) })

    // ── 弾 ──

    /// 敵の弾は橙の玉（芯を明るく）、自分の弾は黄緑の細い棒。
    def bulletsAndShots(w: World.World): List[Render.PlacedItem] =
        let t = Tuning.rec(w#tuning);
        let bullets = if (w#mode == Mode.Radius or w#mode == Mode.LayerMask) World.bulletsOf(w) else Nil;
        // 玉の芯は明るいクリーム色にして、上に重ねる橙の点線（コライダー）が見えるようにする。
        let ball = b -> (RawDraw.circleAt(b#at, t#bulletRadius + 6.0, Look.enemyColor(), 14) |> Render.overItem(Render.fade(0.55)))
            :: RawDraw.circleAt(b#at, t#bulletRadius + 2.0, Color.rgb(1.0, 0.93, 0.80), 15) :: Nil;
        let shot = s -> RawDraw.boxAt(s#at, { x = t#shotWidth, y = t#shotHeight }, Look.heroColor(), 14) :: Nil;
        List.flatMap(ball, bullets) ::: List.flatMap(shot, w#shots)

    // ── 自機 ──

    /// 自機の絵は、動画と同じく胸のあたり（絵の幅の 46%・高さの 54%）がコライダーの中心に来るように置く。
    // WhyNot: 絵の真ん中をコライダーの中心にしない — この絵は体が中心より少し左下にあり、白い丸が胸から外れて見えた。
    def hero(w: World.World): List[Render.PlacedItem] =
        let size = 144.0;
        let at = { x = w#hero#x + (0.5 - 0.461) * size, y = w#hero#y + (0.5 - 0.537) * size };
        { at = at, item = Render.sprite("hero", 16) |> Render.scaled(size / 192.0) } :: Nil

    // ── コライダー（当たり判定に渡している形） ──

    /// 1 つの物のコライダー。自機は白い丸に赤い縁、ほかは橙の点線。重なっている間は黄色。
    // WhyNot: 自機の白い丸を不透明にしない — スライダーで大きくすると自機の絵が隠れ、「絵より大きい / 小さい」を見比べられなかった。
    def colliderView(touching: Bool, b: Hits.Body): List[Render.PlacedItem] =
        let color = if (touching) Look.touchColor() else Look.enemyColor();
        match (Hits.kindOf(b#id), b#collider#shape) {
            case (Kind.Hero, CollisionShape2D.CircleShape2D(c)) =>
                RawDraw.circleAt(b#at, c#radius + 2.5, if (touching) Look.touchColor() else Color.rgb(0.95, 0.15, 0.2), 22)
                    :: (RawDraw.circleAt(b#at, c#radius, Color.rgb(1.0, 1.0, 1.0), 23) |> Render.overItem(Render.fade(0.5))) :: Nil
            case (_, shape) => Look.dashedLoop(outlineOf(b#at, shape), 2.5, color, 20)
        }

    /// 形の縁の点（点線で結ぶ）。
    def outlineOf(at: Vec2.Vec2, shape: CollisionShape2D): List[Vec2.Vec2] = match shape {
        case CollisionShape2D.CircleShape2D(c) => Look.circlePoints(at, c#radius)
        case CollisionShape2D.RectShape2D(r) =>
            let hw = r#width / 2.0;
            let hh = r#height / 2.0;
            { x = at#x - hw, y = at#y - hh } :: { x = at#x + hw, y = at#y - hh } :: { x = at#x + hw, y = at#y + hh } :: { x = at#x - hw, y = at#y + hh } :: Nil
        case CollisionShape2D.CapsuleShape2D(c) =>
            // 横長のカプセル: 右の半円 → 左の半円 を順になぞる。
            let (a, b) = CollisionShape2D.capsuleSegment(at, c#radius, c#height, c#vertical);
            let arc = (center, startAngle) -> List.range(0, 13) |> List.map(i -> {
                let angle = startAngle + 3.14159 * Int32.toFloat64(i) / 12.0;
                { x = center#x + Num.cos(angle) * c#radius, y = center#y + Num.sin(angle) * c#radius }
            });
            arc(b, 0.0 - 1.5708) ::: arc(a, 1.5708)
        case CollisionShape2D.PolygonShape2D(p) => p#points |> List.map(q -> { x = at#x + q#x, y = at#y + q#y })
        case CollisionShape2D.SlopeShape2D(_) => Nil
    }

    // ── 番号のラベル（動画と同じ番号） ──

    def tags(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let tag = (at, kind, isBoss) -> Look.text(atlas, 24.0, Look.kindColor(isBoss, kind), 26, at, Int32.toString(Hits.numberOf(kind)));
        let heroTag = tag({ x = w#hero#x + 26.0, y = w#hero#y - 44.0 }, Kind.Hero, false);
        let enemyTags = World.enemiesOf(w#mode) |> List.map(e -> tag({ x = e#x + 44.0, y = e#y - 56.0 }, Kind.Enemy, false));
        let rest = match w#mode {
            case Mode.BossShape => tag({ x = World.bossAt()#x - 8.0, y = World.bossAt()#y - Hits.bossHeight() * 0.35 - 34.0 }, Kind.Enemy, true) :: Nil
            case Mode.SpawnLine => Look.text(atlas, 24.0, Look.lineColor(), 26, { x = 16.0, y = World.lineAt()#y - 44.0 }, "5 出現ライン") :: Nil
            case _              => Nil
        };
        heroTag :: enemyTags ::: rest

    // ── 盤の上の字（数と操作） ──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let plate = (at, size) -> { at = at, item = RawDraw.box(size, Color.rgb(0.04, 0.05, 0.09), 30) |> Render.fade(0.72) |> Render.rounded(10.0) };
        let counter = match w#mode {
            case Mode.SpawnLine =>
                plate({ x = 12.0, y = 12.0 }, { x = 250.0, y = 70.0 })
                    :: Look.runs(atlas, 48.0, 31, { x = 28.0, y = 18.0 }, ("ボス ", Look.bossColor()) :: ("${Int32.toString(w#bosses)} 体", Look.textColor()) :: Nil)
            case _ =>
                plate({ x = 12.0, y = 12.0 }, { x = 200.0, y = 58.0 })
                    :: Look.runs(atlas, 36.0, 31, { x = 28.0, y = 20.0 }, ("被弾 ", Look.addedColor()) :: (Int32.toString(w#hits), Look.textColor()) :: Nil)
        };
        let help = "矢印キー: 動く　1〜4: 章　C: コライダー　R: 数を 0 に";
        plate({ x = 12.0, y = World.fieldHeight() - 48.0 }, { x = World.fieldWidth() - 24.0, y = 38.0 })
            :: Look.text(atlas, 22.0, Look.textColor(), 31, { x = 26.0, y = World.fieldHeight() - 44.0 }, help)
            :: counter
}
