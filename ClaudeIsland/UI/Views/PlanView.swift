//
//  PlanView.swift
//  ClaudeIsland
//
//  Full-screen-centered viewer for an ExitPlanMode plan.
//  Renders the full markdown body via `MarkdownText` (the same renderer the rest of
//  the app uses) inside a scrollable container. Matches ChatView's visual language:
//  slim header with title + close button, gradient fades at top/bottom of the scroll
//  area, black background, same font weights/opacities.
//
//  The plan text is passed by value at construction time — it is a snapshot captured
//  at the moment the user tapped the plan tile, so nothing mutates it while the
//  viewer is on screen and there is no source to keep in sync.
//

import SwiftUI

struct PlanView: View {
    let plan: String
    @ObservedObject var viewModel: NotchViewModel

    /// Background color the gradient fades blend into — matches ChatView.fadeColor
    private let fadeColor = Color.black

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                MarkdownText(plan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            }
            .overlay(alignment: .top)    { topFade }
            .overlay(alignment: .bottom) { bottomFade }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    @State private var isCloseHovered: Bool = false

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))

            Text("Plan")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            // Close button — same hover pattern as the menu toggle in NotchView
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.exitPlan()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isCloseHovered ? .white.opacity(0.9) : .white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isCloseHovered ? Color.white.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .zIndex(1)
    }

    // MARK: - Gradient fades

    private var topFade: some View {
        LinearGradient(
            colors: [fadeColor.opacity(0.9), fadeColor.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 20)
        .allowsHitTesting(false)
    }

    private var bottomFade: some View {
        LinearGradient(
            colors: [fadeColor.opacity(0), fadeColor.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 20)
        .allowsHitTesting(false)
    }
}
