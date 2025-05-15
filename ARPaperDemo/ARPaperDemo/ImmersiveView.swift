//
//  ImmersiveView.swift
//  ARPaperDemo
//
//  Created by 酒井雄太 on 2025/05/13.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    var body: some View {
        RealityView { content in
            // 既存のImmersiveエンティティを追加
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
            }

            // セッション生成と構成
            let trackingSession = SpatialTrackingSession()
            let config = SpatialTrackingSession.Configuration(tracking: [.plane])
            if let result = await trackingSession.run(config) {
                if !result.anchor.contains(.plane) {
                    // 平面検出が許可されていない場合の処理（必要なら）
                }
            }

            // 平面検出用アンカーを作成
            let planeAnchor = AnchorEntity(
                .plane(.horizontal, classification: .any, minimumBounds: [0.2, 0.2])
            )
            // 半透明の平面を生成し、アンカーの子に追加
            let mesh = MeshResource.generatePlane(width: 0.3, depth: 0.3)
            let material = SimpleMaterial(color: .blue.withAlphaComponent(0.3), isMetallic: false)
            let planeEntity = ModelEntity(mesh: mesh, materials: [material])
            planeEntity.position = .zero
            planeAnchor.addChild(planeEntity)
            content.add(planeAnchor)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
