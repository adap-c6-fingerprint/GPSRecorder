import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - CSV 문자열 만들기

enum CSVExporter {
    private static let header: [String] = [
        "session_title", "session_started_at_local", "record_index",
        "recorded_at_utc", "recorded_at_local", "location_timestamp_utc",
        "latitude", "longitude", "horizontal_accuracy_m",
        "altitude_m", "ellipsoidal_altitude_m", "vertical_accuracy_m",
        "speed_mps", "speed_accuracy_mps", "course_deg", "course_accuracy_deg",
        "floor_level",
        "magnetic_heading_deg", "true_heading_deg", "heading_accuracy_deg", "heading_timestamp_utc",
        "is_simulated_by_software", "is_produced_by_accessory",
    ]

    // ISO 8601: 날짜·시간을 "2026-10-20T12:21:00.123Z"처럼 표기하는 국제 표준 형식
    private static let utcFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let localFormat = Date.ISO8601FormatStyle(
        timeZoneSeparator: .colon, includingFractionalSeconds: true, timeZone: .current
    )
    private static let fileStampFormat = Date.ISO8601FormatStyle(
        dateSeparator: .omitted, timeSeparator: .omitted, timeZone: .current
    )

    static func document(for session: RecordSession) -> CSVDocument {
        CSVDocument(
            fileName: "GPS_\(session.startedAt.formatted(fileStampFormat)).csv",
            text: makeCSV(for: session)
        )
    }

    static func makeCSV(for session: RecordSession) -> String {
        var lines = [header.joined(separator: ",")]

        for (index, record) in session.sortedRecords.enumerated() {
            let fields: [String] = [
                session.title,
                session.startedAt.formatted(localFormat),
                String(index + 1),
                record.recordedAt.formatted(utcFormat),
                record.recordedAt.formatted(localFormat),
                record.locationTimestamp.formatted(utcFormat),
                // String(Double)은 기기 언어 설정과 무관하게 소수점(.)을 쓰고 정밀도를 잃지 않습니다.
                String(record.latitude),
                String(record.longitude),
                String(record.horizontalAccuracy),
                String(record.altitude),
                String(record.ellipsoidalAltitude),
                String(record.verticalAccuracy),
                String(record.speed),
                String(record.speedAccuracy),
                String(record.course),
                String(record.courseAccuracy),
                text(record.floorLevel),
                text(record.magneticHeading),
                text(record.trueHeading),
                text(record.headingAccuracy),
                record.headingTimestamp.map { $0.formatted(utcFormat) } ?? "",
                text(record.isSimulatedBySoftware),
                text(record.isProducedByAccessory),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }

        // \u{FEFF}(BOM, Byte Order Mark): 엑셀이 이 파일을 UTF-8로 인식하게 해서 한글 깨짐을 막습니다.
        // \r\n: CSV 표준(RFC 4180)의 줄바꿈 문자
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    // Optional 값이 nil이면 빈 칸으로 출력
    private static func text<T>(_ value: T?) -> String {
        guard let value else { return "" }
        return String(describing: value)
    }

    // 값 안에 쉼표·따옴표·줄바꿈이 있으면 큰따옴표로 감싸고, 내부 따옴표는 두 번 써서 이스케이프
    private static func escape(_ field: String) -> String {
        let special = Set("\",\n\r".unicodeScalars)
        guard field.unicodeScalars.contains(where: { special.contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - 공유 가능한 CSV 파일

// Transferable: ShareLink 등으로 앱 밖에 "전달할 수 있는" 타입이 되기 위한 프로토콜.
// FileRepresentation: 공유하는 순간 임시 폴더에 .csv 파일을 써서 그 파일을 넘깁니다.
nonisolated struct CSVDocument: Transferable {
    let fileName: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { document in
            let url = URL.temporaryDirectory.appending(path: document.fileName)
            try Data(document.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
