# アーキテクチャ

本アプリの主要コンポーネントとフロー:

1. **SpatialTrackingSession**
   - 平面検出と手指トラッキングを同時に実行
2. **AnchorEntity(.plane)**
   - 検出された水平面に自動でアンカーを生成
3. **AnchorEntity(.hand)**
   - 人差し指先の座標取得用アンカー
4. **CollisionComponent**
   - 指先と平面／紙の当たり判定を行い、配置・リサイズを検知
5. **SceneEvents.Update**
   - 両手指先間距離から用紙のスケールを動的に更新

各コンポーネントの詳細はコードコメントを参照してください。
