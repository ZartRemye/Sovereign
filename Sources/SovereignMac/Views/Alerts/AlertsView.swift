import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var selectedFilter: AlertFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("异常提醒")
                        .font(AppTypography.largeTitle)
                    Text("\(unreadCount) 条未读 · 共 \(filteredAlerts.count) 条")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Picker("筛选", selection: $selectedFilter) {
                    ForEach(AlertFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding()

            Divider()

            if filteredAlerts.isEmpty {
                EmptyStateView(
                    systemImage: "bell.badge",
                    title: "暂无提醒",
                    message: "当检测到睡眠不足、恢复偏低、训练负荷过高等情况时，会在这里显示提醒。"
                )
            } else {
                List {
                    ForEach(filteredAlerts) { alert in
                        AlertCard(alert: alert) {
                            markAsRead(alert)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("提醒")
    }

    private var filteredAlerts: [AlertRecord] {
        switch selectedFilter {
        case .all: return healthStore.alerts
        case .unread: return healthStore.alerts.filter { !$0.isRead }
        case .read: return healthStore.alerts.filter { $0.isRead }
        }
    }

    private var unreadCount: Int {
        healthStore.alerts.filter { !$0.isRead }.count
    }

    private func markAsRead(_ alert: AlertRecord) {
        alert.isRead = true
    }
}

enum AlertFilter: String, CaseIterable {
    case all = "全部"
    case unread = "未读"
    case read = "已读"
}
