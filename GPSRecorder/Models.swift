import Foundation
import SwiftData

// MARK: - 기록 묶음 (측정 1회 = 묶음 1개)

// @Model: SwiftData가 이 class를 "디스크에 저장되는 모델"로 다루도록 하는 매크로(macro).
// 저장 기능 + 변경 감지(Observation) 기능이 자동으로 붙습니다.
@Model
final class RecordSession {
    var title: String
    var startedAt: Date
    var endedAt: Date?        // nil이면 아직 측정 중
    var isStarred: Bool       // 중요 표시

    // 묶음 1개 : 기록 N개 관계.
    // deleteRule: .cascade → 묶음을 지우면 그 안의 기록도 함께 삭제됩니다.
    // inverse → LocationRecord.session과 서로 짝이라는 것을 SwiftData에 알려줍니다.
    @Relationship(deleteRule: .cascade, inverse: \LocationRecord.session)
    var records: [LocationRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \BarometerRecord.session)
    var barometerRecords: [BarometerRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \ArrivalRecord.session)
    var arrivals: [ArrivalRecord] = []

    init(title: String, startedAt: Date = .now) {
        self.title = title
        self.startedAt = startedAt
        self.endedAt = nil
        self.isStarred = false
    }

    var isActive: Bool { endedAt == nil }

    // SwiftData의 relationship 배열은 "저장 순서"를 보장하지 않습니다.
    // 그래서 화면 표시와 CSV 출력에는 항상 기록 시각 기준으로 정렬한 배열을 씁니다.
    var sortedRecords: [LocationRecord] {
        records.sorted { $0.recordedAt < $1.recordedAt }
    }
}

// MARK: - 기록 1건 ('기록' 버튼 1번 = 1건)

@Model
final class LocationRecord {
    // 사용자가 '기록' 버튼을 누른 시각
    var recordedAt: Date
    // 시스템이 이 위치를 계산한 시각 (버튼 시각과 약간 다를 수 있음)
    var locationTimestamp: Date

    // CLLocation이 제공하는 값들
    var latitude: Double             // 위도 (도)
    var longitude: Double            // 경도 (도)
    var horizontalAccuracy: Double   // 수평 오차 반경 (m), 음수면 무효
    var altitude: Double             // 해발 고도 (m)
    var ellipsoidalAltitude: Double  // WGS84 타원체 기준 고도 (m)
    var verticalAccuracy: Double     // 고도 오차 (m), 0 이하면 무효
    var speed: Double                // 속력 (m/s), 음수면 무효
    var speedAccuracy: Double        // 속력 오차 (m/s), 음수면 무효
    var course: Double               // 이동 방향 (도, 진북 기준), 음수면 무효
    var courseAccuracy: Double       // 이동 방향 오차 (도), 음수면 무효
    var floorLevel: Int?             // 건물 층 (지원되는 장소에서만 값이 있음)
    var isSimulatedBySoftware: Bool? // 시뮬레이터 등 소프트웨어가 만든 위치인지
    var isProducedByAccessory: Bool? // 외장 GPS 같은 액세서리가 만든 위치인지

    // CLHeading(나침반)이 제공하는 값들 — 나침반 센서가 없거나 아직 값이 없으면 nil
    var magneticHeading: Double?     // 자북 기준 방위 (도)
    var trueHeading: Double?         // 진북 기준 방위 (도), 음수면 무효
    var headingAccuracy: Double?     // 방위 오차 (도), 음수면 무효
    var headingTimestamp: Date?

    // 이 기록이 속한 묶음 (RecordSession.records의 짝)
    var session: RecordSession?

    init(recordedAt: Date, location: LocationSnapshot, heading: HeadingSnapshot?) {
        self.recordedAt = recordedAt
        self.locationTimestamp = location.timestamp
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.altitude = location.altitude
        self.ellipsoidalAltitude = location.ellipsoidalAltitude
        self.verticalAccuracy = location.verticalAccuracy
        self.speed = location.speed
        self.speedAccuracy = location.speedAccuracy
        self.course = location.course
        self.courseAccuracy = location.courseAccuracy
        self.floorLevel = location.floorLevel
        self.isSimulatedBySoftware = location.isSimulatedBySoftware
        self.isProducedByAccessory = location.isProducedByAccessory
        self.magneticHeading = heading?.magneticHeading
        self.trueHeading = heading?.trueHeading
        self.headingAccuracy = heading?.headingAccuracy
        self.headingTimestamp = heading?.timestamp
        self.session = nil
    }
}
