import ActivityKit
import SwiftUI
import WidgetKit

@main
struct HoldOnControlsBundle: WidgetBundle {
    var body: some Widget {
        HoldOnCaptureControl()
        HoldOnCaptureLiveActivityWidget()
    }
}

struct HoldOnCaptureControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: HoldOnControlVisualState { .idle }

        func currentValue() async throws -> HoldOnControlVisualState {
            HoldOnControlStateStore.state()
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: HoldOnCaptureControlKind.value,
            provider: Provider()
        ) { value in
            ControlWidgetButton(action: HoldOnControlIntent()) {
                // Use only built-in SF Symbols here. Text/custom assets can be replaced
                // with a question-mark placeholder in compact Lock Screen controls.
                Group {
                    switch value {
                    case .idle:
                        Image(systemName: "h.circle")
                    case .capturing:
                        Image(systemName: "waveform")
                    case .saved:
                        Image(systemName: "checkmark")
                    case .failed:
                        Image(systemName: "exclamationmark")
                    }
                }
                // Keep the control visually stable. The system may still draw its own
                // very short press feedback, but HOLD ON itself does not switch accent colors.
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
            }
            // Explicitly use the platform primary color instead of the default control accent.
            // This keeps H visually neutral after the action returns to idle.
            .tint(Color.primary)
        }
        .displayName("HOLD ON")
        .description("한 번 누르면 잡고, 다시 누르면 바로 저장합니다.")
    }
}

struct HoldOnCaptureLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HoldOnCaptureActivityAttributes.self) { _ in
            // AudioRecordingIntent requires a Live Activity while recording. A content-less
            // activity leaves a large empty capsule on the Lock Screen, so make the required
            // surface intentional but quiet instead of pretending it can be hidden.
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.caption2.weight(.semibold))
                Text("HOLD ON")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("HOLD ON 녹음 중")
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("HOLD ON", systemImage: "waveform")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .font(.caption2.weight(.semibold))
                    .accessibilityLabel("HOLD ON 녹음 중")
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "waveform")
                    .font(.caption2.weight(.semibold))
                    .accessibilityLabel("HOLD ON 녹음 중")
            }
        }
    }
}
