// Look — 色と、字・点線を描く小物。色は動画と同じ意味で使う（同じ色 = 同じ物）。
mod Look {
    use fge::{Color, FontAtlas, Num, RawDraw, Render, TextDraw, Vec2}
    use Hits.Kind

    def hex(text: String): Color = Color.hex(text) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    pub def heroColor(): Color = hex("#7fd35a")       // 自機・自分の弾
    pub def lineColor(): Color = hex("#2fc9a0")       // 出現ライン
    pub def bossColor(): Color = hex("#b77dff")       // ボス
    pub def enemyColor(): Color = hex("#ff9a3c")      // 敵・敵の弾・コライダーの点線
    pub def addedColor(): Color = hex("#ff4d6d")      // 増えた組
    pub def engineColor(): Color = hex("#6aa8ff")     // エンジンの関数
    pub def touchColor(): Color = hex("#ffe14d")      // いま触れている所
    pub def textColor(): Color = hex("#e8ecf6")
    pub def dimColor(): Color = hex("#9aa3bd")
    pub def panelColor(): Color = hex("#151a2c")
    pub def chipOffColor(): Color = hex("#262c44")

    /// 種類の色（第 3 章のボスは敵の 1 体だけれど紫で描く）。
    pub def kindColor(isBoss: Bool, kind: Kind): Color = match kind {
        case Kind.Hero        => heroColor()
        case Kind.Enemy       => if (isBoss) bossColor() else enemyColor()
        case Kind.EnemyBullet => enemyColor()
        case Kind.HeroShot    => heroColor()
        case Kind.SpawnLine   => lineColor()
    }

    /// 左上 at に 1 行の字。
    pub def text(atlas: FontAtlas, size: Float64, color: Color, z: Int32, at: Vec2.Vec2, content: String): Render.PlacedItem =
        { at = at, item = Render.textTinted(content, atlas, size, color, z) }

    /// 色の違う字を横につなげて 1 行にする（"(" "1" ", " "3" ")" のように）。
    pub def runs(atlas: FontAtlas, size: Float64, z: Int32, at: Vec2.Vec2, parts: List[(String, Color)]): List[Render.PlacedItem] =
        let step = (acc, part) -> {
            let (x, items) = acc;
            let (content, color) = part;
            (x + TextDraw.width(content, atlas, size), text(atlas, size, color, z, { x = x, y = at#y }, content) :: items)
        };
        snd(List.foldLeft(step, (at#x, Nil), parts))

    /// 閉じた形の縁を点線で描く（点 7px・すき間 5px）。コライダーは絵の上にこの点線で重ねる。
    pub def dashedLoop(points: List[Vec2.Vec2], width: Float64, color: Color, z: Int32): List[Render.PlacedItem] =
        match points {
            case first :: _ =>
                List.zip(points, List.append(List.drop(1, points), first :: Nil)) |> List.flatMap(edge -> {
                    let (a, b) = edge;
                    let length = Vec2.distanceTo(a, b);
                    let pieces = Int32.max(1, Float64.floor(length / 12.0) |> Float64.tryToInt32 |> Option.getWithDefault(1));
                    List.range(0, pieces) |> List.map(i -> {
                        let t0 = Int32.toFloat64(i) / Int32.toFloat64(pieces);
                        let t1 = t0 + 7.0 / 12.0 / Int32.toFloat64(pieces);
                        RawDraw.lineSeg(Vec2.lerp(a, b, t0), Vec2.lerp(a, b, t1), width, color, z)
                    })
                })
            case Nil => Nil
        }

    /// 円周上の点（点線の円に使う）。
    pub def circlePoints(center: Vec2.Vec2, radius: Float64): List[Vec2.Vec2] =
        let n = Int32.max(8, Float64.floor(radius * 6.2832 / 12.0) |> Float64.tryToInt32 |> Option.getWithDefault(8));
        List.range(0, n) |> List.map(i -> {
            let a = 6.2832 * Int32.toFloat64(i) / Int32.toFloat64(n);
            { x = center#x + Num.cos(a) * radius, y = center#y + Num.sin(a) * radius }
        })
}
