import SwiftUI

struct BrandWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOLD ON")
                .font(.system(size: 30, weight: .medium))
                .tracking(4.0)
                .foregroundStyle(
                    LinearGradient(
                        colors: [HoldOnTheme.purple, HoldOnTheme.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("지금 이 목소리를, 오래도록")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.33, green: 0.35, blue: 0.42))
        }
    }
}
