from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[1]
read = lambda rel: (root / rel).read_text(encoding='utf-8')
project = read('HoldOnRebuild.xcodeproj/project.pbxproj')
yaml = read('codemagic.yaml')
app = read('HoldOnRebuild/HoldOnRebuildApp.swift')
home = read('HoldOnRebuild/Screens/HomeView.swift')
memories = read('HoldOnRebuild/Screens/MemoriesView.swift')
detail = read('HoldOnRebuild/Screens/MemoryDetailView.swift')
editor = read('HoldOnRebuild/Screens/AudioSubtitleEditorView.swift')
settings = read('HoldOnRebuild/Screens/SettingsView.swift')
rootview = read('HoldOnRebuild/RootView.swift')
tutorial = read('HoldOnRebuild/Screens/HoldOnTutorialView.swift')
engine = read('HoldOnRebuild/Engine/AudioHoldEngine.swift')
model = read('HoldOnRebuild/Models/SavedMoment.swift')
theme = read('HoldOnRebuild/Theme/HoldOnTheme.swift')
subtitle = read('HoldOnRebuild/Components/HoldOnSubtitleLayout.swift')
card = read('HoldOnRebuild/Components/MemoryCard.swift')
purchase = read('HoldOnRebuild/Monetization/HoldOnPurchaseManager.swift')
rewarded = read('HoldOnRebuild/Monetization/HoldOnRewardedAdManager.swift')
paywall = read('HoldOnRebuild/Monetization/HoldOnPremiumAccessView.swift')
plist = read('HoldOnRebuild/Info.plist')
active_swift = '\n'.join(p.read_text(encoding='utf-8') for p in (root/'HoldOnRebuild').rglob('*.swift'))

checks = {
    'build 156 all four configs': project.count('CURRENT_PROJECT_VERSION = 156;') == 4,
    'no other active project build number': all(v == '156' for v in re.findall(r'CURRENT_PROJECT_VERSION = (\d+);', project)),
    'codemagic expects build 156': 'CURRENT_PROJECT_VERSION = 156;' in yaml and 'verify_build156.py' in yaml,
    'marketing version stays 1.0': project.count('MARKETING_VERSION = 1.0;') == 4,
    'main bundle id retained': 'PRODUCT_BUNDLE_IDENTIFIER = com.soso.holdon;' in project,
    'control bundle id retained': 'PRODUCT_BUNDLE_IDENTIFIER = com.soso.holdon.controls;' in project,
    'font download retained': 'GowunBatang-Regular.ttf' in yaml and 'GowunBatang-Bold.ttf' in yaml and 'OFL-GowunBatang.txt' in yaml,
    'no font binary shipped in source zip': not any((root/'HoldOnRebuild').rglob('*.ttf')) and not any((root/'HoldOnRebuild').rglob('*.otf')),
    'tutorial split into own source file': 'HoldOnTutorialView.swift' in project and 'F30000000000000000000002' in project and 'struct HoldOnTutorialView' not in rootview,
    'tutorial revision key forces new walkthrough once': 'holdon.tutorial.completed.v2' in rootview,
    'tutorial uses horizontal paging': 'TabView(selection: $page)' in tutorial and '.tabViewStyle(.page(indexDisplayMode: .never))' in tutorial,
    'tutorial has previous and next controls': 'Label("이전", systemImage: "chevron.left")' in tutorial and 'Text(page == pages.count - 1 ? "시작하기" : "다음")' in tutorial,
    'tutorial has ten focused pages': tutorial.count('.init(') == 10,
    'tutorial makes prebuffer requirement explicit': '먼저 HOLD ON을 켜두세요' in tutorial and '켜져 있을 때만 최근 5분을 임시로 담아요.' in tutorial and 'OFF였던 시간의 소리는 가져올 수 없어요' in tutorial,
    'tutorial quick capture appears early': tutorial.find('앱을 열지 않고 바로 잡아요') < tutorial.find('한 번 잡고, 다시 눌러 저장해요'),
    'tutorial includes capture cancel': '저장하지 않고 중단' in tutorial,
    'tutorial includes capture point replay': '잡은 순간부터 바로 들어보세요' in tutorial,
    'tutorial includes split and quiet cleanup': '필요한 부분만 남겨요' in tutorial and '나누기' in tutorial and '무음 제거' in tutorial and 'speaker.slash' in tutorial,
    'tutorial includes export storage routine settings revisit': all(x in tutorial for x in ['사진과 함께 내보내세요','용량 관리','자주 쓰는 시간은 루틴으로','사용법 다시 보기','이미 만든 기억은 그대로예요.']),
    'settings can reopen tutorial': '사용법 다시 보기' in settings and 'HoldOnTutorialView' in settings,
    'storage management entry exists': '저장공간 관리' in settings and 'StorageManagementView' in settings,
    'storage cleanup has old exported and large modes': all(x in settings for x in ['오래된 기억 정리','내보낸 기억 정리','큰 용량부터 정리','지운 기억함 비우기']),
    'export success is tracked locally': 'exportedToPhotosAt' in model and 'markMomentExportedToPhotos' in engine and 'engine.markMomentExportedToPhotos(id: moment.id)' in detail,
    'storage usage counts saved and rolling data': 'directoryBytes(savedURL) + directoryBytes(rollingURL)' in engine,
    'trash empty removes original audio too': 'deleteMomentFiles(record.moment)' in engine and 'func emptyTrash()' in engine,
    'future-fragile ad tracking claim removed': '광고 추적 없음' not in settings and '광고 SDK나 행동 추적용 분석 도구를 사용하지 않아요.' not in settings,
    'memory normal header archive is compact icon': 'Image(systemName: "archivebox")' in memories and '.accessibilityLabel("지운기억함")' in memories,
    'memory selection mode replaces cluttered header': 'if selectionMode {' in memories and 'Text("\\(selected.count)개 선택")' in memories and 'Button("완료")' in memories,
    'memory selection actions one-line and not blue prominent': 'selectionActionLabel("폴더로 이동"' in memories and '.lineLimit(1)' in memories and '.buttonStyle(.borderedProminent)' not in memories[memories.find('private var selectionActionBar'):memories.find('private func toggle')],
    'folder select-all respects current filter': r'selected = Set(moments.map(\.id))' in memories,
    'shared title editor exists': 'struct HoldOnTitleEditor' in subtitle and '제목 스타일' in subtitle and 'Slider(value:' in subtitle,
    'detail and editor use same title editor': 'HoldOnTitleEditor(' in detail and 'HoldOnTitleEditor(' in editor,
    'old crowded detail title implementation removed': 'textformat.size.smaller' not in detail and 'SelectAllTextField' not in detail,
    'old crowded editor title implementation removed': 'textformat.size.smaller' not in editor and '@FocusState private var titleTextFocused' not in editor,
    'title style is one button plus sheet': 'accessibilityLabel("제목 글꼴과 크기")' in subtitle and 'Picker("글꼴"' in subtitle and '제목 크기' in subtitle,
    'title keyboard done and external resign path retained': '.submitLabel(.done)' in subtitle and 'commitAndDismiss()' in subtitle and 'dismissAllKeyboards()' in editor,
    'subtitle keyboard alignment popup removed': 'ToolbarItemGroup(placement: .keyboard)' in editor and 'text.alignleft' not in editor[editor.find('ToolbarItemGroup(placement: .keyboard)'):editor.find('.onAppear(perform: load)')],
    'subtitle style owns alignment controls': 'styleAlignmentButton("text.alignleft", "왼쪽"' in editor and 'styleAlignmentButton("text.aligncenter", "가운데"' in editor and 'styleAlignmentButton("text.alignright", "오른쪽"' in editor,
    'subtitle style alignment persists immediately': 'engine.updateSubtitles(momentID: momentID, cues: subtitles)' in editor[editor.find('private func setSubtitleAlignment'):editor.find('private func styleAlignmentButton')],
    'subtitle alignment visibly moves one-line cues': 'subtitles[index].x = 0.22' in editor and 'subtitles[index].x = 0.50' in editor and 'subtitles[index].x = 0.78' in editor,
    'subtitle selected overlay no longer expands to 88 percent': '.frame(maxWidth: canvasWidth * 0.88)' not in subtitle,
    'selected cue helper retained for subtitle actions': 'private var selectedCue: HoldOnSubtitleCue?' in editor and 'selectedSubtitleID' in editor,
    'subtitle duplicate beside add retained': editor.count('Label("복제", systemImage: "plus.square.on.square")') == 1 and editor.find('Label("추가"') < editor.find('Label("복제"'),
    'subtitle compact toolbar icon labels retained': all(x in editor for x in ['subtitleCompactAction("나누기", symbol: "scissors")','subtitleCompactAction("여기부터", symbol: "arrow.right.to.line")','subtitleCompactAction("여기까지", symbol: "arrow.left.to.line")','subtitleCompactAction("스타일", symbol: "slider.horizontal.3")']),
    'subtitle duplicate preserves style and playhead': 'var copy = source' in editor and 'copy.id = UUID()' in editor and 'proposedStart = min(max(0, position)' in editor,
    'capture cancel retained with confirmation': '진짜 중단할까요?' in home and '저장하지 않고 중단' in home and 'engine.cancelCapture()' in home,
    'routine reminder and tap-to-on retained': 'UNCalendarNotificationTrigger' in engine and 'HOLD ON을 켤 시간이에요' in engine and 'handleRoutineOnNotificationTap' in engine,
    'routine OFF auto and no silent ON catchup retained': 'Do NOT catch up by silently turning HOLD ON on when the app later returns.' in engine,
    'one-hour capture auto-cancels without save': '순간잡기가 1시간이 되어 저장 없이 자동 중단됐어요.' in engine,
    '55-minute warning retained': '5분 뒤 자동으로 중단돼요' in engine,
    'photo library save retained': 'PHAssetChangeRequest.creationRequestForAsset(from: image)' in home,
    'external audio recovery retained': 'recoverIfNeeded' in engine and 'interruption' in engine,
    'gowun font retained': 'GowunBatang-Regular' in theme and 'fonts.swiftUIFont' in card and 'fonts.swiftUIFont' in subtitle,
    'export dynamic fps retained with crisp final pass': 'CMTime(value: 1, timescale: 4)' in detail and 'AVAssetExportPresetHighestQuality' in detail and 'CGSize(width: 1920, height: 480)' in detail and 'AVVideoAverageBitRateKey: 4_800_000' in detail,
    'memory preview title/meta lifted above playback strip': '.offset(y: showsPlayback ? -12 : 0)' in card,
    'title stays single-line, shrinks, diagonal style icon retained': 'ZStack(alignment: .topTrailing)' in subtitle and '.lineLimit(1)' in subtitle and '.minimumScaleFactor(0.5)' in subtitle and '.allowsTightening(true)' in subtitle and '.offset(x: 9, y: -9)' in subtitle and '.lineLimit(1...3)' not in subtitle[subtitle.find('struct HoldOnTitleEditor'):],
    'export keeps previous meta and waveform visual scale': 'exportMetaSize(canvasWidth:' in detail and 'exportAudioMarkWidth(canvasWidth:' in detail and 'exportAudioMarkHeight(canvasWidth:' in detail and 'legacyExportWidth(for ratio:' in subtitle,
    'memory preview suppresses subtitles': 'activeSubtitles' not in card and 'ForEach(activeSubtitles)' not in card,
    'title selects all on focus': '#selector(UIResponder.selectAll(_:))' in subtitle,
    'subtitle selects all on edit': editor.count('#selector(UIResponder.selectAll(_:))') >= 1,
    'editor title width matches export safe width': '.frame(maxWidth: targetWidth * 0.88)' in editor,
    'memory rows support native swipe delete': '.swipeActions(edge: .trailing, allowsFullSwipe: false)' in memories and 'pendingDelete = moment' in memories,
    'rolling bitrate reduced for disk budget': 'channels == 1 ? 48_000 : 80_000' in engine,
    'quick capture successful start is not forced failed by activity race': '_ = HoldOnCaptureActivity.startIfNeeded()' in read('HoldOnRebuild/QuickControl/HoldOnControlIntent.swift') and 'quickControlLiveActivityUnavailable' not in read('HoldOnRebuild/QuickControl/HoldOnControlIntent.swift'),
    'no legacy web app layer': 'WKWebView' not in active_swift,
    'photos HOLD ON album helper retained': 'saveVideoToHoldOnAlbum' in active_swift and 'saveImageToHoldOnAlbum' in active_swift and 'creationRequestForAssetCollection(withTitle: albumTitle)' in active_swift,
    'playback boost is non destructive and capped at five': 'playbackGain' in model and 'HoldOnBoostedAudioPlayer' in engine and 'min(5.0, max(1.0, gain))' in engine and '재생 음량' in editor,
    'quiet section cleanup remains reversible': 'tidyQuietSections()' in editor and '무음 제거' in editor and 'Undo로 되돌릴 수 있어요' in editor,
    'audio edit tools are one compact four-item row': 'HStack(spacing: 6)' in editor and 'editButton("나누기"' in editor and 'editButton(currentSegmentExcluded ? "복원" : "제외"' in editor and 'editButton("무음 제거", "speaker.slash")' in editor and r'Text("음량 \(Int(moment?.playbackGain ?? 1.0))×")' in editor,
    'audio edit UI no longer adds second tool row': editor.count('editButton("나누기"') == 1 and '음량 증폭은 재생에만 적용되고 원본 오디오는 그대로예요' not in editor,
    'external media route avoids bluetooth HFP': '.allowBluetoothA2DP' in engine and '.allowBluetoothHFP' not in engine,
    'static export seed uses two samples': 'let stillTimes = [0.0, max(duration, 1.0)]' in detail,
    'phone interruption delayed rebuild retained': 'interruptionEndedDelayed' in engine and '.milliseconds(650)' in engine,
    'no aggressive primary-audio yield path remains': 'yieldToPrimaryAudio' not in engine and 'secondaryAudioShouldBeSilencedHint' not in engine and 'handleSecondaryAudioHint' not in engine,
    'standby fallback notification uses heartbeat grace': 'standbyHeartbeatGraceSeconds: TimeInterval = 120' in engine and 'UNTimeIntervalNotificationTrigger(timeInterval: standbyHeartbeatGraceSeconds' in engine and 'ticks % 6 == 0' in engine and 'refreshStandbyFallbackNotification(reason: "heartbeat")' in engine,
    'explicit stop cancels standby fallback notification': 'removePendingNotificationRequests(withIdentifiers: [standbyStoppedNotificationID])' in engine[engine.find('func stopHoldOn'):engine.find('func prepareForMemoryPlayback')],
    'recovery retries are cancellable single flight': 'recoveryRetryTask?.cancel()' in engine and 'recoveryRetryTask = Task' in engine,
    'failed standby preserves desired intent': 'markStandbyUnavailableAndNotify' in engine and 'UserDefaults.standard.bool(forKey: desiredStateKey)' in engine,
    'failed standby sends requested local notification': 'HOLD ON이 꺼졌어요.' in engine and '필요한 순간이라면 대기 모드를 다시 켜주세요.' in engine,
    'no new in-app status indicator source added': 'standbyIndicator' not in active_swift and 'microphoneStatusIndicator' not in active_swift,
    'storekit full access product id configured': 'com.soso.holdon.fullaccess' in purchase and 'Product.products(for:' in purchase and 'AppStore.sync()' in purchase,
    'full access transaction entitlements verified': 'Transaction.currentEntitlements' in purchase and 'case .verified(let transaction)' in purchase,
    'admob swift package linked': 'swift-package-manager-google-mobile-ads.git' in project and 'productName = GoogleMobileAds;' in project and 'GoogleMobileAds in Frameworks' in project,
    'admob application id configured': 'ca-app-pub-5978840146134387~1691289873' in plist,
    'build156 uses google rewarded test ad': 'useTestAds = true' in rewarded and 'ca-app-pub-3940256099942544/1712485313' in rewarded,
    'production rewarded id preserved for release switch': 'ca-app-pub-5978840146134387/6117620046' in rewarded,
    'rewarded ad stays opt in': '광고 보고 이번 한 번 사용' in paywall and 'showRewardedAd' in rewarded,
    'editor requires reward or full access': 'requestPremium(.editor)' in detail and 'HoldOnPremiumAccessView(context: context)' in detail,
    'video export requires reward or full access': 'Button("영상 → 사진 앱") { requestPremium(.videoExport) }' in detail,
    'raw audio file export stays available': 'Button("오디오 → 파일")' in detail,
    'settings exposes full access and restore': 'HOLD ON Full Access' in settings and 'HoldOnPremiumAccessView(context: .manage)' in settings and '구매 복원' in paywall,
    'core free features explicitly remain free': '순간잡기 · 저장 후 카메라 · 기억카드 꾸미기는 계속 무료예요.' in paywall,
    'privacy summary separates local recordings from ads': '선택형 광고' in settings and '녹음 내용은 광고 서비스로 보내지 않아요.' in settings,
    'no ATT tracking permission prompt added': 'NSUserTrackingUsageDescription' not in plist and 'ATTrackingManager' not in active_swift,
}
failed=[]
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' | ' + name)
    if not ok: failed.append(name)
print(f'\nTOTAL: {len(checks)-len(failed)}/{len(checks)} PASS')
if failed:
    print('FAILED:')
    for name in failed: print(' -', name)
    sys.exit(1)