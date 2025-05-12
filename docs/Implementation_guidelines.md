# AR Paper Demo: Tap & Resize 実装指針

このドキュメントは、visionOS 2.0 以降で以下の要件を満たすデモアプリ「AR Paper Demo: Tap & Resize」の実装指針をまとめたものです。

* 検出した平面上に仮想的な用紙を配置する
* 人差し指で平面を物理的にタップして用紙を配置する
* 配置済みの用紙を両手の人差し指でサイズ変更する

---

## 1. セッションの開始

```swift
@State var trackingSession = SpatialTrackingSession()

.task {
  let config = SpatialTrackingSession.Configuration(
    tracking: [.hand, .plane]
  )
  await trackingSession.run(config)
}
```

* `SpatialTrackingSession.run()` で平面検出と手指トラッキングを同時に有効化。

## 2. 平面検出 (AnchorEntity(.plane))

```swift
let planeAnchor = AnchorEntity(
  .plane(.horizontal,
         classification: .any,
         minimumBounds: [0.2, 0.2])
)
arView.scene.anchors.append(planeAnchor)
```

* `.horizontal`＋`classification: .any`＋`minimumBounds` により、条件に合う水平面すべてに自動でアンカーを生成。
* `minimumBounds` を指定しないと微小な平面断片にもアンカーが生成され、ノイズやパフォーマンス低下の原因となる。

## 3. 手指トラッキング (AnchorEntity(.hand))

```swift
let leftTipAnchor = AnchorEntity(
  .hand(.left, location: .indexFingerTip),
  trackingMode: .continuous
)
arView.scene.anchors.append(leftTipAnchor)
```

* `AnchorEntity(.hand)` は ARKit の Hand Tracking Provider と連携し、人差し指先の座標を毎フレーム更新。

## 4. physicsSimulation 設定

```swift
leftTipAnchor.anchoring.physicsSimulation = .none
```

* デフォルトの `.isolated` では指先の衝突判定が他エンティティと切り離されるため、`.none` にしてシーン共通の物理空間に参加させる。

## 5. 衝突判定の追加

```swift
planeEntity.generateCollisionShapes(recursive: true)
paperEntity.generateCollisionShapes(recursive: true)

let tipSphere = ModelEntity(mesh: .generateSphere(radius: 0.01))
tipSphere.generateCollisionShapes(recursive: false)
leftTipAnchor.addChild(tipSphere)

scene.subscribe(to: CollisionEvents.Began.self, on: tipSphere) { event in
  if event.entityB == planeEntity {
    placePaper(at: tipSphere.position)
  }
}
```

* `generateCollisionShapes()` で衝突コンポーネントを生成。
* `CollisionEvents.Began` で指先と平面／紙の当たり判定を検出し、配置やリサイズ処理に繋げる。

## 6. 仮想用紙の配置

```swift
func placePaper(at position: SIMD3<Float>) {
  let size = SIMD2<Float>(0.21, 0.297)
  let mesh = MeshResource.generatePlane(width: size.x, depth: size.y)
  let material = SimpleMaterial(color: .white.withAlphaComponent(0.9), isMetallic: false)
  let paper = ModelEntity(mesh: mesh, materials: [material])
  paper.generateCollisionShapes(recursive: true)

  let paperAnchor = AnchorEntity(anchor: planeAnchor.anchor!)
  paperAnchor.addChild(paper)
  paper.position = position
  scene.addAnchor(paperAnchor)
}
```

* A4 相当サイズの平面メッシュを生成し、`AnchorEntity` に追加。

## 7. 両手人差し指によるリサイズ

```swift
var initialDistance: Float?

scene.subscribe(to: CollisionEvents.Began.self) { event in
  if bothTipsCollidingWith(paper) {
    initialDistance = distance(leftTipAnchor.position, rightTipAnchor.position)
  }
}

scene.subscribe(to: SceneEvents.Update.self) { _ in
  guard let base = initialDistance,
        bothTipsCollidingWith(paper) else { return }
  let current = distance(leftTipAnchor.position, rightTipAnchor.position)
  let factor = current / base
  paper.scale = SIMD3<Float>(repeating: factor)
}
```

* 両手の人差し指が同時に用紙に触れた瞬間の距離を基準に、`SceneEvents.Update` で毎フレームスケールを更新。

## 8. minimumBounds の役割

* 指定しないと微小な面にもアンカーが生成されノイズが増加。
* `minimumBounds: [0.2, 0.2]` 程度を指定すると、手の届く十分な広さの面だけを対象にできる。

---

以上が、AR Paper Demo: Tap & Resize における用紙配置とリサイズ機能を実現するための実装まとめです。
