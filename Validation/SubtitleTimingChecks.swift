import Foundation

@main
struct SubtitleTimingChecks {
    static func main() {
        var moment = SavedMoment(id: UUID(), createdAt: Date(), title: "test", audioFileName: "test.m4a", preSeconds: 20, durationSeconds: 100)
        moment.subtitles = [HoldOnSubtitleCue(start: 20, end: 30, text: "unchanged")]
        assert(moment.exportSubtitles.first?.start == 20)
        assert(moment.exportSubtitles.first?.end == 30)
        moment.audioEdit = HoldOnAudioEditState(trimStart: 0.1, trimEnd: 0.9, deletedRanges: [[0.3, 0.5]], sourceDuration: 100)
        moment.durationSeconds = 60
        moment.subtitles = [
            HoldOnSubtitleCue(start: 0, end: 5, text: "before trim"),
            HoldOnSubtitleCue(start: 35, end: 45, text: "inside cut"),
            HoldOnSubtitleCue(start: 25, end: 55, text: "across cut"),
            HoldOnSubtitleCue(start: 60, end: 70, text: "after cut"),
            HoldOnSubtitleCue(start: 95, end: 100, text: "after trim")
        ]
        let result = moment.exportSubtitles
        assert(result.count == 2)
        assert(result[0].text == "across cut")
        assert(abs(result[0].start - 15) < 0.001 && abs(result[0].end - 25) < 0.001)
        assert(abs(result[1].start - 30) < 0.001 && abs(result[1].end - 40) < 0.001)
        assert(moment.subtitles?.count == 5, "Export must not mutate source captions")
        print("PASS: edited subtitle timing and source preservation")
    }
}
