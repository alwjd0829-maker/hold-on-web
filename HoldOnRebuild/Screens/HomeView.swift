import SwiftUI
import PhotosUI
import Photos
import UIKit

struct HomeView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @AppStorage("holdon.setting.cameraAfterSave") private var cameraAfterSave = true
    @State private var showPreTime = false
    @State private var isWorking = false
    @State private var showPhotoSuggestion = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var suggestedMomentID: UUID?
    @State private var showCancelCaptureConfirmation = false

    private var preText: String {
        let s = engine.selectedPreSeconds
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    var body: some View {
        ZStack {
            HoldOnTheme.ambientBackground
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    statusCard
                    Spacer(minLength: 38)
                    captureControl
                    preTimeButton
                    if engine.isCapturing {
                        captureCancelButton
                    }
                    Spacer(minLength: 18)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 120)
            }
        }
        .sheet(isPresented: $showPreTime) {
            PreTimePickerSheet(seconds: Binding(
                get: { engine.selectedPreSeconds },
                set: { engine.updateCapturePreSeconds($0) }
            ))
            .presentationDetents([.height(390)])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("기억을 저장했어요. 사진을 더할까요?", isPresented: $showPhotoSuggestion, titleVisibility: .visible) {
            Button("이 순간 촬영하기") { showCamera = true }
            Button("그냥 저장하기") {
                // The memory has already been saved before this suggestion appears.
                // This action simply keeps that saved memory without adding a photo.
                suggestedMomentID = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            HoldOnCameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: engine.lastSavedMomentID) { _, newID in
            guard cameraAfterSave, let newID else { return }
            guard !HoldOnQuickCapture.consumeCameraPromptSuppression() else {
                suggestedMomentID = nil
                showPhotoSuggestion = false
                return
            }
            suggestedMomentID = newID
            showPhotoSuggestion = true
        }
        .onChange(of: capturedImage) { _, image in
            guard let image, let id = suggestedMomentID,
                  let data = image.jpegData(compressionQuality: 0.92) else { return }
            engine.setMomentCardPhoto(id: id, jpegData: data)
            Task { await saveCapturedPhotoToLibrary(image) }
            suggestedMomentID = nil
            capturedImage = nil
        }
        .alert("진짜 중단할까요?", isPresented: $showCancelCaptureConfirmation) {
            Button("계속 잡기", role: .cancel) { }
            Button("저장하지 않고 중단", role: .destructive) {
                engine.cancelCapture()
            }
        } message: {
            Text("지금 잡고 있는 구간은 저장되지 않아요.")
        }

    }

    private func saveCapturedPhotoToLibrary(_ image: UIImage) async {
        try? await HoldOnPhotoLibrary.saveImageToHoldOnAlbum(image)
    }

    private var header: some View {
        HStack(alignment: .top) {
            BrandWordmark()
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private var statusCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 11) {
                    Circle()
                        .fill(HoldOnTheme.purple.opacity(engine.isHoldOn ? 1 : 0.24))
                        .frame(width: 11, height: 11)
                    Text(engine.isCapturing ? "순간을 잡는 중" : (engine.isHoldOn ? "녹음 대기 중" : "녹음 꺼짐"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(HoldOnTheme.ink)
                }

                Text(statusCopy)
                    .font(.system(size: 11))
                    .foregroundStyle(HoldOnTheme.muted)
                    .lineSpacing(3)
                    .padding(.leading, 22)
            }

            Spacer()

            VStack(spacing: 5) {
                Toggle("", isOn: Binding(
                    get: { engine.isHoldOn },
                    set: { value in
                        if value {
                            Task { try? await engine.startHoldOn() }
                        } else if engine.isCapturing {
                            Task {
                                _ = await HoldOnQuickCapture.perform(engine: engine, source: .inApp)
                                if engine.isHoldOn {
                                    engine.stopHoldOn(userInitiated: true, reason: "manualOffDuringCapture")
                                }
                            }
                        } else {
                            engine.stopHoldOn(userInitiated: true)
                        }
                    }
                ))
                .labelsHidden()
                .tint(HoldOnTheme.purple)
                .scaleEffect(0.95)

                Text(engine.isHoldOn ? "ON" : "OFF")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HoldOnTheme.muted)
            }
        }
        .padding(17)
        .background(HoldOnTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private var statusCopy: String {
        if engine.isCapturing {
            return "다시 누르면 저장해요.\n저장은 정확히 한 번만 만들어요."
        }
        if engine.isHoldOn {
            return "최근 5분 50초까지 덮어쓰고 있어요.\n저장은 ‘순간잡기’로 해요."
        }
        return "꺼져 있어도 ‘순간잡기’를 누르면\n자동으로 켜서 지금부터 잡아요."
    }

    private var captureControl: some View {
        Button {
            guard !isWorking else { return }
            isWorking = true
            Task {
                _ = await HoldOnQuickCapture.perform(engine: engine, source: .inApp)
                isWorking = false
            }
        } label: {
            ZStack {
                Circle()
                    .fill(engine.isCapturing ? Color.white.opacity(0.56) : Color.clear)

                if !engine.isCapturing {
                    Circle().fill(HoldOnTheme.accentGradient)
                    VStack(spacing: 12) {
                        Image(systemName: "mic").font(.system(size: 46, weight: .regular))
                        Text("순간잡기").font(.system(size: 23, weight: .medium))
                    }
                    .foregroundStyle(.white)
                } else {
                    VStack(spacing: 22) {
                        Text(engine.captureDurationText)
                            .font(.system(size: 38, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.31, green: 0.33, blue: 0.78))
                        Text(engine.captureHasHistory
                             ? "이전 \(preText)을 포함해서\n저장하고 있어요"
                             : "지금부터 저장하고 있어요\n앞부분 기본값은 \(preText)이에요")
                            .font(.system(size: 15, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(red: 0.41, green: 0.43, blue: 0.50))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(HoldOnTheme.purple)
                            .frame(width: 20, height: 20)
                            .padding(18)
                            .background(HoldOnTheme.purple.opacity(0.055), in: Circle())
                    }
                }
            }
            .frame(width: 238, height: 238)
            .overlay { Circle().stroke(Color.white.opacity(0.58), lineWidth: 5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.isCapturing ? "저장" : "순간잡기")
    }

    private var captureCancelButton: some View {
        Button(role: .destructive) {
            showCancelCaptureConfirmation = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("저장하지 않고 중단")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.red.opacity(0.90))
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(Color.red.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .accessibilityHint("한 번 더 확인한 뒤 현재 잡고 있는 구간을 저장하지 않고 끝냅니다")
    }

    private var preTimeButton: some View {
        Button { showPreTime = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock").font(.system(size: 21, weight: .medium))
                Text("앞")
                Text(preText).font(.system(size: 17, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(HoldOnTheme.ink)
            .padding(.horizontal, 22)
            .frame(height: 48)
            .background(Color(red: 0.94, green: 0.945, blue: 1.0).opacity(0.8), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 26)
    }
}

struct PreTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var seconds: Int
    @State private var draftSeconds: Int

    init(seconds: Binding<Int>) {
        self._seconds = seconds
        self._draftSeconds = State(initialValue: seconds.wrappedValue)
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { draftSeconds / 60 },
            set: { newMinute in
                let maxSecond = newMinute == 5 ? 50 : 59
                draftSeconds = min(350, newMinute * 60 + min(draftSeconds % 60, maxSecond))
            }
        )
    }

    private var secondBinding: Binding<Int> {
        Binding(
            get: { draftSeconds % 60 },
            set: { newSecond in
                draftSeconds = min(350, (draftSeconds / 60) * 60 + newSecond)
            }
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Text("앞에서 살릴 시간")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("완료") {
                    seconds = draftSeconds
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .padding(.top, 26)

            Text("기본은 5분이에요. 필요할 때만 줄여 쓰세요.")
                .font(.system(size: 12))
                .foregroundStyle(HoldOnTheme.muted)

            HStack(spacing: 0) {
                Picker("분", selection: minuteBinding) {
                    ForEach(0...5, id: \.self) { Text("\($0)분").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("초", selection: secondBinding) {
                    ForEach(0...(draftSeconds / 60 == 5 ? 50 : 59), id: \.self) {
                        Text(String(format: "%02d초", $0)).tag($0)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 170)

            HStack(spacing: 8) {
                ForEach([60, 180, 300], id: \.self) { value in
                    Button("\(value / 60)분") { draftSeconds = value }
                        .buttonStyle(.bordered)
                }
            }

            Text("앞 \(draftSeconds / 60):\(String(format: "%02d", draftSeconds % 60))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HoldOnTheme.purple)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(HoldOnTheme.background)
    }
}

struct HoldOnCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: HoldOnCameraPicker
        init(_ parent: HoldOnCameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}

// MARK: - Photos library saving

/// Saves HOLD ON-created media to the normal Photos library and also adds it to
/// a user-visible `HOLD ON` album. The media remains in Recents as usual.
/// Uses add-only authorization; no cloud upload or server copy is involved.
enum HoldOnPhotoLibrary {
    private static let albumTitle = "HOLD ON"
    private static let albumIdentifierKey = "holdon.photos.albumIdentifier"

    static func saveImageToHoldOnAlbum(_ image: UIImage) async throws {
        try await ensureAddPermission()
        try await saveAssetToHoldOnAlbum {
            PHAssetChangeRequest.creationRequestForAsset(from: image).placeholderForCreatedAsset
        }
    }

    static func saveVideoToHoldOnAlbum(_ url: URL) async throws {
        try await ensureAddPermission()
        try await saveAssetToHoldOnAlbum {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)?.placeholderForCreatedAsset
        }
    }

    private static func ensureAddPermission() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        if current == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
            }
        } else {
            status = current
        }
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "HoldOnPhotos", code: 1, userInfo: [NSLocalizedDescriptionKey: "사진 앱 저장 권한이 필요해요."])
        }
    }

    private static func existingAlbum() -> PHAssetCollection? {
        if let id = UserDefaults.standard.string(forKey: albumIdentifierKey) {
            let byID = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            if let album = byID.firstObject { return album }
        }

        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var matched: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == albumTitle {
                matched = collection
                stop.pointee = true
            }
        }
        if let matched {
            UserDefaults.standard.set(matched.localIdentifier, forKey: albumIdentifierKey)
        }
        return matched
    }

    private static func saveAssetToHoldOnAlbum(
        creation: @escaping () -> PHObjectPlaceholder?
    ) async throws {
        let album = existingAlbum()
        var createdAlbumIdentifier: String?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                guard let assetPlaceholder = creation() else { return }

                if let album {
                    PHAssetCollectionChangeRequest(for: album)?.addAssets([assetPlaceholder] as NSArray)
                } else {
                    let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                    createdAlbumIdentifier = albumRequest.placeholderForCreatedAssetCollection.localIdentifier
                    albumRequest.addAssets([assetPlaceholder] as NSArray)
                }
            }) { success, error in
                if success {
                    if let createdAlbumIdentifier {
                        UserDefaults.standard.set(createdAlbumIdentifier, forKey: albumIdentifierKey)
                    }
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "HoldOnPhotos", code: 2, userInfo: [NSLocalizedDescriptionKey: "사진 앱에 저장하지 못했어요."]))
                }
            }
        }
    }
}

