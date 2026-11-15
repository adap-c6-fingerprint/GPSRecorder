import Foundation

enum SurveyCSVExporter {
    // 기존 위치 CSV와 같은 UTC 및 소수 초를 포함하는 ISO-8601 형식입니다.
    private static let utcFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func barometerDocument(for session: RecordSession) -> CSVDocument {
        CSVDocument(fileName: fileBase(for: session) + "_baro.csv", text: barometerCSV(for: session))
    }

    static func arrivalDocument(for session: RecordSession) -> CSVDocument {
        CSVDocument(fileName: fileBase(for: session) + "_arrivals.csv", text: arrivalCSV(for: session))
    }

    static func barometerCSV(for session: RecordSession) -> String {
        let rows = session.barometerRecords.sorted { $0.sequenceIndex < $1.sequenceIndex }.map {
            [
                $0.recordedAt.formatted(utcFormat),
                String($0.sensorTimestamp),
                String($0.pressureKPa),
                String($0.relativeAltitudeM),
                session.title,
            ]
        }
        return csv(
            header: ["recorded_at_utc", "sensor_timestamp_s", "pressure_kpa", "relative_altitude_m", "session_title"],
            rows: rows
        )
    }

    static func arrivalCSV(for session: RecordSession) -> String {
        let rows = session.arrivals.sorted { $0.sequenceIndex < $1.sequenceIndex }.map {
            [$0.recordedAt.formatted(utcFormat), String($0.floorLevel), session.title]
        }
        return csv(header: ["recorded_at_utc", "floor_level", "session_title"], rows: rows)
    }

    private static func csv(header: [String], rows: [[String]]) -> String {
        let lines = [header.joined(separator: ",")] + rows.map { $0.map(escape).joined(separator: ",") }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { "\",\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func fileBase(for session: RecordSession) -> String {
        let disallowed = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        let sanitized = session.title.components(separatedBy: disallowed).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty || sanitized == "." || sanitized == ".." ? "GPS" : String(sanitized.prefix(100))
    }
}
