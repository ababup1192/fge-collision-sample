// World — 遊びの状態と、1 コマ進める規則（純粋）。
// 毎コマ: キーとマウスを読む → 自機と弾を動かす → Hits.pairsOf で組のリストを作る → 増えた組で数を数える。
// 弾の位置は時刻だけから決める（bulletsOf）。同じ時刻なら毎回同じ弾幕になるので、動画と見比べやすい。
mod World {
    use fge::{App, GameEngine, Num, Vec2}
    use Hits.Kind
    use Tuning.BossShape

    /// 動画の章。キーの 1〜4 と、パネルの上のタブで切り替える。
    pub enum Mode with Eq, ToString {
        case Radius      // 第 1 章「絵に触れたのに、なぜ無傷？」
        case LayerMask   // 第 2 章「敵の弾は、なぜ敵をすり抜ける？」
        case BossShape   // 第 3 章「細長いボスを丸で囲うと？」
        case SpawnLine   // 第 4 章「出現ラインを越えた瞬間だけ知りたい」
    }

    /// 第 4 章で、ボスを出すときに見るリスト。
    pub enum LineCheck with Eq, ToString {
        case EveryFrame  // 毎コマ、今のリストを見る（重なっている間ずっと出る）
        case NewOnly     // 増えた組だけ見る（越えた瞬間の 1 コマだけ出る）
    }

    /// スライダーで動かす値。
    pub enum Knob with Eq, ToString {
        case HeroRadius
        case BulletRadius
        case BossCircleRadius
        case BossCapsuleRadius
    }

    /// 自分の弾（第 2 章）。自機の位置から撃つので、時刻だけでは決まらず状態に持つ。
    pub type alias Shot = { id = Int32, at = Vec2.Vec2 }

    /// 遊びの状態。
    /// tuning は JSON から読んだ値に、スライダーとチップで手を加えた今の値（保存すると JSON の値で置き直す）。
    // WhyNot: 章ごとの値（shots・bosses・lineCheck）を章の enum の中に分けない — 1 つの record で全部見渡せる方を、
    // サンプルの読みやすさのために選んだ。使わない章では空のまま。
    pub type alias World = {
        t = Float64,
        mode = Mode,
        tuning = Tuning.Tuning,
        hero = Vec2.Vec2,
        heroLean = Float64,                // 横へ動いている向き（-1 左・0 止まっている・1 右）。絵の向きに使う
        shots = List[Shot],
        shotCount = Int32,
        shotTimer = Float64,
        previous = List[(Int32, Int32)],   // 前のコマの組のリスト
        current = List[(Int32, Int32)],    // 今のコマの組のリスト（detectCollisions の答え）
        added = List[(Int32, Int32)],      // 増えた組（今 − 前）
        hits = Int32,                      // 被弾の数（自機と敵・敵の弾の組が増えた回数）
        bosses = Int32,                    // 第 4 章で出したボスの数
        lineCheck = LineCheck,
        showColliders = Bool,
        drag = Option[Knob]
    }

    // ── 盤（左の弾幕の場所）の大きさ ──

    pub def fieldWidth(): Float64 = 800.0

    pub def fieldHeight(): Float64 = 720.0

    pub def initial(tuning: Tuning.Tuning): World =
        enterMode(Mode.Radius, { t = 0.0, mode = Mode.Radius, tuning = tuning, hero = Vec2.zero(), heroLean = 0.0,
          shots = Nil, shotCount = 0, shotTimer = 0.0, previous = Nil, current = Nil, added = Nil,
          hits = 0, bosses = 0, lineCheck = LineCheck.EveryFrame, showColliders = true, drag = None })

    /// 章に入る: 自機を章の始めの位置へ置き、数とリストを 0 から数え直す。
    pub def enterMode(mode: Mode, w: World): World =
        { mode = mode, hero = heroStart(mode), shots = Nil, previous = Nil, current = Nil, added = Nil,
          hits = 0, bosses = 0, drag = None | w }

    def heroStart(mode: Mode): Vec2.Vec2 = match mode {
        case Mode.Radius    => { x = 400.0, y = 560.0 }
        case Mode.LayerMask => { x = 400.0, y = 600.0 }
        case Mode.BossShape => { x = 400.0, y = 150.0 }   // 円の隅（ボスの絵には触れていない所）
        case Mode.SpawnLine => { x = 400.0, y = 520.0 }
    }

    /// JSON を保存し直した時: 値だけ置き直す（自機の位置や数はそのまま）。
    pub def withTuning(tuning: Tuning.Tuning, w: World): World = { tuning = tuning | w }

    // ── 敵・ボス・出現ラインの置き場所 ──

    /// 章ごとの敵の中心。
    pub def enemiesOf(mode: Mode): List[Vec2.Vec2] = match mode {
        case Mode.Radius    => { x = 400.0, y = 150.0 } :: Nil
        case Mode.LayerMask => { x = 170.0, y = 170.0 } :: { x = 400.0, y = 250.0 } :: { x = 630.0, y = 170.0 } :: Nil
        case _              => Nil
    }

    pub def bossAt(): Vec2.Vec2 = { x = 400.0, y = 420.0 }

    /// 出現ラインの中心（盤の幅いっぱいの横線）。
    pub def lineAt(): Vec2.Vec2 = { x = fieldWidth() / 2.0, y = 300.0 }

    // ── 敵の弾（時刻だけから決まる輪の弾幕） ──

    /// 時刻 t に盤の中にある敵の弾。敵ごとに period 秒おきに n 発の輪を撃ち、輪は少しずつ回る。
    pub def bulletsOf(w: World): List[Hits.Body] =
        let collider = Hits.colliderOf(Kind.EnemyBullet, fieldWidth(), w#tuning);
        let speed = Tuning.rec(w#tuning)#bulletSpeed;
        let (period, n) = if (w#mode == Mode.Radius) (0.55, 14) else (1.1, 8);
        let lifetime = 1100.0 / Float64.max(speed, 1.0);
        let newest = Float64.floor(w#t / period) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        let oldest = Int32.max(0, newest - (Float64.ceil(lifetime / period) |> Float64.tryToInt32 |> Option.getWithDefault(0)));
        enemiesOf(w#mode) |> List.zipWithIndex |> List.flatMap(entry -> {
            let (e, origin) = entry;
            List.range(oldest, newest + 1) |> List.flatMap(k -> {
                let age = w#t - Int32.toFloat64(k) * period;
                List.range(0, n) |> List.filterMap(i -> {
                    let angle = 3.14159265 * 2.0 * Int32.toFloat64(i) / Int32.toFloat64(n) + Int32.toFloat64(k) * 0.37 + Int32.toFloat64(e) * 1.1;
                    let at = { x = origin#x + Num.cos(angle) * speed * age, y = origin#y + Num.sin(angle) * speed * age };
                    // 何発目か: 敵 e の k 輪目の i 発目。k は 1000 輪で一回りさせる（番号が種類の桁へあふれない）。
                    let id = Hits.idOf(Kind.EnemyBullet, (Int32.modulo(k, 1000) * 8 + e) * n + i);
                    if (age >= 0.0 and insideField(40.0, at)) Some({ id = id, at = at, collider = collider }) else None
                })
            })
        })

    def insideField(margin: Float64, p: Vec2.Vec2): Bool =
        p#x > -margin and p#x < fieldWidth() + margin and p#y > -margin and p#y < fieldHeight() + margin

    // ── 当たり判定に渡す物の一覧 ──

    /// 今の章の全部の物（自機・敵・弾・ボス・出現ライン）。
    pub def bodiesOf(w: World): List[Hits.Body] =
        let collider = kind -> Hits.colliderOf(kind, fieldWidth(), w#tuning);
        let hero = { id = Hits.idOf(Kind.Hero, 0), at = w#hero, collider = collider(Kind.Hero) };
        let enemies = enemiesOf(w#mode) |> List.zipWithIndex
            |> List.map(entry -> { id = Hits.idOf(Kind.Enemy, fst(entry)), at = snd(entry), collider = collider(Kind.Enemy) });
        let shots = w#shots |> List.map(s -> { id = s#id, at = s#at, collider = collider(Kind.HeroShot) });
        let rest = match w#mode {
            case Mode.BossShape =>
                // ボスは「敵」の 1 体（レイヤーとマスクは敵の値・形だけボスの形）。
                { id = Hits.idOf(Kind.Enemy, 0), at = bossAt(), collider = { shape = Hits.bossShapeOf(w#tuning) | collider(Kind.Enemy) } } :: Nil
            case Mode.SpawnLine => { id = Hits.idOf(Kind.SpawnLine, 0), at = lineAt(), collider = collider(Kind.SpawnLine) } :: Nil
            case _              => bulletsOf(w)
        };
        hero :: enemies ::: shots ::: rest

    // ── 1 コマ進める ──

    /// 毎コマの系。キー → マウス → 動き → 当たり判定 の順。
    pub def step(frame: App.Frame, w: World): World =
        w |> keys(frame) |> Panel.handleMouse(frame) |> move(frame) |> collide

    def keys(frame: App.Frame, w: World): World =
        let pressed = key -> App.justPressed(key, frame);
        let modeKey = (GameEngine.Key.Digit1, Mode.Radius) :: (GameEngine.Key.Digit2, Mode.LayerMask)
            :: (GameEngine.Key.Digit3, Mode.BossShape) :: (GameEngine.Key.Digit4, Mode.SpawnLine) :: Nil;
        let w1 = modeKey |> List.find(entry -> pressed(fst(entry))) |> Option.map(entry -> enterMode(snd(entry), w)) |> Option.getWithDefault(w);
        let w2 = if (pressed(GameEngine.Key.C)) { showColliders = not w1#showColliders | w1 } else w1;
        if (pressed(GameEngine.Key.R)) { hits = 0, bosses = 0 | w2 } else w2

    /// 矢印キー（か WASD）で自機を動かし、自分の弾を進める。
    def move(frame: App.Frame, w: World): World =
        let held = (a, b) -> App.isDown(a, frame) or App.isDown(b, frame);
        let axis = (neg, pos) -> (if (pos) 1.0 else 0.0) - (if (neg) 1.0 else 0.0);
        let dx = axis(held(GameEngine.Key.Left, GameEngine.Key.A), held(GameEngine.Key.Right, GameEngine.Key.D));
        let dy = axis(held(GameEngine.Key.Up, GameEngine.Key.W), held(GameEngine.Key.Down, GameEngine.Key.S));
        let speed = Tuning.rec(w#tuning)#heroSpeed * frame#dt;
        let hero = { x = Num.clamp(10.0, fieldWidth() - 10.0, w#hero#x + dx * speed),
                     y = Num.clamp(10.0, fieldHeight() - 10.0, w#hero#y + dy * speed) };
        moveShots(frame#dt, { t = w#t + frame#dt, hero = hero, heroLean = dx | w })

    /// 第 2 章だけ、自機が 0.12 秒おきに上へ弾を撃つ。
    def moveShots(dt: Float64, w: World): World =
        if (w#mode != Mode.LayerMask) w
        else {
            let travel = Tuning.rec(w#tuning)#shotSpeed * dt;
            let moved = w#shots |> List.map(s -> { at = { x = s#at#x, y = s#at#y - travel } | s }) |> List.filter(s -> s#at#y > -30.0);
            let timer = w#shotTimer + dt;
            if (timer < 0.12) { shots = moved, shotTimer = timer | w }
            else {
                let shot = { id = Hits.idOf(Kind.HeroShot, Int32.modulo(w#shotCount, 100000)), at = { x = w#hero#x, y = w#hero#y - 30.0 } };
                { shots = shot :: moved, shotCount = w#shotCount + 1, shotTimer = 0.0 | w }
            }
        }

    /// 組のリストを作り直し、増えた組で被弾とボスの数を数える。
    def collide(w: World): World =
        let current = Hits.pairsOf(bodiesOf(w));
        let added = Hits.newPairs(w#current, current);
        let count = (kind, pairs) -> pairs |> List.count(Hits.isHeroWith(kind));
        let hit = count(Kind.Enemy, added) + count(Kind.EnemyBullet, added);
        let seen = match w#lineCheck {
            case LineCheck.EveryFrame => current
            case LineCheck.NewOnly    => added
        };
        let bosses = if (w#mode == Mode.SpawnLine) w#bosses + count(Kind.SpawnLine, seen) else w#bosses;
        // 敵に当たった自分の弾は消える。
        let spent = current |> List.flatMap(p -> fst(p) :: snd(p) :: Nil) |> List.toSet;
        let shots = w#shots |> List.filter(s -> not Set.memberOf(s#id, spent));
        { previous = w#current, current = current, added = added, hits = w#hits + hit, bosses = bosses, shots = shots | w }

    // ── パネルが書き換える値 ──

    /// スライダーの範囲（最小, 最大）。
    pub def knobRange(knob: Knob): (Float64, Float64) = match knob {
        case Knob.HeroRadius        => (2.0, 60.0)
        case Knob.BulletRadius      => (2.0, 40.0)
        case Knob.BossCircleRadius  => (40.0, 360.0)
        case Knob.BossCapsuleRadius => (10.0, 120.0)
    }

    pub def knobValue(knob: Knob, w: World): Float64 =
        let t = Tuning.rec(w#tuning);
        match knob {
            case Knob.HeroRadius        => t#heroRadius
            case Knob.BulletRadius      => t#bulletRadius
            case Knob.BossCircleRadius  => t#bossCircleRadius
            case Knob.BossCapsuleRadius => t#bossCapsuleRadius
        }

    pub def setKnob(knob: Knob, v: Float64, w: World): World =
        let f = t -> match knob {
            case Knob.HeroRadius        => { heroRadius = v | t }
            case Knob.BulletRadius      => { bulletRadius = v | t }
            case Knob.BossCircleRadius  => { bossCircleRadius = v | t }
            case Knob.BossCapsuleRadius => { bossCapsuleRadius = v | t }
        };
        { tuning = Tuning.map(f, w#tuning) | w }

    /// 第 2 章のチップ: kind のレイヤー（isMask = false）かマスク（true）の、その数字（1・2・4・8）を入れる / 外す。
    pub def flipBit(kind: Kind, isMask: Bool, bit: Int32, w: World): World =
        let c = Hits.colliderOf(kind, fieldWidth(), w#tuning);
        let flip = v -> Int32.bitwiseXor(v, bit);
        let layer = if (isMask) c#layer else flip(c#layer);
        let mask = if (isMask) flip(c#mask) else c#mask;
        let f = t -> match kind {
            case Kind.Hero        => { heroLayer = layer, heroMask = mask | t }
            case Kind.Enemy       => { enemyLayer = layer, enemyMask = mask | t }
            case Kind.EnemyBullet => { bulletLayer = layer, bulletMask = mask | t }
            case Kind.HeroShot    => { shotLayer = layer, shotMask = mask | t }
            case Kind.SpawnLine   => { lineLayer = layer, lineMask = mask | t }
        };
        { tuning = Tuning.map(f, w#tuning) | w }

    pub def setBossShape(shape: BossShape, w: World): World =
        { tuning = Tuning.map(t -> { bossShape = shape | t }, w#tuning) | w }

    pub def setLineCheck(check: LineCheck, w: World): World = { lineCheck = check, bosses = 0 | w }

    pub def toggleColliders(w: World): World = { showColliders = not w#showColliders | w }
}
