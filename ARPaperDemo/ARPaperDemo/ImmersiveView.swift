//
//  ImmersiveView.swift
//  ARPaperDemo
//
//  Created by 酒井雄太 on 2025/05/13.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct ImmersiveView: View {
    @State private var session = ARKitSession()
    @State private var planeEntities = [UUID: Entity]()   // Anchor ID ➜ Entity
    @State private var rootEntity = Entity()

    var body: some View {
        RealityView { content in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle),
               !content.entities.contains(immersiveContentEntity) {
                content.add(immersiveContentEntity)
            }
            content.add(rootEntity)
        } update: { content in
            // planeEntities全てを再描画する(パフォーマンスの懸念あり)
            rootEntity.children.removeAll()
            for (_, entity) in planeEntities {
                rootEntity.addChild(entity)
            }
        }
        .task { await runPlaneDetection() }
    }

    private func runPlaneDetection() async {
        guard PlaneDetectionProvider.isSupported else { return }
        let provider = PlaneDetectionProvider(alignments: [.horizontal])
        do {
            try await session.run([provider])
            for await update in provider.anchorUpdates {
                switch update.event {
                case .added, .updated:
                    if update.anchor.classification == .table {
                        // .updated時も必ず新しいEntityを生成し直して差し替える
                        planeEntities[update.anchor.id] = makeEntity(for: update.anchor, color: .cyan.opacity(0.35))
                    }
                case .removed:
                    planeEntities.removeValue(forKey: update.anchor.id)
                }
            }
        } catch {
            print("ARKitSession error:", error)
        }
    }

    private func makeEntity(for anchor: PlaneAnchor, color: Color) -> Entity {
        // メッシュは常に XY 平面で生成
        let mesh = MeshResource.generatePlane(
            width: anchor.geometry.extent.width,
            height: anchor.geometry.extent.height
        )
        let material = SimpleMaterial(color: .init(color), roughness: 1, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // 「エクステント座標->世界座標変換行列」を取得
        let worldFromExtent =
                anchor.originFromAnchorTransform
              * anchor.geometry.extent.anchorFromExtentTransform
        
        // XY平面メッシュを世界座標系における平面アンカーの位置・向きに移動
        entity.setTransformMatrix(worldFromExtent, relativeTo: nil)
        
        // anchorIDをEntity名に必ず設定
        entity.name = anchor.id.uuidString
        return entity
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
