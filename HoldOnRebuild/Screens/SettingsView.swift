import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @AppStorage("holdon.setting.cameraAfterSave") private var cameraAfterSave = true
    @State private var showCardSettings = false
    @State private var showQuickHelp = false
    @State private var showTutorial = false
    @State private var showPrivacySummary = false
    @State private var showStorageManagement = false
    @State private var showFullAccess = false
    @ObservedObject private var purchaseManager = HoldOnPurchaseManager.shared

    var body: some View {
        ZStack {
            HoldOnTheme.ambientBackground
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("설정")
                        .font(.system(size: 31, weight: .bold))
                        .padding(.horizontal, 18)
                        .padding(.top, 20)

                    section("기억") {
                        row("저장 후 카메라 제안", subtitle: "기억 저장 직후 ‘이 순간을 촬영할까요?’라고 물어봐요") {
                            Toggle("", isOn: $cameraAfterSave).labelsHidden().tint(HoldOnTheme.purple)
                        }
                        Divider().padding(.leading, 16)
                        Button { showCardSettings = true } label: {
                            row("기억카드 전체 설정", subtitle: "새로 저장되는 카드의 비율 · 배경 · 제목 스타일") {
                                Image(systemName: "chevron.right").foregroundStyle(HoldOnTheme.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                        Button { showStorageManagement = true } label: {
                            row("저장공간 관리", subtitle: "HOLD ON 데이터 용량 · 오래된 기억 · 내보낸 기억 정리") {
                                Image(systemName: "externaldrive")
                                    .foregroundStyle(HoldOnTheme.purple)
                            }
                        }
                        .buttonStyle(.plain)
                    }


                    section("루틴") {
                        row("시간 루틴", subtitle: "켜짐 알림 · 자동 꺼짐") {
                            Toggle("", isOn: Binding(
                                get: { engine.routineEnabled },
                                set: { engine.setRoutineEnabled($0) }
                            ))
                            .labelsHidden()
                            .tint(HoldOnTheme.purple)
                        }

                        if engine.routineEnabled {
                            Divider().padding(.leading, 16)
                            routineTimeRow("켜짐 알림", minutes: engine.routineOnMinutes) { engine.setRoutineOnMinutes($0) }
                            Divider().padding(.leading, 16)
                            routineTimeRow("꺼짐", minutes: engine.routineOffMinutes) { engine.setRoutineOffMinutes($0) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("꺼짐은 자동으로 실행돼요. 켜짐 시각에는 알림이 오고, 알림을 탭하면 바로 HOLD ON이 켜져요.")
                                Text("iOS가 앱을 완전히 내려둔 상태에서 마이크를 자동으로 켜는 것은 허용하지 않아요.")
                            }
                                .font(.system(size: 10))
                                .foregroundStyle(HoldOnTheme.muted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                    }

                    section("빠른 실행") {
                        Button { showQuickHelp = true } label: {
                            row("빠른 순간잡기", subtitle: "제어센터 · 잠금화면 · 동작 버튼에서 바로 잡기") {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(HoldOnTheme.purple)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    section("Full Access") {
                        Button { showFullAccess = true } label: {
                            row(
                                "HOLD ON Full Access",
                                subtitle: purchaseManager.hasFullAccess
                                    ? "구매 완료 · 고급 기능을 광고 없이 사용 중"
                                    : (purchaseManager.freeTrialRemainingUses > 0
                                        ? "무료 체험 \(purchaseManager.freeTrialRemainingUses)회 남음 · 이후 광고 또는 Full Access"
                                        : "광고 없이 오디오 편집 · 자막 · 영상 내보내기")
                            ) {
                                Image(systemName: purchaseManager.hasFullAccess ? "checkmark.seal.fill" : "sparkles")
                                    .foregroundStyle(HoldOnTheme.purple)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    section("도움말") {
                        Button { showTutorial = true } label: {
                            row("사용법 다시 보기", subtitle: "순간잡기부터 편집까지") {
                                Image(systemName: "questionmark.circle")
                            }
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                        Button { showPrivacySummary = true } label: {
                            row("개인정보 한눈에", subtitle: "수집 여부 · 로컬 저장 · 외부 전송을 먼저 확인해요") {
                                Image(systemName: "hand.raised.fill").foregroundStyle(HoldOnTheme.purple)
                            }
                        }.buttonStyle(.plain)
                    }

                    section("상태") {
                        row("HOLD ON", subtitle: engine.isRecordingActive ? "지금 실제 마이크 입력 중" : "현재 입력 없음") {
                            Circle()
                                .fill(engine.isRecordingActive ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 10, height: 10)
                        }
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .sheet(isPresented: $showCardSettings) {
            GlobalCardSettingsView()
                .environmentObject(engine)
        }
        .sheet(isPresented: $showTutorial) {
            HoldOnTutorialView { showTutorial = false }
        }
        .sheet(isPresented: $showQuickHelp) {
            QuickCaptureHelpView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPrivacySummary) {
            PrivacySummaryView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStorageManagement) {
            StorageManagementView()
                .environmentObject(engine)
        }
        .sheet(isPresented: $showFullAccess) {
            HoldOnPremiumAccessView(context: .manage) { }
        }
    }

    private func routineTimeRow(_ title: String, minutes: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: { dateForMinutes(minutes) },
                    set: { onChange(minutesForDate($0)) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
        .padding(16)
    }

    private func dateForMinutes(_ minutes: Int) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return cal.date(byAdding: .minute, value: minutes, to: start) ?? Date()
    }

    private func minutesForDate(_ date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(HoldOnTheme.muted).padding(.horizontal, 20)
            VStack(spacing: 0) { content() }
                .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.88), lineWidth: 1) }
                .padding(.horizontal, 14)
        }
    }

    private func row<Trailing: View>(_ title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(HoldOnTheme.ink)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(HoldOnTheme.muted)
            }
            Spacer()
            trailing()
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}

private struct QuickCaptureHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("빠른 순간잡기").font(.system(size: 19, weight: .bold))
                    Spacer(); Button("닫기") { dismiss() }
                }
                .padding(.top, 24)

                Text("세 곳 어디서 실행해도 H → 파형(잡는 중) → 다시 누르면 저장 → H 흐름은 같아요.")
                    .font(.system(size: 12)).foregroundStyle(HoldOnTheme.muted)

                place("lock.rectangle", "잠금화면", "아이폰을 깨웠을 때 보이는 첫 화면 아래쪽 버튼 자리", "잠금화면 길게 누르기 → 사용자화 → 잠금 화면 → 아래 제어 버튼 → HOLD ON 추가")
                place("switch.2", "제어센터", "화면 오른쪽 위 모서리에서 아래로 쓸어내리면 나오는 화면", "제어센터 열기 → + → 제어 항목 추가 → HOLD ON 추가")
                place("button.programmable", "동작 버튼", "지원되는 아이폰 왼쪽 옆면의 물리 버튼", "설정 → 동작 버튼 → 제어 항목 → HOLD ON 선택 · 사용할 때는 동작 버튼을 길게 누르기")

                Text("HOLD ON이 이미 켜져 있으면 선택한 앞부분까지 함께 잡고, 꺼져 있으면 누른 시점부터 잡아요. 동작 버튼이 없는 아이폰에서는 세 번째 항목을 사용하지 않으면 됩니다.")
                    .font(.system(size: 11)).foregroundStyle(HoldOnTheme.ink.opacity(0.72)).lineSpacing(3)
            }
            .padding(.horizontal, 22).padding(.bottom, 24)
        }
        .background(HoldOnTheme.background)
    }

    private func place(_ icon: String, _ title: String, _ whereText: String, _ setup: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .bold))
            Text("어디에 있나요?  \(whereText)").font(.system(size: 11))
            Text("설정 방법  \(setup)").font(.system(size: 11, weight: .medium)).foregroundStyle(HoldOnTheme.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }
}


private struct PrivacySummaryView: View {
    @Environment(\.dismiss) private var dismiss
    private let privacyURL = URL(string: "https://alwjd0829-maker.github.io/hold-on-web/privacy.html")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("HOLD ON의 기록은 기본적으로 내 iPhone 안에 머물러요.")
                        .font(.system(size: 19, weight: .bold))

                    privacyPoint("person.crop.circle.badge.xmark", "계정 없음", "가입·로그인·이름 수집 없이 사용할 수 있어요.")
                    privacyPoint("waveform", "녹음은 로컬 저장", "녹음·자막·카드 사진은 사용자가 직접 내보내기 전까지 앱의 로컬 저장공간에 보관돼요.")
                    privacyPoint("square.and.arrow.up", "기록은 내보낼 때만 공유", "녹음·사진·자막은 사용자가 직접 내보내기를 선택했을 때 사진 앱이나 파일로 저장돼요.")
                    privacyPoint("icloud.slash", "별도 서버 저장 없음", "HOLD ON이 운영하는 서버로 녹음·사진·자막을 올려 보관하지 않아요.")
                    privacyPoint("rectangle.and.hand.point.up.left", "선택형 광고", "무료 고급 기능을 위해 광고 보기를 선택하면 Google AdMob이 광고 제공에 필요한 기기·네트워크 정보를 처리할 수 있어요. 녹음 내용은 광고 서비스로 보내지 않아요.")

                    Link(destination: privacyURL) {
                        Label("전체 개인정보처리방침 보기", systemImage: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(HoldOnTheme.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HoldOnTheme.purple)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(HoldOnTheme.background)
            .navigationTitle("개인정보 한눈에")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }

    private func privacyPoint(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HoldOnTheme.purple)
                .frame(width: 28, height: 28)
                .background(HoldOnTheme.purple.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(text).font(.system(size: 12)).foregroundStyle(HoldOnTheme.muted).lineSpacing(3)
            }
        }
    }
}

private struct GlobalCardSettingsView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("holdon.card.global.ratio") private var ratio = "4:1"
    @AppStorage("holdon.card.global.backgroundKind") private var backgroundKind = "sky"
    @AppStorage("holdon.card.global.backgroundValue") private var backgroundValue = "auto"
    @AppStorage("holdon.card.global.titleFont") private var titleFont = "serif"
    @AppStorage("holdon.card.global.titleSize") private var titleSize = 18.0
    @AppStorage("holdon.card.global.inkHex") private var inkHex = "#FFFFFF"
    @State private var photo: PhotosPickerItem?
    @State private var hasGlobalPhoto = false
    @State private var previewRevision = 0
    @State private var gradientA = "#758DD8"
    @State private var gradientB = "#C8A8E2"
    @State private var skyMode = "auto"
    @State private var previewRatio = "4:1"
    @State private var previewBackgroundKind = "sky"
    @State private var previewBackgroundValue = "auto"
    @State private var previewTitleFont = "serif"
    @State private var previewTitleSize = 18.0
    @State private var previewInkHex = "#FFFFFF"

    private let palette = [
        "#FFFFFF", "#F1D6DB", "#E8CCD9", "#DDB8A6",
        "#F0D88A", "#BFD59B", "#9DC8BF", "#A7CDE8",
        "#7B80D9", "#A987B8", "#8A8D99", "#222222"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("미리보기") {
                    GlobalCardPreview(
                        ratio: previewRatio,
                        backgroundKind: previewBackgroundKind,
                        backgroundValue: previewBackgroundValue,
                        titleFont: previewTitleFont,
                        titleSize: previewTitleSize,
                        inkHex: previewInkHex,
                        photoURL: engine.globalCardPhotoPreviewURL
                    )
                    .id(previewRevision)
                    .frame(maxWidth: .infinity)
                }

                Section("화면 비율") {
                    Picker("기본 비율", selection: $ratio) {
                        Text("4:1").tag("4:1")
                        Text("3:2").tag("3:2")
                        Text("1:1").tag("1:1")
                        Text("9:16").tag("9:16")
                    }
                    .pickerStyle(.segmented)
                }

                Section("배경") {
                    Picker("종류", selection: $backgroundKind) {
                        Text("하늘").tag("sky")
                        Text("내 사진").tag("album")
                        Text("단색").tag("solid")
                        Text("그라데이션").tag("gradient")
                    }

                    if backgroundKind == "sky" {
                        Picker("하늘 방식", selection: $skyMode) {
                            Text("시간에 따라 자동").tag("auto")
                            Text("한 장 고정").tag("fixed")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: skyMode) { _, newMode in
                            if newMode == "auto" {
                                backgroundValue = "auto"
                            } else if backgroundValue == "auto" || !backgroundValue.hasPrefix("sky_") {
                                backgroundValue = skyFile(1)
                            }
                            refreshPreview()
                        }

                        if skyMode == "fixed" {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                                ForEach(1...23, id: \.self) { i in
                                    let file = skyFile(i)
                                    Button {
                                        backgroundValue = file
                                        refreshPreview()
                                    } label: {
                                        GlobalSkyThumb(file: file)
                                            .frame(height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 6)
                        } else {
                            Text("저장되는 시간대에 맞춰 하늘이 자동으로 선택돼요.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if backgroundKind == "album" {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(hasGlobalPhoto ? "기본 사진 바꾸기" : "기본 사진 선택", systemImage: "photo")
                        }
                    } else if backgroundKind == "solid" {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                            ForEach(palette, id: \.self) { hex in
                                Button {
                                    backgroundValue = hex
                                    refreshPreview()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 27, height: 27)
                                        .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    } else if backgroundKind == "gradient" {
                        LinearGradient(
                            colors: [Color(hex: gradientA), Color(hex: gradientB)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 9))

                        HStack(alignment: .top, spacing: 10) {
                            globalMiniPalette(selected: $gradientA)
                            globalMiniPalette(selected: $gradientB)
                        }

                        Button("이 그라데이션 사용") {
                            backgroundValue = "\(gradientA)|\(gradientB)"
                            refreshPreview()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }

                Section("제목") {
                    Picker("글꼴", selection: $titleFont) {
                        Text("고운바탕").tag("serif")
                        Text("고딕").tag("system")
                    }
                    HStack {
                        Text("크기")
                        Slider(value: $titleSize, in: 14...23, step: 1)
                        Text("\(Int(titleSize))").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("글자색", selection: $inkHex) {
                        Text("흰색").tag("#FFFFFF")
                        Text("검정").tag("#111111")
                    }
                }

                Section {
                    Text("이 설정은 앞으로 새로 저장되는 기억에 적용돼요. 이미 저장한 기억은 각각의 설정을 유지해요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("기억카드 전체 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                hasGlobalPhoto = engine.hasGlobalCardPhoto()
                skyMode = backgroundValue == "auto" ? "auto" : "fixed"
                refreshPreview()
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
            .onChange(of: backgroundKind) { _, new in
                switch new {
                case "sky":
                    skyMode = "auto"
                    backgroundValue = "auto"
                case "solid":
                    if !backgroundValue.hasPrefix("#") { backgroundValue = "#7B80D9" }
                case "gradient":
                    backgroundValue = "\(gradientA)|\(gradientB)"
                case "album":
                    backgroundValue = ""
                default:
                    break
                }
                refreshPreview()
            }
            .onChange(of: ratio) { _, _ in refreshPreview() }
            .onChange(of: backgroundValue) { _, _ in refreshPreview() }
            .onChange(of: titleFont) { _, _ in refreshPreview() }
            .onChange(of: titleSize) { _, _ in refreshPreview() }
            .onChange(of: inkHex) { _, _ in refreshPreview() }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        engine.setGlobalCardPhoto(jpegData: data)
                        hasGlobalPhoto = true
                        backgroundKind = "album"
                        backgroundValue = ""
                        refreshPreview()
                    }
                    photo = nil
                }
            }
        }
    }
    private func refreshPreview() {
        previewRatio = ratio
        previewBackgroundKind = backgroundKind
        previewBackgroundValue = backgroundValue
        previewTitleFont = titleFont
        previewTitleSize = titleSize
        previewInkHex = inkHex
        previewRevision += 1
    }

    private func skyFile(_ i: Int) -> String {
        let png: Set<Int> = [7, 9, 16, 20, 22, 23]
        return String(format: "sky_%02d.%@", i, png.contains(i) ? "png" : "jpg")
    }

    private func globalMiniPalette(selected: Binding<String>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 5), count: 4), spacing: 5) {
            ForEach(palette, id: \.self) { hex in
                Button { selected.wrappedValue = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 19, height: 19)
                        .overlay(
                            Circle().stroke(
                                selected.wrappedValue == hex ? HoldOnTheme.purple : Color.black.opacity(0.10),
                                lineWidth: selected.wrappedValue == hex ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

}


private struct GlobalCardPreview: View {
    @ObservedObject private var fonts = HoldOnFontManager.shared
    let ratio: String
    let backgroundKind: String
    let backgroundValue: String
    let titleFont: String
    let titleSize: Double
    let inkHex: String
    let photoURL: URL?

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        previewBackground
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: geo.size.width, height: geo.size.height)

                        VStack(spacing: 4) {
                            Text("18:42")
                                .font(titleFont == "serif"
                                      ? fonts.swiftUIFont(size: CGFloat(titleSize), bold: true)
                                      : .system(size: titleSize, weight: .semibold))
                                .foregroundStyle(Color(hex: inkHex))
                            Text("2026.09.14  ·  18:42  ·  HOLD ON")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(hex: inkHex).opacity(0.86))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            }
            .clipped()
    }

    @ViewBuilder
    private var previewBackground: some View {
        if backgroundKind == "album",
           let photoURL,
           let image = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if backgroundKind == "solid" {
            Color(hex: backgroundValue)
        } else if backgroundKind == "gradient" {
            let pair = gradientPair(backgroundValue)
            LinearGradient(
                colors: [Color(hex: pair.0), Color(hex: pair.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if backgroundKind == "sky",
                  let image = globalSkyImage(backgroundValue == "auto" ? automaticSkyFile(for: Date()) : backgroundValue) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.58, blue: 0.90),
                    Color(red: 0.78, green: 0.68, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var aspect: CGFloat {
        switch ratio {
        case "3:2": return 1.5
        case "1:1": return 1
        case "9:16": return 9.0 / 16.0
        default: return 4
        }
    }

    private func gradientPair(_ value: String) -> (String, String) {
        if value.contains("|") {
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        switch value {
        case "blue": return ("#7297B8", "#D6E5F1")
        case "rose": return ("#A987B8", "#E8CCD9")
        default: return ("#758DD8", "#C8A8E2")
        }
    }

    private func automaticSkyFile(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .day, .minute], from: date)
        let h = c.hour ?? 12
        let seed = ((c.day ?? 1) * 37 + (c.minute ?? 0))
        let pool: [String]
        switch h {
        case 0..<5, 21..<24:
            pool = ["sky_01.jpg","sky_02.jpg","sky_14.jpg","sky_15.jpg","sky_22.png","sky_23.png"]
        case 5..<8:
            pool = ["sky_03.jpg","sky_04.jpg","sky_17.jpg","sky_21.jpg"]
        case 8..<17:
            pool = ["sky_05.jpg","sky_06.jpg","sky_07.png","sky_08.jpg","sky_10.jpg","sky_12.jpg","sky_19.jpg"]
        default:
            pool = ["sky_09.png","sky_11.jpg","sky_13.jpg","sky_16.png","sky_18.jpg","sky_20.png","sky_21.jpg"]
        }
        return pool[abs(seed) % pool.count]
    }

    private func globalSkyImage(_ file: String) -> UIImage? {
        guard file != "auto" else { return nil }
        let ns = file as NSString
        guard let url = Bundle.main.url(
            forResource: ns.deletingPathExtension,
            withExtension: ns.pathExtension,
            subdirectory: "SkyAssets"
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct GlobalSkyThumb: View {
    let file: String
    var body: some View {
        if let image = load() {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.gray.opacity(0.15)
        }
    }
    private func load() -> UIImage? {
        let ns = file as NSString
        guard let url = Bundle.main.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension, subdirectory: "SkyAssets") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}


private enum StorageCleanupMode: String, Identifiable {
    case old, exported, large
    var id: String { rawValue }

    var title: String {
        switch self {
        case .old: return "오래된 기억 정리"
        case .exported: return "내보낸 기억 정리"
        case .large: return "큰 용량부터 정리"
        }
    }
}

private struct StorageManagementView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showEmptyTrashConfirm = false

    private var formatter: ByteCountFormatter {
        let value = ByteCountFormatter()
        value.countStyle = .file
        value.allowedUnits = [.useKB, .useMB, .useGB]
        value.includesUnit = true
        return value
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("HOLD ON 데이터")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HoldOnTheme.muted)
                        Text(formatter.string(fromByteCount: engine.holdOnDataBytes()))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(HoldOnTheme.ink)
                        Text("저장된 기억 · 지운 기억 · 최근 대기 오디오가 사용하는 공간이에요.")
                            .font(.system(size: 11))
                            .foregroundStyle(HoldOnTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(spacing: 0) {
                        cleanupLink(.old, symbol: "calendar.badge.minus", subtitle: "30일 · 90일 · 1년 지난 기억을 골라 정리")
                        Divider().padding(.leading, 54)
                        cleanupLink(.exported, symbol: "square.and.arrow.up", subtitle: "사진 앱에 내보낸 기억만 골라 정리")
                        Divider().padding(.leading, 54)
                        cleanupLink(.large, symbol: "arrow.down.circle", subtitle: "용량이 큰 기억부터 확인하고 선택")
                    }
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        Button { showEmptyTrashConfirm = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.red)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("지운 기억함 비우기")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(HoldOnTheme.ink)
                                    Text(trashSubtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(HoldOnTheme.muted)
                                }
                                Spacer()
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.trashedMoments.isEmpty)
                    }
                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("정리 목록에서 기억을 고르면 먼저 지운 기억함으로 이동해요. 실제 저장공간은 ‘지운 기억함 비우기’ 후 확보됩니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(HoldOnTheme.muted)
                        .lineSpacing(3)
                        .padding(.horizontal, 4)

                    Text("내보낸 기억 여부는 이 버전부터 기록해요. 이전 버전에서 이미 내보낸 기억은 자동으로 구분되지 않을 수 있어요.")
                        .font(.system(size: 10))
                        .foregroundStyle(HoldOnTheme.muted.opacity(0.9))
                        .lineSpacing(3)
                        .padding(.horizontal, 4)
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(HoldOnTheme.background)
            .navigationTitle("저장공간 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .confirmationDialog("지운 기억함을 완전히 비울까요?", isPresented: $showEmptyTrashConfirm, titleVisibility: .visible) {
                Button("완전히 삭제", role: .destructive) { engine.emptyTrash() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("사진 앱에 따로 내보낸 영상은 그대로 유지되지만, HOLD ON 안의 원본과 편집 데이터는 복구할 수 없어요.")
            }
        }
    }

    private var trashSubtitle: String {
        guard !engine.trashedMoments.isEmpty else { return "비울 항목이 없어요" }
        return "\(engine.trashedMoments.count)개 · 약 \(formatter.string(fromByteCount: engine.trashStorageBytes())) 확보 가능"
    }

    private func cleanupLink(_ mode: StorageCleanupMode, symbol: String, subtitle: String) -> some View {
        NavigationLink {
            StorageCleanupListView(mode: mode)
                .environmentObject(engine)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HoldOnTheme.purple)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HoldOnTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HoldOnTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HoldOnTheme.muted)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
}

private struct StorageCleanupListView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    let mode: StorageCleanupMode
    @State private var selected = Set<UUID>()
    @State private var ageDays = 90
    @State private var showMoveConfirm = false

    private var formatter: ByteCountFormatter {
        let value = ByteCountFormatter()
        value.countStyle = .file
        value.allowedUnits = [.useKB, .useMB, .useGB]
        value.includesUnit = true
        return value
    }

    private var candidates: [SavedMoment] {
        switch mode {
        case .old:
            let cutoff = Date().addingTimeInterval(-Double(ageDays) * 24 * 60 * 60)
            return engine.savedMoments.filter { $0.createdAt < cutoff }.sorted { $0.createdAt < $1.createdAt }
        case .exported:
            return engine.savedMoments.filter { $0.exportedToPhotosAt != nil }.sorted { ($0.exportedToPhotosAt ?? .distantPast) > ($1.exportedToPhotosAt ?? .distantPast) }
        case .large:
            return engine.savedMoments.sorted { engine.momentStorageBytes($0) > engine.momentStorageBytes($1) }
        }
    }

    private var selectedMoments: [SavedMoment] {
        candidates.filter { selected.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedMoments.reduce(0) { $0 + engine.momentStorageBytes($1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if mode == .old {
                Picker("기준", selection: $ageDays) {
                    Text("30일").tag(30)
                    Text("90일").tag(90)
                    Text("1년").tag(365)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onChange(of: ageDays) { _, _ in selected.removeAll() }
            }

            if candidates.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: mode == .exported ? "square.and.arrow.up" : "externaldrive",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(candidates) { moment in
                            Button { toggle(moment.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(moment.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(selected.contains(moment.id) ? HoldOnTheme.purple : HoldOnTheme.muted)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(moment.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(HoldOnTheme.ink)
                                            .lineLimit(1)
                                        Text(itemSubtitle(moment))
                                            .font(.system(size: 10))
                                            .foregroundStyle(HoldOnTheme.muted)
                                    }
                                    Spacer()
                                    Text(formatter.string(fromByteCount: engine.momentStorageBytes(moment)))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(HoldOnTheme.ink.opacity(0.72))
                                }
                                .padding(13)
                                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                VStack(spacing: 8) {
                    Text(selected.isEmpty ? "정리할 기억을 선택하세요" : "\(selected.count)개 · 약 \(formatter.string(fromByteCount: selectedBytes))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HoldOnTheme.muted)
                    Button { showMoveConfirm = true } label: {
                        Text("선택한 기억을 지운 기억함으로 이동")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(HoldOnTheme.purple, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(selected.isEmpty)
                    .opacity(selected.isEmpty ? 0.45 : 1)
                }
                .padding(14)
                .background(.ultraThinMaterial)
            }
        }
        .background(HoldOnTheme.background)
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("선택한 기억을 정리할까요?", isPresented: $showMoveConfirm, titleVisibility: .visible) {
            Button("지운 기억함으로 이동", role: .destructive) {
                engine.moveToTrash(selectedMoments)
                selected.removeAll()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("바로 완전히 삭제되지는 않아요. 저장공간 관리에서 지운 기억함을 비우면 실제 용량이 확보됩니다.")
        }
    }

    private var emptyTitle: String {
        switch mode {
        case .old: return "해당 기간의 기억이 없어요"
        case .exported: return "내보낸 것으로 기록된 기억이 없어요"
        case .large: return "저장된 기억이 없어요"
        }
    }

    private var emptyDescription: String {
        mode == .exported ? "앞으로 사진 앱으로 내보낸 기억은 이곳에서 바로 골라 정리할 수 있어요." : "정리할 항목이 생기면 이곳에 표시돼요."
    }

    private func itemSubtitle(_ moment: SavedMoment) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy.MM.dd"
        if mode == .exported, let exported = moment.exportedToPhotosAt {
            return "저장 \(f.string(from: moment.createdAt)) · 내보냄 \(f.string(from: exported))"
        }
        return f.string(from: moment.createdAt)
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
