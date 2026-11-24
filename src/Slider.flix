// Slider — つまみを横に引いて数を変える部品（右のパネルで使う）。
// ブラウザ版では JSON の保存即反映が効かないので、値はこのスライダーで変える。
// 描く（view）と、マウスの位置から値を出す（valueAt）が、同じ枠（track）を読む。
mod Slider {
    use fge::{Color, FontAtlas, Num, Rect2, RawDraw, Render, Vec2}

    /// 1 本のスライダー。track は引ける線の枠（左上と大きさ）。
    pub type alias Spec = {
        label = String,
        value = Float64,
        min = Float64,
        max = Float64,
        track = Rect2.Rect2,
        color = Color,
        active = Bool
    }

    /// つまみの位置 x から値へ（線の外は端の値・整数に丸める）。
    pub def valueAt(spec: { min = Float64, max = Float64, track = Rect2.Rect2 }, x: Float64): Float64 =
        let ratio = Num.clamp01((x - spec#track#position#x) / spec#track#size#x);
        Float64.round(Num.lerp(spec#min, spec#max, ratio))

    /// ラベル（線の上）・線・塗った所・つまみ・今の値（線の右）。
    pub def view(atlas: FontAtlas, z: Int32, spec: Spec): List[Render.PlacedItem] =
        let track = spec#track;
        let ratio = Num.clamp01((spec#value - spec#min) / (spec#max - spec#min));
        let midY = track#position#y + track#size#y / 2.0;
        let knobX = track#position#x + track#size#x * ratio;
        let rail = { x = track#size#x, y = 8.0 };
        let valueText = Int32.toString(Num.roundInt(spec#value));
        let knobRadius = if (spec#active) 15.0 else 13.0;
        { at = { x = track#position#x, y = track#position#y - 34.0 }, item = Render.textTinted(spec#label, atlas, 24.0, Color.rgb(0.86, 0.88, 0.95), z) }
            :: { at = { x = track#position#x, y = midY - 4.0 }, item = RawDraw.box(rail, Color.rgb(0.22, 0.25, 0.36), z) |> Render.rounded(4.0) }
            :: { at = { x = track#position#x, y = midY - 4.0 }, item = RawDraw.box({ x = knobX - track#position#x, y = 8.0 }, spec#color, z + 1) |> Render.rounded(4.0) }
            :: RawDraw.circleAt({ x = knobX, y = midY }, knobRadius + 2.0, Color.rgb(0.08, 0.09, 0.14), z + 2)
            :: RawDraw.circleAt({ x = knobX, y = midY }, knobRadius, spec#color, z + 3)
            :: { at = { x = track#position#x + track#size#x + 18.0, y = midY - 18.0 }, item = Render.textTinted(valueText, atlas, 32.0, Color.rgb(1.0, 1.0, 1.0), z) }
            :: Nil

    /// 押した所が、このスライダーをつかめる範囲か（線の上下は少し広めに取る）。
    pub def grabs(p: Vec2.Vec2, track: Rect2.Rect2): Bool = Rect2.hasPoint(p, Rect2.grow(14.0, track))
}
