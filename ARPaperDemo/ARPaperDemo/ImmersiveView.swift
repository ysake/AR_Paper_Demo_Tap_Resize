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

    var body: some View {
        RealityView { content in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle),
               !content.entities.contains(immersiveContentEntity) {
                content.add(immersiveContentEntity)
            }
        } update: { content in
            // まだシーンに無いエンティティを追加
            for (_, entity) in planeEntities where entity.parent == nil {
                content.add(entity)
            }
            // planeEntities に存在しない子を削除
            for child in content.entities {
                guard let anchorID = UUID(uuidString: child.name) else { continue }
                if planeEntities[anchorID] == nil {
                    content.remove(child)
                }
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
                    planeEntities[update.anchor.id] = makeEntity(for: update.anchor, color: .cyan.opacity(0.35))
                case .removed:
                    planeEntities.removeValue(forKey: update.anchor.id)
                }
            }
        } catch {
            print("ARKitSession error:", error)
        }
    }

    private func makeEntity(for anchor: PlaneAnchor, color: Color) -> Entity {
        let mesh = MeshResource.generatePlane(
            width: anchor.geometry.extent.width,
            depth: anchor.geometry.extent.height)
        let material = SimpleMaterial(color: .cyan, roughness: 1, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.setTransformMatrix(anchor.originFromAnchorTransform, relativeTo: nil)
        return entity
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
