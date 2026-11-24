// Tuning — assets/collision.kind.json（コライダーの大きさ・レイヤー・マスク・速さ）を読む。
// 動画の「FGE の表」の値が既定値。make debug で JSON を保存すると、遊んでいる途中でもすぐ変わる。
// 右のパネルのスライダーやチップも同じ値を書き換える（パネルの下に JSON の形で出る）。
// 壊れた JSON・無い欄は既定値で続ける（ゲームは必ず起動する）。
pub mod Tuning {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 欄が多いので 1 case の enum で包む（型検査を速く保つ。中身は rec で取り出す）。
    pub enum Tuning(Rec)

    /// 細長いボスを、どの形のコライダーで囲うか（第 3 章）。
    pub enum BossShape with Eq, ToString {
        case Circle
        case Capsule
        case Polygon
    }

    /// 調整できる値の全部（JSON では物ごとに入れ子。ここでは平らに並べて { x = v | r } で書き換えやすくする）。
    pub type alias Rec = {
        heroRadius = Float64, heroLayer = Int32, heroMask = Int32, heroSpeed = Float64,
        enemyRadius = Float64, enemyLayer = Int32, enemyMask = Int32,
        bulletRadius = Float64, bulletLayer = Int32, bulletMask = Int32, bulletSpeed = Float64,
        shotWidth = Float64, shotHeight = Float64, shotLayer = Int32, shotMask = Int32, shotSpeed = Float64,
        lineHeight = Float64, lineLayer = Int32, lineMask = Int32,
        bossShape = BossShape, bossCircleRadius = Float64, bossCapsuleRadius = Float64
    }

    pub def rec(t: Tuning): Rec = match t { case Tuning.Tuning(r) => r }

    pub def path(): String = "assets/collision.kind.json"

    /// 動画の FGE の表と同じ値（assets/collision.kind.json と同じ値から始まる）。
    pub def defaults(): Tuning = Tuning.Tuning({
        heroRadius = 7.0, heroLayer = 1, heroMask = 6, heroSpeed = 300.0,
        enemyRadius = 38.0, enemyLayer = 2, enemyMask = 8,
        bulletRadius = 9.0, bulletLayer = 4, bulletMask = 0, bulletSpeed = 150.0,
        shotWidth = 6.0, shotHeight = 22.0, shotLayer = 8, shotMask = 0, shotSpeed = 700.0,
        lineHeight = 20.0, lineLayer = 16, lineMask = 1,
        bossShape = BossShape.Circle, bossCircleRadius = 330.0, bossCapsuleRadius = 70.0
    })

    pub def load(p: String): Tuning \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// JSON の文字から Tuning へ。JSON として読めなければ None。
    pub def fromJson(text: String): Option[Tuning] = DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Tuning =
        let d = rec(defaults());
        let hero = objectAt("hero", root);
        let enemy = objectAt("enemy", root);
        let bullet = objectAt("enemyBullet", root);
        let shot = objectAt("heroShot", root);
        let line = objectAt("spawnLine", root);
        let boss = objectAt("boss", root);
        Tuning.Tuning({
            heroRadius = JsonCodec.floatOr("radius", d#heroRadius, hero),
            heroLayer = JsonCodec.intOr("layer", d#heroLayer, hero),
            heroMask = JsonCodec.intOr("mask", d#heroMask, hero),
            heroSpeed = JsonCodec.floatOr("speed", d#heroSpeed, hero),
            enemyRadius = JsonCodec.floatOr("radius", d#enemyRadius, enemy),
            enemyLayer = JsonCodec.intOr("layer", d#enemyLayer, enemy),
            enemyMask = JsonCodec.intOr("mask", d#enemyMask, enemy),
            bulletRadius = JsonCodec.floatOr("radius", d#bulletRadius, bullet),
            bulletLayer = JsonCodec.intOr("layer", d#bulletLayer, bullet),
            bulletMask = JsonCodec.intOr("mask", d#bulletMask, bullet),
            bulletSpeed = JsonCodec.floatOr("speed", d#bulletSpeed, bullet),
            shotWidth = JsonCodec.floatOr("width", d#shotWidth, shot),
            shotHeight = JsonCodec.floatOr("height", d#shotHeight, shot),
            shotLayer = JsonCodec.intOr("layer", d#shotLayer, shot),
            shotMask = JsonCodec.intOr("mask", d#shotMask, shot),
            shotSpeed = JsonCodec.floatOr("speed", d#shotSpeed, shot),
            lineHeight = JsonCodec.floatOr("height", d#lineHeight, line),
            lineLayer = JsonCodec.intOr("layer", d#lineLayer, line),
            lineMask = JsonCodec.intOr("mask", d#lineMask, line),
            bossShape = bossShapeOf(JsonCodec.stringOr("shape", "", boss)) |> Option.getWithDefault(d#bossShape),
            bossCircleRadius = JsonCodec.floatOr("circleRadius", d#bossCircleRadius, boss),
            bossCapsuleRadius = JsonCodec.floatOr("capsuleRadius", d#bossCapsuleRadius, boss)
        })

    /// 入れ子の { } を取り出す。無ければ空（中の欄は全部既定値になる）。
    def objectAt(key: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    /// JSON の "circle" / "capsule" / "polygon" を、読み込む所で 1 回だけ enum にする。
    pub def bossShapeOf(name: String): Option[BossShape] = match name {
        case "circle"  => Some(BossShape.Circle)
        case "capsule" => Some(BossShape.Capsule)
        case "polygon" => Some(BossShape.Polygon)
        case _         => None
    }

    pub def bossShapeName(shape: BossShape): String = match shape {
        case BossShape.Circle  => "circle"
        case BossShape.Capsule => "capsule"
        case BossShape.Polygon => "polygon"
    }

    pub def map(f: Rec -> Rec, t: Tuning): Tuning = Tuning.Tuning(f(rec(t)))
}
