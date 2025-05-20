//
//  ImmersiveView.swift
//  ARPaperDemo
//
//  机などの水平面を検出し、現実空間に“面ピッタリ”の半透明パネルを重ねて表示するビュー。
//  PlaneDetectionProvider + RealityView(rootEntity方式) の標準実装例。
//
//  【設計方針・Tips・設計経緯まとめ】
//  - PlaneDetectionProvider で .horizontal 平面(机)のみ検出
//  - RealityView の make クロージャのみで rootEntity を add
//  - 検出平面は rootEntity の子として管理（updateクロージャは使わない）
//  - 検出面の追加/更新/削除は planeEntities と rootEntity で一元管理
//  - メッシュ生成・配置はエクステント座標→世界座標変換行列で正確に行う
//  - rootEntity方式は、RealityViewのupdateクロージャを使わずに平面管理が完結し、シンプルでバグが少ない
//  - 複数平面の追加/削除/更新もplaneEntitiesとrootEntityだけで一元管理できる
//  - 検出面の色やマテリアルはmakeEntityで自由にカスタマイズ可能
//  - alignmentsやclassificationを変えれば床・壁・天井にも応用できる
//  - 「PlaneDetectionProviderのイベントの度に全ての平面Entityを再生成し直す」方式は、
//    平面数が多い場合にパフォーマンス低下の懸念があった。
//  - そのため、PlaneDetectionProviderが提供する「追加・更新・削除」イベントを活用し、
//    必要なEntityのみを個別に生成・更新・削除する現方式に移行した。

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct ImmersiveView: View {
    // ARKitセッション本体。Viewのライフサイクルに合わせて管理
    @State private var session = ARKitSession()
    // 検出した平面アンカーIDごとに対応するModelEntityを保持
    @State private var planeEntities = [UUID: ModelEntity]()   // Anchor ID ➜ ModelEntity
    // RealityView直下に配置するrootEntity。全ての平面Entityの親
    @State private var rootEntity = Entity()

    var body: some View {
        RealityView { content in
            // RealityKitContentのImmersiveエンティティ（背景や装飾用）を一度だけadd
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle),
               !content.entities.contains(immersiveContentEntity) {
                content.add(immersiveContentEntity)
            }
            // rootEntityをRealityView直下にadd（以降はrootEntity配下で平面を管理）
            content.add(rootEntity)
        }
        // View表示時に平面検出タスクを起動
        .task { await runPlaneDetection() }
    }

    /// 平面検出プロバイダを起動し、アンカーの追加/更新/削除イベントを監視
    private func runPlaneDetection() async {
        // 端末が平面検出対応か事前にチェック
        guard PlaneDetectionProvider.isSupported else { return }
        let provider = PlaneDetectionProvider(alignments: [.horizontal]) // 水平面のみ
        do {
            try await session.run([provider])
            // 検出アンカーの更新を非同期で逐次受信
            for await update in provider.anchorUpdates {
                // テーブル面のみを対象とする（床や壁は除外）
                guard update.anchor.classification == .table else { continue }

                switch update.event {
                case .added:
                    // 新規検出: Entity生成しrootEntity配下に追加
                    let newEntity = makeEntity(for: update.anchor, color: .cyan.opacity(0.35))
                    planeEntities[update.anchor.id] = newEntity
                    rootEntity.addChild(newEntity)
                case .updated:
                    // 既存平面の形状・位置更新: Entityを再配置
                    guard let updatingEntity = planeEntities[update.anchor.id] else { continue }
                    updateEntity(updatingEntity, with: update.anchor)
                case .removed:
                    // 平面消失: EntityをrootEntity配下から削除
                    guard let entity = planeEntities.removeValue(forKey: update.anchor.id) else { continue }
                    entity.removeFromParent()
                }
            }
        } catch {
            print("ARKitSession error:", error)
        }
    }

    /// PlaneAnchorから“面ピッタリ”のModelEntityを生成
    /// - anchor: 検出した平面アンカー
    /// - color: 表示色（半透明推奨）
    private func makeEntity(for anchor: PlaneAnchor, color: Color) -> ModelEntity {
        // RealityKitのMeshResourceは常にXY平面で生成
        let mesh = MeshResource.generatePlane(
            width: anchor.geometry.extent.width,
            height: anchor.geometry.extent.height
        )
        let material = SimpleMaterial(color: .init(color), roughness: 1, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // エクステント座標→世界座標変換行列で正しい位置・向きに配置
        let worldFromExtent =
                anchor.originFromAnchorTransform
              * anchor.geometry.extent.anchorFromExtentTransform
        entity.setTransformMatrix(worldFromExtent, relativeTo: nil)

        return entity
    }
    
    /// 既存Entityの形状・位置・向きをPlaneAnchorに合わせて更新
    /// - entity: 更新対象のModelEntity
    /// - anchor: 最新のPlaneAnchor
    private func updateEntity(_ entity: ModelEntity, with anchor: PlaneAnchor) {
        // サイズが大きく変わった時だけメッシュを再生成（小変化は行列のみ更新）
        let newExt = anchor.geometry.extent
        if abs(entity.transform.scale.x - newExt.width) > 0.02 ||
            abs(entity.transform.scale.z - newExt.height) > 0.02
        {
            entity.model?.mesh = MeshResource.generatePlane(
                width: newExt.width,
                height: newExt.height
            )
        }

        // 行列更新で“面ピッタリ”を維持
        let worldFromExtent =
                anchor.originFromAnchorTransform
              * anchor.geometry.extent.anchorFromExtentTransform
        entity.setTransformMatrix(worldFromExtent, relativeTo: nil)
    }
}
