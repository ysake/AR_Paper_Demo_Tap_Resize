# AR Paper Demo: Tap & Resize 実装指針

このドキュメントは、visionOS 2.0 以降で以下の要件を満たすデモアプリ「AR Paper Demo: Tap & Resize」の実装指針をまとめたものです。

* 検出した平面上に仮想的な用紙を配置する
* 人差し指で平面を物理的にタップして用紙を配置する
* 配置済みの用紙を両手の人差し指でサイズ変更する

---

## 【重要な知見】visionOSでの平面検出・可視化の現状
- visionOSのRealityKit/ARKitにはiOSのARPlaneAnchorは存在しない。
- 平面検出・可視化・イベント取得にはPlaneDetectionProviderとPlaneAnchorを利用するのが推奨パターン。
- PlaneAnchorはextent（平面サイズ）やalignment（向き）などのプロパティを持つため、検出した平面の大きさ・形状に一致するMeshResource.generatePlaneを生成できる。
- これにより「検出した平面全体に一致する半透明の面」の可視化が可能。
- PlaneDetectionProviderの利用にSpatialTrackingSessionは必須ではない。
- ただし、手指トラッキング（HandTrackingProvider）を利用する場合は、SpatialTrackingSessionを使うことも選択肢となる。
- 今後のAPI拡張やvisionOSアップデートで状況が変わる可能性があるため、最新情報を随時確認することが重要。

---

## 【補足知見】AnchorEntity(.plane)の限界について
- RealityKitのAnchorEntity(.plane)は、iOSのARPlaneAnchorのようなextent（平面サイズ）やboundary（境界情報）を持たない。
- そのため、AnchorEntity(.plane)単体では「検出した平面の正確な大きさ・形状に合わせた可視化」や「平面上の正確な衝突位置取得」はできない。
- 今後のステップで「平面と指の衝突位置に紙を配置」などの高度なAR体験を実現するには、PlaneDetectionProvider＋PlaneAnchor（extentを持つ）を使う方式が必須となる。

---

## 1. 平面検出の開始（PlaneDetectionProvider）

```swift
let planeDetectionProvider = PlaneDetectionProvider()
planeDetectionProvider.start()
```

* PlaneDetectionProviderをインスタンス化し、start()で平面検出を開始する。
* 検出イベントやPlaneAnchorの取得は、PlaneDetectionProviderのイベントやクエリを利用する。

---

## 2. 平面検出と可視化（PlaneDetectionProvider + PlaneAnchor）

```swift
// PlaneDetectionProviderで平面検出を有効化した状態で、
// 検出されたPlaneAnchorごとに以下の処理を行う

let extent = planeAnchor.extent // [width, depth]
let mesh = MeshResource.generatePlane(width: extent.x, depth: extent.y)
let material = SimpleMaterial(color: .blue.withAlphaComponent(0.3), isMetallic: false)
let planeEntity = ModelEntity(mesh: mesh, materials: [material])
planeEntity.position = .zero
planeAnchor.addChild(planeEntity)
scene.anchors.append(planeAnchor)
```

* PlaneAnchorのextentを使うことで、検出した平面の大きさに一致した可視化が可能。
* 平面の更新イベント（サイズ変化など）があれば、planeEntityのスケールやメッシュを動的に更新する。

---

## 3. 手指トラッキング（HandTrackingProvider or SpatialTrackingSession）

- visionOSではHandTrackingProviderを直接利用する方法と、SpatialTrackingSession経由で手指トラッキングを有効化する方法がある。
- どちらの方式も選択肢となるが、用途やAPI設計に応じて使い分ける。

---

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
