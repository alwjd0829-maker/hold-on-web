import Foundation

struct HoldOnAudioEditState: Codable, Hashable {
    var trimStart: Double = 0
    var trimEnd: Double = 1
    var deletedRanges: [[Double]] = []
    // Duration of the untouched source timeline. Keeping this separate prevents
    // edit fractions/subtitle times from drifting after the rendered file gets shorter.
    var sourceDuration: Double? = nil
    var splitPoints: [Double]? = nil
}

struct HoldOnSubtitleCue: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var text: String
    var x: Double = 0.5
    var y: Double = 0.66
    var scale: Double = 1
    var font: String = "serif"
    var textHex: String = "#FFFFFF"
    var backgroundHex: String = "#000000"
    var backgroundAlpha: Double = 0.35
    var lane: Int = 0
    var alignment: String? = nil
}

struct SavedMoment: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var title: String
    let audioFileName: String
    let preSeconds: Int
    var durationSeconds: Double

    // Card appearance is stored with each memory so list/detail/editor/export all read the same source of truth.
    // Optional fields keep old Build 9/earlier saved indexes decodable.
    var cardRatio: String? = nil
    var cardBackgroundKind: String? = nil
    var cardBackgroundValue: String? = nil
    var titleFont: String? = nil
    var titleSize: Double? = nil
    var inkHex: String? = nil
    var showsHoldOnMark: Bool? = nil
    var cardImageRevision: Int? = nil
    var folderName: String? = nil
    // Non-destructive listening boost. 1.0 = original level, up to 5.0.
    // This never rewrites the saved/original audio file.
    var playbackGain: Double? = nil
    // Set after a HOLD ON video is successfully exported to Photos.
    // Optional keeps memories created by earlier builds decodable.
    var exportedToPhotosAt: Date? = nil

    // Non-destructive editor state. The original recording stays in original_<id>.m4a.
    var audioEdit: HoldOnAudioEditState? = nil
    var subtitles: [HoldOnSubtitleCue]? = nil

    var audioURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HoldOnSaved", isDirectory: true)
            .appendingPathComponent(audioFileName)
    }

    var cardImageURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HoldOnSaved", isDirectory: true)
            .appendingPathComponent("card_\(id.uuidString).jpg")
    }
}


extension SavedMoment {
    /// Export uses the edited audio timeline; stored captions retain source timestamps.
    var exportSubtitles: [HoldOnSubtitleCue] {
        (subtitles ?? []).compactMap { cue in
            var mapped = cue
            mapped.start = playbackTimelineTime(forSourceTime: cue.start)
            mapped.end = playbackTimelineTime(forSourceTime: cue.end)
            return mapped.end > mapped.start ? mapped : nil
        }
    }
    /// Maps the edited audio player's current time back to the untouched source timeline.
    /// Subtitle cues are stored on the source timeline so cuts never permanently desynchronize them.
    func sourceTimelineTime(forPlaybackTime playbackTime: Double) -> Double {
        guard let edit = audioEdit,
              let sourceDuration = edit.sourceDuration,
              sourceDuration > 0 else {
            return max(0, playbackTime)
        }

        let start = min(max(edit.trimStart, 0), 1)
        let end = min(max(edit.trimEnd, start), 1)
        let cuts = edit.deletedRanges.compactMap { range -> (Double, Double)? in
            guard range.count >= 2 else { return nil }
            let a = min(max(range[0], start), end)
            let b = min(max(range[1], a), end)
            return b > a ? (a, b) : nil
        }.sorted { $0.0 < $1.0 }

        var keep: [(Double, Double)] = []
        var cursor = start
        for (a, b) in cuts {
            if a > cursor { keep.append((cursor, a)) }
            cursor = max(cursor, b)
        }
        if cursor < end { keep.append((cursor, end)) }
        if keep.isEmpty { keep = [(start, end)] }

        var remaining = max(0, playbackTime)
        for (a, b) in keep {
            let segmentSeconds = sourceDuration * (b - a)
            if remaining <= segmentSeconds {
                return sourceDuration * a + remaining
            }
            remaining -= segmentSeconds
        }
        return sourceDuration * end
    }
    /// Maps a timestamp on the untouched source timeline into the edited playback timeline.
    /// If the source point falls inside an excluded range, the marker snaps to that cut boundary.
    func playbackTimelineTime(forSourceTime sourceTime: Double) -> Double {
        guard let edit = audioEdit,
              let sourceDuration = edit.sourceDuration,
              sourceDuration > 0 else {
            return max(0, min(sourceTime, durationSeconds))
        }

        let start = min(max(edit.trimStart, 0), 1)
        let end = min(max(edit.trimEnd, start), 1)
        let sourceFraction = min(max(sourceTime / sourceDuration, start), end)
        let cuts = edit.deletedRanges.compactMap { range -> (Double, Double)? in
            guard range.count >= 2 else { return nil }
            let a = min(max(range[0], start), end)
            let b = min(max(range[1], a), end)
            return b > a ? (a, b) : nil
        }.sorted { $0.0 < $1.0 }

        var elapsed: Double = 0
        var cursor = start
        for (a, b) in cuts {
            if sourceFraction <= a {
                elapsed += sourceDuration * max(0, sourceFraction - cursor)
                return min(max(0, elapsed), durationSeconds)
            }
            if a > cursor { elapsed += sourceDuration * (a - cursor) }
            if sourceFraction < b {
                return min(max(0, elapsed), durationSeconds)
            }
            cursor = max(cursor, b)
        }
        if sourceFraction > cursor { elapsed += sourceDuration * (sourceFraction - cursor) }
        return min(max(0, elapsed), durationSeconds)
    }

}
