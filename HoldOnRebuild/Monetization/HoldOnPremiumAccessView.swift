import SwiftUI

enum HoldOnPremiumContext: String, Identifiable {
    case editor
    case videoExport
    case manage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor: return "더 섬세하게 다듬기"
        case .videoExport: return "영상으로 내보내기"
        case .manage: return "HOLD ON Full Access"
        }
    }

    var detail: String {
        switch self {
        case .editor:
            return "오디오 편집 · 무음 제거 · 최대 5배 재생 · 자막 편집을 사용할 수 있어요."
        case .videoExport:
            return "완성한 기억을 자막과 함께 영상으로 만들어 사진 앱에 저장할 수 있어요."
        case .manage:
            return "고급 편집과 영상 내보내기를 광고 없이 계속 사용할 수 있어요."
        }
    }

    var allowsOneTimeAd: Bool { self != .manage }
}

struct HoldOnPremiumAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = HoldOnPurchaseManager.shared
    @ObservedObject private var ads = HoldOnRewardedAdManager.shared

    let context: HoldOnPremiumContext
    let onUnlocked: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: store.hasFullAccess ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(HoldOnTheme.purple)
                        .padding(.top, 18)

                    VStack(spacing: 8) {
                        Text(store.hasFullAccess ? "Full Access 사용 중" : context.title)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(context.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(HoldOnTheme.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        feature("waveform", "오디오 편집")
                        feature("speaker.slash", "무음 제거")
                        feature("speaker.wave.3", "최대 5배 재생")
                        feature("captions.bubble", "자막 편집")
                        feature("square.and.arrow.up", "영상 내보내기")
                    }
                    .padding(16)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))

                    if store.hasFullAccess {
                        Button("계속") {
                            onUnlocked()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HoldOnTheme.purple)
                        .frame(maxWidth: .infinity)
                    } else {
                        if context.allowsOneTimeAd {
                            Button {
                                Task {
                                    await ads.showRewardedAd {
                                        onUnlocked()
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack {
                                    if ads.isLoading || ads.isPresenting { ProgressView().tint(.white) }
                                    Text(ads.isLoading ? "광고 준비 중…" : "광고 보고 이번 한 번 사용")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(HoldOnTheme.purple)
                            .disabled(ads.isLoading || ads.isPresenting)
                        }

                        Button {
                            Task {
                                if await store.purchaseFullAccess() {
                                    onUnlocked()
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                if store.isPurchasing { ProgressView() }
                                Text(purchaseTitle)
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.bordered)
                        .tint(HoldOnTheme.purple)
                        .disabled(store.isPurchasing)

                        Button("구매 복원") {
                            Task {
                                if await store.restorePurchases() {
                                    onUnlocked()
                                    dismiss()
                                }
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HoldOnTheme.muted)
                    }

                    Text("순간잡기 · 저장 후 카메라 · 기억카드 꾸미기는 계속 무료예요.")
                        .font(.system(size: 11))
                        .foregroundStyle(HoldOnTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
            .background(HoldOnTheme.ambientBackground.ignoresSafeArea())
            .navigationTitle("Full Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .task {
                await store.loadProduct()
                await store.refreshEntitlements()
            }
            .alert("안내", isPresented: Binding(
                get: { store.message != nil || ads.message != nil },
                set: { if !$0 { store.message = nil; ads.message = nil } }
            )) {
                Button("확인") { store.message = nil; ads.message = nil }
            } message: {
                Text(store.message ?? ads.message ?? "")
            }
        }
    }

    private var purchaseTitle: String {
        if let price = store.fullAccessProduct?.displayPrice {
            return "Full Access 한 번 구매 · \(price)"
        }
        return "Full Access 한 번 구매"
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(HoldOnTheme.ink)
    }
}
