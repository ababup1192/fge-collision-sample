// 当たり判定の芯（Hits）と、JSON の読み込み（Tuning）のテスト。
mod TestHits {
    use fge::App

    @Test
    def testBrokenJsonIsNone(): Unit \ Assert =
        Assert.assertEq(expected = None, Tuning.fromJson("{ broken") |> Option.map(t -> Tuning.rec(t)#heroRadius))

    @Test
    def testJsonOverridesHeroRadius(): Unit \ Assert =
        Assert.assertEq(expected = Some(12.0),
            Tuning.fromJson("{\"hero\": {\"radius\": 12}}") |> Option.map(t -> Tuning.rec(t)#heroRadius))

    @Test
    def testNewPairsKeepsOnlyPairsNotInPreviousFrame(): Unit \ Assert =
        Assert.assertEq(expected = (1, 5) :: Nil, Hits.newPairs((1, 3) :: Nil, (1, 3) :: (1, 5) :: Nil))

    @Test
    def testClickingRightEndOfHeroSliderSetsMaxRadius(): Unit \ Assert =
        let frame = { cursor = { x = 1180.0, y = 230.0 }, mouseClicked = true, mouseDown = true, dt = 1.0 / 60.0 | App.emptyFrame() };
        let w = World.step(frame, World.initial(Tuning.defaults()));
        Assert.assertEq(expected = 60.0, Tuning.rec(w#tuning)#heroRadius)

    @Test
    def testEnemyBulletDoesNotPairWithEnemyByDefault(): Unit \ Assert =
        let collider = kind -> Hits.colliderOf(kind, 800.0, Tuning.defaults());
        Assert.assertEq(expected = false, Hits.masksMatch(collider(Hits.Kind.Enemy), collider(Hits.Kind.EnemyBullet)))
}
