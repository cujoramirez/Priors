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
    @State private var holdProgress: Double = 0.0

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
                    lanternHUD
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

    private var lanternHUD: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundColor(Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0))
                .font(.system(size: 13, weight: .semibold))
                .shadow(color: Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0).opacity(0.8), radius: 4)

            Text("Lanterns: \(lanternCount)")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(white: 0.08, opacity: 0.85))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 3)
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
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                )
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
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        knobOffset = .zero
                    }
                    onVectorChange?(.zero)
                }
        )
    }

    /// Dimmed and inert away from a live decision; solid and gently pulsing
    /// once one is armed. Press-and-hold, not tap — SPEC §8.3's social
    /// mechanic resolves on hold duration, tracked by the caller.
    private var interactButton: some View {
        ZStack {
            // Outer Static Border
            Circle()
                .strokeBorder(Color.white.opacity(canInteract ? 0.85 : 0.2), lineWidth: 2)
                .background(Circle().fill(Color.black.opacity(canInteract ? 0.5 : 0.25)))
                .frame(width: 68, height: 68)

            // Radial Hold Progress Ring (0.6s fill)
            if canInteract && holdProgress > 0.0 {
                Circle()
                    .trim(from: 0.0, to: holdProgress)
                    .stroke(
                        Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 72, height: 72)
                    .shadow(color: Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0).opacity(0.8), radius: 4)
            }

            Text("Interact")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(canInteract ? 1.0 : 0.3))
        }
        .scaleEffect(isPressed ? 0.94 : (canInteract && pulse ? 1.05 : 1.0))
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
        .onChange(of: isPressed) { _, pressed in
            if pressed {
                holdProgress = 0.0
                withAnimation(.linear(duration: 0.6)) {
                    holdProgress = 1.0
                }
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    holdProgress = 0.0
                }
            }
        }
        .onChange(of: canInteract) { _, live in
            pulse = false
            if isPressed {
                isPressed = false
                onInteractPressChanged?(false)
            }
            guard live else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
