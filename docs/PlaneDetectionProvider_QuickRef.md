
# PlaneDetectionProvider × RealityView 早わかりメモ
2025-05-18

## 概要
PlaneDetectionProvider で検出した *PlaneAnchor* を **RealityView** 内に “面ピッタリ” 可視化するまでの実装／設計の落とし穴とベストプラクティスを 1 枚にまとめました。  
水平・垂直・傾斜の各平面に対応し、`update` クロージャーで差分反映する **公式推奨パターン** を軸に、行列計算・パフォーマンス・フィルタリングまでを整理しています。

## 1. PlaneDetectionProvider の起動
```swift
let provider = PlaneDetectionProvider(alignments: [.horizontal, .vertical, .slanted])
try await session.run([provider])   // isSupported で端末確認を推奨
```
- `PlaneDetectionProvider.isSupported` で必ずサポート可否を確認する。
- アンカー更新は `for await update in provider.anchorUpdates` で受信。

## 2. アンカーをフィルタする
```swift
guard update.anchor.classification == .table else { continue }
```
`PlaneAnchor.Classification.table` を使うと机レベルの平面だけ抽出できる。

## 3. Extent と Transform の一般化
### 3‑1 キーとなる 2 行列
| 行列 | 役目 |
|------|------|
| `anchor.geometry.extent.anchorFromExtentTransform` | Extent 空間 → アンカー空間 |
| `anchor.originFromAnchorTransform` | アンカー空間 → ワールド空間 |

### 3‑2 ワールド座標への一発変換
```swift
let worldFromExtent =
    anchor.originFromAnchorTransform *
    anchor.geometry.extent.anchorFromExtentTransform
entity.setTransformMatrix(worldFromExtent, relativeTo: nil)
```
この掛け算で **XY 平面メッシュ**を水平・垂直・傾斜すべて正しい向きへ配置できる。

### 3‑3 メッシュ生成は常に XY 平面
```swift
MeshResource.generatePlane(width: anchor.geometry.extent.width,
                           height: anchor.geometry.extent.height)
```
`width:height:` 版は XY 面で法線 +Z、XZ 面は行列でローテート。

## 4. RealityView の make / update 分離
```swift
RealityView { _ in        // make: 初期化 1 回
} update: { content in    // update: State 変化毎
    // 追加
    for (_, e) in planeEntities where e.parent == nil { content.add(e) }
    // 削除
    for c in content.entities {
        if planeEntities[UUID(uuidString: c.name) ?? .init()] == nil {
            content.remove(c)          // 安全に破棄
        }
    }
}
```
- `update` は状態変化時のみ呼ばれ、毎フレームではない。  
- `RealityViewContent.remove(_:)` は子の後始末をすべて処理。

## 5. 更新イベントとサイズ変化
`PlaneAnchor` が拡張されると `extent.width / height` が変わることがある。  
簡単には「旧 Entity を remove → 新しく生成し直し」で対応できる。

## 6. パフォーマンス指針
- 平面検出頻度は低く、`content.entities` の O(n) ループで十分高速。WWDC サンプルでも同手法を採用。  
- 複数百平面でもボトルネックは描画負荷（頂点数）であり、差分ロジックではない。

---

## 付録 A. 汎用 Entity 生成関数
```swift
func makePlaneEntity(anchor: PlaneAnchor, color: Color) -> Entity {
    let mesh = MeshResource.generatePlane(
        width: anchor.geometry.extent.width,
        height: anchor.geometry.extent.height)
    let mat = SimpleMaterial(color: .init(color), roughness: 1)
    let e   = ModelEntity(mesh: mesh, materials: [mat])
    let worldFromExtent =
        anchor.originFromAnchorTransform *
        anchor.geometry.extent.anchorFromExtentTransform
    e.setTransformMatrix(worldFromExtent, relativeTo: nil)
    e.name = anchor.id.uuidString
    return e
}
```

これ一つで alignment を意識せず「面ピッタリ」可視化が可能です。
