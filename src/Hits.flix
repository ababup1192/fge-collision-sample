// Hits — 当たり判定の芯。動画の 4 つの章で使うコードは全部ここにある。
//   第 1 章 … colliderOf の自機の丸（半径はスライダーの値）
//   第 2 章 … colliderOf の layer と mask（チップで切り替える値）
//   第 3 章 … bossShapeOf（ボスを囲う形）と overlapsBoss（checkOverlap）
//   第 4 章 … pairsOf（detectCollisions）と newPairs（増えた組 = 今のリスト − 前のコマのリスト）
// 試すこと: Tuning の値（assets/collision.kind.json）を変えて、組（タプル）のリストがどう変わるかを見る。
mod Hits {
    use fge::{Collision, CollisionShape2D, Vec2}
    use Tuning.BossShape

    /// 物の種類。番号は動画と同じ（1 自機 / 2 敵 / 3 敵の弾 / 4 自分の弾 / 5 出現ライン）。
    /// ボスは「敵」の 1 体として 2 番で数える。
    pub enum Kind with Eq, Order, ToString {
        case Hero
        case Enemy
        case EnemyBullet
        case HeroShot
        case SpawnLine
    }

    /// 動画の番号。
    pub def numberOf(kind: Kind): Int32 = match kind {
        case Kind.Hero        => 1
        case Kind.Enemy       => 2
        case Kind.EnemyBullet => 3
        case Kind.HeroShot    => 4
        case Kind.SpawnLine   => 5
    }

    /// 1 つ 1 つの物の番号（EntityId）。弾は何発もあるので、種類の番号 × 100 万 + 何発目か にする。
    /// 画面に出す組は、この番号を種類の番号へ戻して (1, 3) のように書く。
    pub def idOf(kind: Kind, n: Int32): Int32 = numberOf(kind) * 1000000 + n

    pub def kindOf(id: Int32): Kind = match id / 1000000 {
        case 1 => Kind.Hero
        case 2 => Kind.Enemy
        case 3 => Kind.EnemyBullet
        case 4 => Kind.HeroShot
        case _ => Kind.SpawnLine
    }

    /// 当たり判定に渡す物 1 つ: 番号・中心の位置・コライダー（形 + レイヤー + マスク）。
    pub type alias Body = { id = Int32, at = Vec2.Vec2, collider = Collision.Collider }

    // ── 第 1・2 章: コライダー = 形 + レイヤー（自分は何か）+ マスク（誰とぶつかるか） ──

    /// 種類ごとのコライダー。形の大きさもレイヤーもマスクも Tuning（JSON とスライダー）の値。
    /// 出現ラインの幅は盤の幅に合わせる（width に渡す）。
    pub def colliderOf(kind: Kind, fieldWidth: Float64, tuning: Tuning.Tuning): Collision.Collider =
        let t = Tuning.rec(tuning);
        match kind {
            case Kind.Hero        => { shape = CollisionShape2D.CircleShape2D({ radius = t#heroRadius }), layer = t#heroLayer, mask = t#heroMask }
            case Kind.Enemy       => { shape = CollisionShape2D.CircleShape2D({ radius = t#enemyRadius }), layer = t#enemyLayer, mask = t#enemyMask }
            case Kind.EnemyBullet => { shape = CollisionShape2D.CircleShape2D({ radius = t#bulletRadius }), layer = t#bulletLayer, mask = t#bulletMask }
            case Kind.HeroShot    => { shape = CollisionShape2D.RectShape2D({ width = t#shotWidth, height = t#shotHeight }), layer = t#shotLayer, mask = t#shotMask }
            case Kind.SpawnLine   => { shape = CollisionShape2D.RectShape2D({ width = fieldWidth, height = t#lineHeight }), layer = t#lineLayer, mask = t#lineMask }
        }

    /// detectCollisions が組にするかどうかの決まり（エンジンと同じ式）。
    /// どちらか片方のマスクが相手のレイヤーを含めば組になる。
    pub def masksMatch(a: Collision.Collider, b: Collision.Collider): Bool =
        Int32.bitwiseAnd(a#mask, b#layer) != 0 or Int32.bitwiseAnd(b#mask, a#layer) != 0

    // ── 第 3 章: 細長いボスを囲う形 ──

    /// ボスの絵を何 px の幅で描くか（絵は 3.2:1 の横長）。
    pub def bossWidth(): Float64 = 640.0

    pub def bossHeight(): Float64 = bossWidth() * 246.0 / 800.0

    /// ボスのコライダーの形。円は真ん中から半径・カプセルは絵の幅いっぱいの横長・多角形は絵の輪郭をなぞった頂点。
    pub def bossShapeOf(tuning: Tuning.Tuning): CollisionShape2D =
        let t = Tuning.rec(tuning);
        match t#bossShape {
            case BossShape.Circle  => CollisionShape2D.CircleShape2D({ radius = t#bossCircleRadius })
            case BossShape.Capsule => CollisionShape2D.CapsuleShape2D({ radius = t#bossCapsuleRadius, height = bossWidth() * 0.96, vertical = false })
            case BossShape.Polygon => CollisionShape2D.PolygonShape2D({ points = bossOutline() })
        }

    /// ボスの絵（元の 1200×370 の画素）の輪郭を手でなぞった頂点を、描く大きさ・絵の真ん中が原点へ直した物。
    // WhyNot: 頂点を JSON に出さない — 絵を描き替えた時にだけ直す形で、遊びながら調整する数ではない。
    def bossOutline(): List[Vec2.Vec2] =
        let s = bossWidth() / 1200.0;
        ((20, 185) :: (70, 135) :: (160, 105) :: (225, 65) :: (255, 110) :: (330, 85) :: (430, 80) :: (480, 115) ::
         (700, 115) :: (740, 90) :: (850, 100) :: (880, 125) :: (960, 135) :: (1190, 182) ::
         (960, 232) :: (880, 245) :: (850, 270) :: (740, 280) :: (700, 252) :: (480, 252) :: (430, 290) ::
         (330, 285) :: (255, 262) :: (225, 305) :: (160, 265) :: (70, 235) :: Nil)
            |> List.map(p -> { x = (Int32.toFloat64(fst(p)) - 600.0) * s, y = (Int32.toFloat64(snd(p)) - 185.0) * s })

    /// 自機の丸とボスの形が重なっているか（第 3 章のパネルに「checkOverlap(自機の丸, ボスの形)」として出す）。
    pub def overlapsBoss(hero: Vec2.Vec2, boss: Vec2.Vec2, tuning: Tuning.Tuning): Bool =
        CollisionShape2D.checkOverlap(hero, CollisionShape2D.CircleShape2D({ radius = Tuning.rec(tuning)#heroRadius }), boss, bossShapeOf(tuning))

    // ── 第 4 章: 組（タプル）のリストと、増えた組 ──

    /// 今のコマで重なっている組（タプル）のリスト。同じ組は 1 回だけ・小さい番号が先。
    // WhyNot: 出現ライン（盤の幅いっぱいの矩形）を別に調べない — detectCollisions の升目は一番大きいコライダーに合わせて粗くなり、
    // 近くの物をまとめて比べるようになるが、このサンプルの数（弾 200 発ほど）では遅くならない。
    pub def pairsOf(bodies: List[Body]): List[(Int32, Int32)] =
        let positions = bodies |> List.map(b -> (b#id, b#at)) |> List.toMap;
        let colliders = bodies |> List.map(b -> (b#id, b#collider)) |> List.toMap;
        Collision.detectCollisions(positions, colliders)

    /// 増えた組 = 今のリストにあって、前のコマのリストに無い組。重なり始めた瞬間の 1 コマだけ出る。
    /// WhyNot: 今のリストをそのまま数えない — 重なっている間ずっと毎コマ出るので、ボスが毎コマ 1 体ずつ増える（第 4 章）。
    pub def newPairs(previous: List[(Int32, Int32)], current: List[(Int32, Int32)]): List[(Int32, Int32)] =
        Set.difference(List.toSet(current), List.toSet(previous)) |> Set.toList

    /// 組が「種類 a と種類 b」の組か（順番は問わない）。
    pub def isPairOf(a: Kind, b: Kind, pair: (Int32, Int32)): Bool =
        let (x, y) = pair;
        (kindOf(x) == a and kindOf(y) == b) or (kindOf(y) == a and kindOf(x) == b)

    /// 組が「自機と種類 kind」の組か。
    pub def isHeroWith(kind: Kind, pair: (Int32, Int32)): Bool =
        let (a, b) = pair;
        (kindOf(a) == Kind.Hero and kindOf(b) == kind) or (kindOf(b) == Kind.Hero and kindOf(a) == kind)
}
