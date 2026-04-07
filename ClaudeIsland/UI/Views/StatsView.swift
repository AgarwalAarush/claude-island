//
//  StatsView.swift
//  ClaudeIsland
//
//  Analytics panel: today's summary and per-project breakdowns.
//

import SwiftUI

struct StatsView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    // MARK: - Derived Data

    private var todaySessions: [SessionState] {
        sessionMonitor.instances.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var todayTokens: Int {
        todaySessions.reduce(0) {
            $0 + $1.conversationInfo.totalInputTokens + $1.conversationInfo.totalOutputTokens
        }
    }

    private var todayToolCalls: Int {
        todaySessions.reduce(0) { $0 + toolCallCount($1) }
    }

    /// All unique cwds across all sessions, sorted by descending total tokens
    private var projectGroups: [(cwd: String, sessions: [SessionState])] {
        let grouped = Dictionary(grouping: sessionMonitor.instances) { $0.cwd }
        return grouped.map { cwd, sessions in (cwd: cwd, sessions: sessions) }
            .sorted { groupTokens($0.sessions) > groupTokens($1.sessions) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back header
            HStack(spacing: 6) {
                Button { viewModel.exitStats() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Stats")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Today summary cards
                    todaySummarySection

                    // Per-project rows
                    if !projectGroups.isEmpty {
                        projectsSection
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, 4)
        .onAppear {
            let cwds = Array(Set(sessionMonitor.instances.map { $0.cwd }))
            viewModel.triggerProjectScans(for: cwds)
        }
    }

    // MARK: - Today Section

    private var todaySummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .kerning(0.8)

            HStack(spacing: 8) {
                StatCard(label: "Sessions", value: "\(todaySessions.count)")
                StatCard(label: "Tokens", value: formatTokens(todayTokens))
                StatCard(label: "Tool Calls", value: "\(todayToolCalls)")
            }
        }
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROJECTS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .kerning(0.8)

            VStack(spacing: 4) {
                ForEach(projectGroups, id: \.cwd) { group in
                    ProjectRow(
                        cwd: group.cwd,
                        sessions: group.sessions,
                        scanResult: viewModel.projectScanResults[group.cwd]
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func groupTokens(_ sessions: [SessionState]) -> Int {
        sessions.reduce(0) {
            $0 + $1.conversationInfo.totalInputTokens + $1.conversationInfo.totalOutputTokens
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let cwd: String
    let sessions: [SessionState]
    let scanResult: ProjectScanResult?

    private var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    private var totalTokens: Int {
        sessions.reduce(0) {
            $0 + $1.conversationInfo.totalInputTokens + $1.conversationInfo.totalOutputTokens
        }
    }

    private var totalToolCalls: Int {
        sessions.reduce(0) { $0 + toolCallCount($1) }
    }

    private var topLanguages: [(language: String, lines: Int)] {
        guard let result = scanResult else { return [] }
        return result.languageLines
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { (language: $0.key, lines: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: project name + repo slug
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(cwd)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let slug = scanResult?.repoSlug {
                    Text(slug)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            // Language bars or scanning indicator
            if scanResult == nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Scanning...")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
            } else if topLanguages.isEmpty {
                Text("No source files found")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            } else {
                let maxLines = topLanguages.first?.lines ?? 1
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(topLanguages, id: \.language) { item in
                        HStack(spacing: 8) {
                            Text(item.language)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 76, alignment: .leading)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: geo.size.width)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.5))
                                            .frame(width: geo.size.width * CGFloat(item.lines) / CGFloat(maxLines))
                                    }
                            }
                            .frame(height: 4)
                            Text(formatLOC(item.lines))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }

            // Footer stats
            HStack(spacing: 12) {
                footerLabel("\(sessions.count)", "session\(sessions.count == 1 ? "" : "s")")
                footerLabel(formatTokens(totalTokens), "tokens")
                footerLabel("\(totalToolCalls)", "tool calls")
                Spacer()
                if let result = scanResult {
                    Text("\(result.fileCount) files")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func footerLabel(_ value: String, _ unit: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Text(unit)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

// MARK: - Formatting Helpers

private func formatTokens(_ n: Int) -> String {
    switch n {
    case ..<1000: return "\(n)"
    case ..<1_000_000: return String(format: "%.1fk", Double(n) / 1000)
    default: return String(format: "%.1fM", Double(n) / 1_000_000)
    }
}

private func formatLOC(_ n: Int) -> String {
    if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
    return "\(n)"
}

private func toolCallCount(_ session: SessionState) -> Int {
    session.chatItems.filter {
        if case .toolCall = $0.type { return true }
        return false
    }.count
}
