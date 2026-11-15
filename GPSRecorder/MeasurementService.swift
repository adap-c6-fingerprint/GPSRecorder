import CoreMotion
import Foundation
import Observation
import SwiftData
import UIKit

nonisolated struct BarometerSample: Sendable {
    let recordedAt: Date
    let sensorTimestamp: TimeInterval
    let pressureKPa: Double
    let relativeAltitudeM: Double
}

@MainActor
protocol RelativeAltitudeSource {
    var isAvailable: Bool { get }
    var authorizationStatus: CMAuthorizationStatus { get }
    func start(receive: @escaping @MainActor (BarometerSample?, String?) -> Void)
    func stop()
}

@MainActor
final class CoreMotionAltitudeSource: RelativeAltitudeSource {
    private var altimeter = CMAltimeter()

    var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }
    var authorizationStatus: CMAuthorizationStatus { CMAltimeter.authorizationStatus() }

    func start(receive: @escaping @MainActor (BarometerSample?, String?) -> Void) {
        altimeter.stopRelativeAltitudeUpdates()
        // 세션마다 새 객체의 첫 이벤트를 상대 고도 0 m 기준으로 사용합니다.
        altimeter = CMAltimeter()
        altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
            // 센서 시각으로 환산하지 않고 콜백을 받은 시각을 바로 기록합니다.
            let receivedAt = Date.now
            let sample = data.map {
                BarometerSample(
                    recordedAt: receivedAt,
                    sensorTimestamp: $0.timestamp,
                    pressureKPa: $0.pressure.doubleValue,
                    relativeAltitudeM: $0.relativeAltitude.doubleValue
                )
            }
            let message = error?.localizedDescription
            // OperationQueue.main에서 콜백을 받으므로 같은 actor에서 동기적으로 처리합니다.
            MainActor.assumeIsolated { receive(sample, message) }
        }
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
    }
}

@MainActor
protocol LocationUpdating {
    func start()
    func stop()
}

extension LocationService: LocationUpdating {}

// 센서의 실행 수명을 측정 세션에 연결합니다.
@MainActor
@Observable
final class MeasurementService {
    private(set) var activeSession: RecordSession?
    private(set) var latestBarometerSample: BarometerSample?
    private(set) var barometerCount = 0
    private(set) var barometerStatus = "정지됨"
    private(set) var motionPermissionDenied = false
    private(set) var persistenceError: String?

    @ObservationIgnored private let locationUpdates: any LocationUpdating
    @ObservationIgnored private let altitudeSource: any RelativeAltitudeSource
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var runID: UUID?

    init(
        locationUpdates: any LocationUpdating,
        altitudeSource: any RelativeAltitudeSource = CoreMotionAltitudeSource()
    ) {
        self.locationUpdates = locationUpdates
        self.altitudeSource = altitudeSource
    }

    func isRecording(_ session: RecordSession) -> Bool {
        activeSession === session && session.isActive
    }

    func start(session: RecordSession, context: ModelContext) {
        // 화면 재표시나 중복 호출로 relativeAltitude 기준이 초기화되지 않도록 합니다.
        guard !isRecording(session), session.isActive else { return }
        finish()
        self.context = context
        activeSession = session
        latestBarometerSample = nil
        barometerCount = session.barometerRecords.count
        motionPermissionDenied = false
        persistenceError = nil
        save(context)
        locationUpdates.start()
        UIApplication.shared.isIdleTimerDisabled = true

        guard altitudeSource.isAvailable else {
            barometerStatus = "이 기기는 기압 측정을 지원하지 않습니다. 실제 iPhone에서 측정하세요."
            return
        }
        switch altitudeSource.authorizationStatus {
        case .denied, .restricted:
            motionPermissionDenied = true
            barometerStatus = "동작 및 피트니스 접근이 허용되지 않았습니다."
            return
        case .notDetermined, .authorized:
            break
        @unknown default:
            barometerStatus = "동작 및 피트니스 권한을 확인할 수 없습니다."
            return
        }

        let id = UUID()
        runID = id
        barometerStatus = "기압 업데이트를 기다리는 중…"
        altitudeSource.start { [weak self] sample, errorMessage in
            guard let self, self.runID == id,
                  let session = self.activeSession, session.isActive else { return }
            if let sample {
                let record = BarometerRecord(sample: sample, sequenceIndex: self.barometerCount)
                context.insert(record)
                session.barometerRecords.append(record)
                self.barometerCount += 1
                self.latestBarometerSample = sample
                self.barometerStatus = "기압 자동 기록 중"
                // 간격 제한, 평균화, 중복 제거 없이 매번 디스크에 저장합니다.
                self.save(context)
            }
            if let errorMessage {
                self.motionPermissionDenied = self.altitudeSource.authorizationStatus == .denied
                    || self.altitudeSource.authorizationStatus == .restricted
                self.barometerStatus = "기압 업데이트가 중지되었습니다: \(errorMessage)"
                self.runID = nil
                self.altitudeSource.stop()
            }
        }
    }

    func recordArrival(floor: Int, at date: Date = .now) {
        guard let session = activeSession, session.isActive, let context else { return }
        let marker = ArrivalRecord(
            recordedAt: date, floorLevel: floor, sequenceIndex: session.arrivals.count
        )
        context.insert(marker)
        session.arrivals.append(marker)
        save(context)
    }

    func finish() {
        guard let session = activeSession else { return }
        // 늦게 도착한 이전 콜백이 다음 세션에 섞이지 않도록 합니다.
        runID = nil
        altitudeSource.stop()
        locationUpdates.stop()
        session.endedAt = .now
        if let context { save(context) }
        activeSession = nil
        context = nil
        barometerStatus = "정지됨"
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func finish(session: RecordSession, context: ModelContext) {
        if activeSession === session {
            finish()
        } else {
            // 앱 종료 등으로 중단된 이전 세션도 명시적으로 종료할 수 있습니다.
            session.endedAt = .now
            save(context)
        }
    }

    func retrySave(context: ModelContext) {
        save(context)
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
            persistenceError = nil
        } catch {
            // 미저장 모델을 보존하고 다음 업데이트나 종료 시 저장을 다시 시도합니다.
            persistenceError = "기록을 저장할 수 없습니다: \(error.localizedDescription)"
        }
    }
}
