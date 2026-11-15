import Foundation
import CoreLocation
import Observation

// MARK: - 스냅샷(snapshot) 타입

// CLLocation을 그대로 들고 다니지 않고, 필요한 값만 복사한 struct로 바꿔 둡니다.
// 이유: 위치 콜백은 nonisolated(특정 actor에 묶이지 않은) 메서드에서 들어오는데,
//       거기서 MainActor로 값을 넘기려면 그 값이 Sendable(스레드 간 전달이 안전한 타입)이어야 합니다.
//       Double/Date만 담은 struct는 Sendable로 만들 수 있습니다.
// nonisolated: 프로젝트 기본 격리가 MainActor여도, 이 타입은 어느 스레드에서나 만들 수 있게 합니다.
nonisolated struct LocationSnapshot: Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double
    let ellipsoidalAltitude: Double
    let verticalAccuracy: Double
    let speed: Double
    let speedAccuracy: Double
    let course: Double
    let courseAccuracy: Double
    let floorLevel: Int?
    let isSimulatedBySoftware: Bool?
    let isProducedByAccessory: Bool?

    init(_ location: CLLocation) {
        timestamp = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.altitude
        ellipsoidalAltitude = location.ellipsoidalAltitude
        verticalAccuracy = location.verticalAccuracy
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        course = location.course
        courseAccuracy = location.courseAccuracy
        floorLevel = location.floor?.level
        isSimulatedBySoftware = location.sourceInformation?.isSimulatedBySoftware
        isProducedByAccessory = location.sourceInformation?.isProducedByAccessory
    }
}

nonisolated struct HeadingSnapshot: Sendable {
    let timestamp: Date
    let magneticHeading: Double
    let trueHeading: Double
    let headingAccuracy: Double

    init(_ heading: CLHeading) {
        timestamp = heading.timestamp
        magneticHeading = heading.magneticHeading
        trueHeading = heading.trueHeading
        headingAccuracy = heading.headingAccuracy
    }
}

// MARK: - 위치 서비스

// 나침반 앱이 보여주는 위경도·고도·방위는 모두 Core Location에서 나옵니다.
// 다른 앱(나침반 앱)의 데이터는 iOS 샌드박스 때문에 읽을 수 없으므로,
// 같은 출처인 CLLocationManager에서 직접 받아옵니다.
//
// @Observable: 이 class의 프로퍼티가 바뀌면, 그 프로퍼티를 읽은 SwiftUI View만 다시 그려집니다.
// NSObject 상속: CLLocationManagerDelegate가 Objective-C 프로토콜이라 NSObject가 필요합니다.
@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var accuracyAuthorization: CLAccuracyAuthorization
    private(set) var latestLocation: LocationSnapshot?
    private(set) var latestHeading: HeadingSnapshot?
    private(set) var lastErrorMessage: String?

    // @ObservationIgnored: 화면 갱신과 무관한 내부 객체라 변경 추적에서 제외
    @ObservationIgnored private let manager: CLLocationManager

    override init() {
        // super.init() 전에는 self의 프로퍼티를 읽을 수 없으므로 지역 상수로 먼저 만듭니다.
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.accuracyAuthorization = manager.accuracyAuthorization
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest   // 가장 높은 정확도 요청
        manager.distanceFilter = kCLDistanceFilterNone      // 조금만 움직여도 업데이트
        manager.headingFilter = kCLHeadingFilterNone        // 방위가 조금만 바뀌어도 업데이트
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        lastErrorMessage = nil
        if authorizationStatus == .notDetermined {
            requestPermission()
        }
        manager.startUpdatingLocation()
        // 나침반 센서(자력계)가 있는 기기에서만 방위 업데이트 시작
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}

// MARK: - CLLocationManagerDelegate

// delegate 메서드는 Objective-C 쪽에서 호출되므로 nonisolated로 선언합니다.
// 콜백 안에서는 Sendable 스냅샷만 만들고, 실제 프로퍼티 변경은 MainActor에서 합니다.
extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in
            self.authorizationStatus = status
            self.accuracyAuthorization = accuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 배열의 마지막이 가장 최신 위치입니다.
        guard let newest = locations.last else { return }
        let snapshot = LocationSnapshot(newest)
        Task { @MainActor in
            self.latestLocation = snapshot
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let snapshot = HeadingSnapshot(newHeading)
        Task { @MainActor in
            self.latestHeading = snapshot
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.lastErrorMessage = message
        }
    }
}
