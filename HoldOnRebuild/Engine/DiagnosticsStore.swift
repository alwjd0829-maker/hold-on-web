import Foundation
import UIKit

@MainActor
final class DiagnosticsStore {
    struct Event: Codable {
        let at: Date
        let kind: String
        let details: [String: String]
    }

    private let fm = FileManager.default
    private let directory: URL
    private let markerURL: URL
    private let exportURL: URL
    private var logURL: URL?
    private var activeSessionID: UUID?
    private var activeSessionStartedAt: Date?

    init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("HoldOnDiagnostics", isDirectory: true)
        markerURL = directory.appendingPathComponent("active_session.json")
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        exportURL = documents.appendingPathComponent("HOLD_ON_TEST_LOG.jsonl")
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: exportURL.path) {
            fm.createFile(atPath: exportURL.path, contents: nil)
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        recoverIfNeeded()
    }

    func beginSession() {
        guard activeSessionID == nil else { return }
        let id = UUID()
        let start = Date()
        activeSessionID = id
        activeSessionStartedAt = start
        logURL = directory.appendingPathComponent("holdon-\(Self.fileStamp(start))-\(id.uuidString.prefix(8)).jsonl")
        writeMarker(id: id, startedAt: start)
        record("holdOnStarted", ["battery": batteryDescription(), "lowPowerMode": String(ProcessInfo.processInfo.isLowPowerModeEnabled)])
    }

    func endSession(reason: String) {
        guard activeSessionID != nil else { return }
        let duration = activeSessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        record("holdOnStopped", [
            "reason": reason,
            "durationSeconds": String(format: "%.1f", duration),
            "battery": batteryDescription()
        ])
        try? fm.removeItem(at: markerURL)
        activeSessionID = nil
        activeSessionStartedAt = nil
        logURL = nil
    }

    func record(_ kind: String, _ details: [String: String] = [:]) {
        guard let logURL else { return }
        let event = Event(at: Date(), kind: kind, details: details)
        guard let data = try? JSONEncoder().encode(event) else { return }
        let line = data + Data([0x0A])
        append(line, to: logURL)
        append(line, to: exportURL)
    }

    func recordHeartbeat(lastAudioAt: Date?, segmentCount: Int, rollingSeconds: TimeInterval) {
        var details: [String: String] = [
            "segments": String(segmentCount),
            "rollingSeconds": String(format: "%.1f", rollingSeconds),
            "battery": batteryDescription(),
            "lowPowerMode": String(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "thermalState": thermalStateDescription()
        ]
        if let lastAudioAt {
            details["lastAudioAgeSeconds"] = String(format: "%.2f", Date().timeIntervalSince(lastAudioAt))
        } else {
            details["lastAudioAgeSeconds"] = "none"
        }
        record("heartbeat", details)
    }

    private func recoverIfNeeded() {
        guard let data = try? Data(contentsOf: markerURL),
              let payload = try? JSONDecoder().decode(ActiveMarker.self, from: data) else { return }

        let recoveryURL = directory.appendingPathComponent("recovery-\(Self.fileStamp(Date())).jsonl")
        let event = Event(
            at: Date(),
            kind: "previousSessionEndedUncleanly",
            details: [
                "sessionID": payload.id.uuidString,
                "startedAt": ISO8601DateFormatter().string(from: payload.startedAt)
            ]
        )
        if let encoded = try? JSONEncoder().encode(event) {
            let line = encoded + Data([0x0A])
            append(line, to: recoveryURL)
            append(line, to: exportURL)
        }
        try? fm.removeItem(at: markerURL)
    }

    private struct ActiveMarker: Codable {
        let id: UUID
        let startedAt: Date
    }

    private func writeMarker(id: UUID, startedAt: Date) {
        let marker = ActiveMarker(id: id, startedAt: startedAt)
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: markerURL, options: .atomic)
    }

    private func append(_ data: Data, to url: URL) {
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func batteryDescription() -> String {
        let value = UIDevice.current.batteryLevel
        guard value >= 0 else { return "unknown" }
        return String(format: "%.0f%%", value * 100)
    }

    private func thermalStateDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
