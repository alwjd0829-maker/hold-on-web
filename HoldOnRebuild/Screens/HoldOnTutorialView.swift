import SwiftUI

struct HoldOnTutorialView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [TutorialPage] = [
        .init(
            title: "먼저 HOLD ON을 켜두세요",
            body: "켜져 있을 때만 최근 5분을 임시로 담아요.",
            visual: .buffer
        ),
        .init(
            title: "지나간 순간도 잡을 수 있어요",
            body: "‘아, 방금!’ 했을 때 눌러도 돼요.",
            visual: .pastMoment
        ),
        .init(
            title: "앱을 열지 않고 바로 잡아요",
            body: "잠금화면 · 제어센터 · 동작 버튼에서 바로 순간잡기.",
            visual: .quickCapture
        ),
        .init(
            title: "한 번 잡고, 다시 눌러 저장해요",
            body: "잘못 눌렀다면 저장하지 않고 중단할 수 있어요.",
            visual: .captureSave
        ),
        .init(
            title: "잡은 순간부터 바로 들어보세요",
            body: "긴 녹음에서도 그 순간으로 바로 이동해요.",
            visual: .playFromCapture
        ),
        .init(
            title: "필요한 부분만 남겨요",
            body: "잡은 순간 근처로 이동 → 나누기 → 무음 제거 → 필요한 구간만 남기기.",
            visual: .trimAudio
        ),
        .init(
            title: "제목과 자막도 손볼 수 있어요",
            body: "제목을 누르고, 자막은 원하는 순간에 추가하세요.",
            visual: .editText
        ),
        .init(
            title: "사진과 함께 내보내세요",
            body: "내보낸 영상은 사진 앱에서 확인하고, 저장공간도 관리할 수 있어요.",
            visual: .export
        ),
        .init(
            title: "자주 쓰는 시간은 루틴으로",
            body: "ON 시간엔 알림을 눌러 켜고, OFF는 자동으로 꺼져요.",
            visual: .routine
        ),
        .init(
            title: "나에게 맞게 설정해두세요",
            body: "전체 기본값을 정할 수 있어요. 이미 만든 기억은 그대로예요.",
            visual: .settings
        )
    ]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("HOLD ON 사용법")
                    .font(.headline)
                Spacer()
                Button("나중에 보기", action: onFinish)
                    .buttonStyle(.plain)
                    .foregroundStyle(HoldOnTheme.muted)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    TutorialPageView(page: pages[index])
                        .tag(index)
                        .padding(.horizontal, 22)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeOut(duration: 0.18), value: page)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? HoldOnTheme.purple : HoldOnTheme.muted.opacity(0.25))
                        .frame(width: index == page ? 18 : 6, height: 6)
                        .animation(.easeOut(duration: 0.18), value: page)
                }
            }
            .accessibilityLabel("\(page + 1) / \(pages.count)")

            HStack(spacing: 10) {
                Button {
                    guard page > 0 else { return }
                    page -= 1
                } label: {
                    Label("이전", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .tint(HoldOnTheme.ink.opacity(0.16))
                .foregroundStyle(HoldOnTheme.ink)
                .disabled(page == 0)

                Button {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        page += 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(page == pages.count - 1 ? "시작하기" : "다음")
                        if page != pages.count - 1 { Image(systemName: "chevron.right") }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(HoldOnTheme.purple)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .foregroundStyle(HoldOnTheme.ink)
        .background(HoldOnTheme.background.ignoresSafeArea())
    }
}

private struct TutorialPage: Identifiable {
    enum Visual {
        case buffer, pastMoment, quickCapture, captureSave, playFromCapture, trimAudio, editText, export, routine, settings
    }
    let id = UUID()
    let title: String
    let body: String
    let visual: Visual
}

private struct TutorialPageView: View {
    let page: TutorialPage

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            TutorialVisual(visual: page.visual)
                .frame(height: 250)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 25, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(page.body)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HoldOnTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
    }
}

private struct TutorialVisual: View {
    let visual: TutorialPage.Visual

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.95)))

            switch visual {
            case .buffer:
                VStack(spacing: 18) {
                    HStack(spacing: 10) {
                        Text("HOLD ON")
                            .font(.system(size: 17, weight: .bold))
                        Spacer()
                        Capsule()
                            .fill(HoldOnTheme.purple)
                            .frame(width: 54, height: 30)
                            .overlay(Circle().fill(.white).frame(width: 24, height: 24).offset(x: 11))
                        Text("ON")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(HoldOnTheme.purple)
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 7) {
                        HStack(spacing: 4) {
                            ForEach(0..<28, id: \.self) { i in
                                Capsule()
                                    .fill(HoldOnTheme.purple.opacity(0.38 + Double(i % 4) * 0.10))
                                    .frame(width: 4, height: CGFloat(8 + (i * 5) % 24))
                            }
                        }
                        HStack {
                            Text("5분 전")
                            Spacer()
                            Text("지금")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HoldOnTheme.muted)
                    }
                    .padding(.horizontal, 28)

                    Label("OFF였던 시간의 소리는 가져올 수 없어요", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HoldOnTheme.ink.opacity(0.72))
                }

            case .pastMoment:
                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        Text("…대화 중…")
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(HoldOnTheme.ink.opacity(0.06), in: Capsule())
                        Image(systemName: "arrow.right")
                            .foregroundStyle(HoldOnTheme.muted)
                        Text("아, 방금!")
                            .fontWeight(.bold)
                    }
                    Button(action: {}) {
                        Label("순간잡기", systemImage: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 180, height: 52)
                            .background(HoldOnTheme.purple, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Label("미리 HOLD ON이 켜져 있어야 해요", systemImage: "record.circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HoldOnTheme.purple)
                }

            case .quickCapture:
                VStack(spacing: 20) {
                    HStack(spacing: 14) {
                        tutorialTile("lock.fill", "잠금화면")
                        tutorialTile("switch.2", "제어센터")
                        tutorialTile("button.programmable", "동작 버튼")
                    }
                    HStack(spacing: 8) {
                        Circle().fill(HoldOnTheme.purple).frame(width: 38, height: 38)
                            .overlay(Text("H").font(.system(size: 17, weight: .bold)).foregroundStyle(.white))
                        Image(systemName: "arrow.right")
                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(HoldOnTheme.purple)
                    }
                }

            case .captureSave:
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        tutorialCircle("waveform", "잡기")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(HoldOnTheme.muted)
                        tutorialCircle("checkmark", "저장")
                    }
                    Label("잘못 눌렀다면 저장하지 않고 중단", systemImage: "xmark.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HoldOnTheme.ink.opacity(0.72))
                }

            case .playFromCapture:
                HStack(spacing: 14) {
                    tutorialButton("play.fill", "재생")
                    tutorialButton("bookmark.fill", "잡은 순간")
                }

            case .trimAudio:
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        tutorialButton("bookmark.fill", "잡은 순간")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(HoldOnTheme.muted)
                        tutorialButton("scissors", "나누기")
                    }
                    tutorialButton("speaker.slash", "무음 제거")
                    HStack(spacing: 3) {
                        ForEach(0..<24, id: \.self) { i in
                            Capsule().fill(i < 8 || i > 18 ? Color.gray.opacity(0.25) : HoldOnTheme.purple.opacity(0.65))
                                .frame(width: 4, height: CGFloat(8 + (i * 7) % 24))
                        }
                    }
                }

            case .editText:
                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(HoldOnTheme.ink.opacity(0.34), lineWidth: 1)
                        .frame(width: 205, height: 42)
                        .overlay(HStack { Text("제목을 눌러 수정"); Spacer(); Image(systemName: "textformat") }.padding(.horizontal, 12).font(.system(size: 12, weight: .semibold)))
                    HStack(spacing: 10) {
                        tutorialButton("plus", "추가")
                        tutorialButton("plus.square.on.square", "복제")
                        tutorialButton("slider.horizontal.3", "스타일")
                    }
                }

            case .export:
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        tutorialButton("square.and.arrow.up", "내보내기")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(HoldOnTheme.muted)
                        tutorialButton("photo.on.rectangle", "사진 앱")
                    }
                    tutorialButton("externaldrive", "용량 관리")
                }

            case .routine:
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        tutorialButton("bell.badge", "ON 알림")
                        tutorialButton("power", "자동 OFF")
                    }
                    Label("ON 알림을 한 번 눌러 켜요", systemImage: "hand.tap.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HoldOnTheme.purple)
                }

            case .settings:
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        tutorialButton("slider.horizontal.3", "전체 설정")
                        tutorialButton("questionmark.circle", "사용법 다시 보기")
                    }
                    Text("전체 설정은 앞으로 만들 기억의 기본값")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HoldOnTheme.muted)
                }
            }
        }
    }

    private func tutorialCircle(_ symbol: String, _ text: String) -> some View {
        Circle()
            .fill(HoldOnTheme.purple.opacity(0.12))
            .frame(width: 78, height: 78)
            .overlay(VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 21, weight: .bold))
                Text(text).font(.system(size: 10, weight: .bold))
            }.foregroundStyle(HoldOnTheme.purple))
    }

    private func tutorialTile(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(HoldOnTheme.ink)
        .frame(width: 82, height: 82)
        .background(HoldOnTheme.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }

    private func tutorialButton(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
            Text(text).font(.system(size: 11, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(HoldOnTheme.ink)
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(HoldOnTheme.ink.opacity(0.055), in: Capsule())
    }
}
