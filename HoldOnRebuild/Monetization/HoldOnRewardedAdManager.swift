import Foundation
import Combine
import GoogleMobileAds

@MainActor
final class HoldOnRewardedAdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = HoldOnRewardedAdManager()

    // Build 160 is the App Store release candidate. Production rewarded ads are enabled.
    private let useTestAds = false
    private let googleTestRewardedID = "ca-app-pub-3940256099942544/1712485313"
    private let productionRewardedID = "ca-app-pub-5978840146134387/6117620046"

    @Published private(set) var isLoading = false
    @Published private(set) var isPresenting = false
    @Published var message: String?

    private var rewardedAd: RewardedAd?
    private var didStartSDK = false
    private var pendingReward: (() -> Void)?

    private override init() {
        super.init()
    }

    private var adUnitID: String {
        useTestAds ? googleTestRewardedID : productionRewardedID
    }

    private func startSDKIfNeeded() {
        guard !didStartSDK else { return }
        didStartSDK = true
        MobileAds.shared.start()
    }

    func loadAdIfNeeded() async -> Bool {
        if rewardedAd != nil { return true }
        if isLoading { return false }
        startSDKIfNeeded()
        isLoading = true
        defer { isLoading = false }

        do {
            let ad = try await RewardedAd.load(with: adUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            return true
        } catch {
            message = "광고를 준비하지 못했어요. 네트워크를 확인하고 다시 시도해 주세요."
            return false
        }
    }

    func showRewardedAd(onReward: @escaping () -> Void) async {
        guard !isPresenting else { return }
        let ready = await loadAdIfNeeded()
        guard ready, let ad = rewardedAd else { return }

        pendingReward = onReward
        isPresenting = true
        ad.present(from: nil) { [weak self] in
            guard let self else { return }
            let rewardAction = self.pendingReward
            self.pendingReward = nil
            rewardAction?()
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        rewardedAd = nil
        pendingReward = nil
        isPresenting = false
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        rewardedAd = nil
        pendingReward = nil
        isPresenting = false
        message = "광고를 표시하지 못했어요. 잠시 후 다시 시도해 주세요."
    }
}
