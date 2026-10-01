import SwiftUI

enum RootTab: CaseIterable {
    case home, memories, settings

    var title: String {
        switch self {
        case .home: "홈"
        case .memories: "기억들"
        case .settings: "설정"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .memories: "folder"
        case .settings: "gearshape"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: RootTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selection == tab ? "\(tab.symbol).fill" : tab.symbol)
                            .font(.system(size: 21, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? HoldOnTheme.purple : HoldOnTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(selection == tab ? HoldOnTheme.purple.opacity(0.06) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
