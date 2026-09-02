//
//  VirtualControls.swift
//  Priors
//

import SwiftUI
import CoreGraphics

/// SPEC §8 — Virtual thumbstick and interact button overlay (Landscape HIG optimized).
public struct VirtualControlsView: View {
    public var lanternCount: Int
    /// True when the player is standing in a scenario zone. Drives the only
    /// affordance telling them the button will do something — the value was
    /// previously computed in `VillageContainerView` and never read, so the
    /// interact button looked identical whether or not it was live.
    public var canInteract: Bool
    public var onVectorChange: ((CGVector) -> Void)?
    /// Fires `true` on press-down, `false` on release — SPEC §8.3's social
    /// mechanic needs hold duration, which a single tap action can't express.
    public var onInteractPressChanged: ((Bool) -> Void)?

    @State private var knobOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var pulse: Bool = false
    @State private var isPressed: Bool = false

    private let baseRadius: CGFloat = 56.0
    private let knobRadius: CGFloat = 22.0

    public init(
        lanternCount: Int = 0,
        canInteract: Bool = false,
        onVectorChange: ((CGVector) -> Void)? = nil,
        onInteractPressChanged: ((Bool) -> Void)? = nil
    ) {
        self.lanternCount = lanternCount
        self.canInteract = canInteract
        self.onVectorChange = onVectorChange
        self.onInteractPressChanged = onInteractPressChanged
    }

    public var body: some View {
        ZStack {
            // Top HUD: Lantern count only (SPEC §8 — No timer, no minimap, no objective marker)
            VStack {
                HStack {
                    Text("Lanterns: \(lanternCount)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.leading, 32)

                Spacer()

                // Bottom Controls: Thumbstick on bottom-left, Interact on bottom-right (Landscape ergonomics)
                HStack(alignment: .bottom) {
                    // Virtual Thumbstick
                    thumbstick
                        .padding(.leading, 36)
                        .padding(.bottom, 24)

                    Spacer()

                    // Interact Button
                    interactButton
                        .padding(.trailing, 36)
                        .padding(.bottom, 24)
                }
            }
            .safeAreaPadding()
        }
    }

    private var thumbstick: some View {
        ZStack {
            // Outer Ring
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                .background(Circle().fill(Color.black.opacity(0.3)))
                .frame(width: baseRadius * 2, height: baseRadius * 2)

            // Inner Knob
            Circle()
                .fill(Color.white.opacity(0.65))
                .frame(width: knobRadius * 2, height: knobRadius * 2)
                .offset(knobOffset)
        }
        .frame(width: baseRadius * 2, height: baseRadius * 2)
        .contentShape(Rectangle().size(width: baseRadius * 2.5, height: baseRadius * 2.5))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let translation = value.translation
                    let distance = hypot(translation.width, translation.height)

                    if distance <= baseRadius {
                        knobOffset = translation
                    } else if distance > 0 {
                        let scale = baseRadius / distance
                        knobOffset = CGSize(width: translation.width * scale, height: translation.height * scale)
                    }

                    // Normalised CGVector: dx in [-1, 1], dy in [-1, 1] (SpriteKit Y-up convention)
                    let normX = knobOffset.width / baseRadius
                    let normY = -knobOffset.height / baseRadius
                    let vector = CGVector(dx: max(-1.0, min(1.0, normX)), dy: max(-1.0, min(1.0, normY)))
                    onVectorChange?(vector)
                }
                .onEnded { _ in
                    isDragging = false
                    knobOffset = .zero
                    onVectorChange?(.zero)
                }
        )
    }

    /// Dimmed and inert away from a live decision; solid and gently pulsing
    /// once one is armed. Press-and-hold, not tap — SPEC §8.3's social
    /// mechanic resolves on hold duration, tracked by the caller.
    private var interactButton: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(canInteract ? 0.85 : 0.2), lineWidth: 2)
                .background(Circle().fill(Color.black.opacity(canInteract ? 0.5 : 0.25)))
                .frame(width: 68, height: 68)
                .scaleEffect(canInteract && pulse ? 1.06 : 1.0)

            Text("Interact")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(canInteract ? 1.0 : 0.3))
        }
        .contentShape(Circle())
        .opacity(canInteract ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.25), value: canInteract)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard canInteract, !isPressed else { return }
                    isPressed = true
                    onInteractPressChanged?(true)
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    onInteractPressChanged?(false)
                }
        )
        .onChange(of: canInteract) { _, live in
            pulse = false
            if isPressed { isPressed = false; onInteractPressChanged?(false) }
            guard live else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
