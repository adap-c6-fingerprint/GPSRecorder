import Foundation
import SwiftData

// 위치 기록과 독립된 스트림입니다. 같은 센서 값이 반복되어도 콜백마다 한 건을 저장합니다.
@Model
final class BarometerRecord {
    var recordedAt: Date
    var sensorTimestamp: Double
    var pressureKPa: Double
    var relativeAltitudeM: Double
    var sequenceIndex: Int
    var session: RecordSession?

    init(sample: BarometerSample, sequenceIndex: Int) {
        recordedAt = sample.recordedAt
        sensorTimestamp = sample.sensorTimestamp
        pressureKPa = sample.pressureKPa
        relativeAltitudeM = sample.relativeAltitudeM
        self.sequenceIndex = sequenceIndex
    }
}

@Model
final class ArrivalRecord {
    var recordedAt: Date
    var floorLevel: Int
    var sequenceIndex: Int
    var session: RecordSession?

    init(recordedAt: Date, floorLevel: Int, sequenceIndex: Int) {
        self.recordedAt = recordedAt
        self.floorLevel = floorLevel
        self.sequenceIndex = sequenceIndex
    }
}
