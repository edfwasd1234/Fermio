import SwiftUI
import UIKit

/// Advanced Console: a detailed, filterable view of everything the app has
/// logged as failing. Tap a row to expand its full error detail; copy or clear
/// the whole log from the menu.
struct DiagnosticsConsoleView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var filter: FilterOption = .all
    @State private var expandedIDs: Set<UUID> = []
    @State private var showCopied = false

    enum FilterOption: String, CaseIterable {
        case all = "All"
        case error = "Errors"
        case warning = "Warnings"
        case info = "Info"
    }

    private var entries: [DiagnosticsLog.Entry] {
        let all = DiagnosticsLog.shared.entries
        switch filter {
        case .all: return all
        case .error: return all.filter { $0.level == .error }
        case .warning: return all.filter { $0.level == .warning }
        case .info: return all.filter { $0.level == .info }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Filter", selection: $filter) {
                        ForEach(FilterOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if entries.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.green.opacity(0.7))
                            Text(filter == .all ? "Nothing logged yet." : "No \(filter.rawValue.lowercased()) logged.")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(entries) { entry in
                                    row(entry)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("Advanced Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = DiagnosticsLog.shared.exportText()
                            withAnimation { showCopied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation { showCopied = false }
                            }
                        } label: {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                        .disabled(DiagnosticsLog.shared.entries.isEmpty)

                        Button(role: .destructive) {
                            withAnimation {
                                DiagnosticsLog.shared.clear()
                                expandedIDs.removeAll()
                            }
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                        }
                        .disabled(DiagnosticsLog.shared.entries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopied {
                    Text("Copied to clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ entry: DiagnosticsLog.Entry) -> some View {
        let isExpanded = expandedIDs.contains(entry.id)
        let hasDetail = (entry.detail?.isEmpty == false)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(entry.level))
                    .font(.system(size: 13))
                    .foregroundColor(color(entry.level))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.category.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(color(entry.level))
                        Spacer()
                        Text(timeString(entry.date))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }

                    Text(entry.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if hasDetail, let detail = entry.detail {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(isExpanded ? 0.75 : 0.5))
                            .lineLimit(isExpanded ? nil : 1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: isExpanded)
                    }
                }

                if hasDetail {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(entry.level).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color(entry.level).opacity(0.25), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasDetail else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedIDs.remove(entry.id)
                } else {
                    expandedIDs.insert(entry.id)
                }
            }
        }
    }

    private func icon(_ level: DiagnosticsLog.Level) -> String {
        switch level {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ level: DiagnosticsLog.Level) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .cyan
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter.string(from: date)
    }
}
