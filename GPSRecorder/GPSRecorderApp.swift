import SwiftUI
import SwiftData

// 앱의 시작점(entry point).
// @main: 이 타입에서 앱 실행이 시작된다는 표시입니다.
@main
struct GPSRecorderApp: App {
    // LocationService는 class(참조 타입)이므로, 앱 전체에서 "하나의 인스턴스"를 공유하려고
    // @State로 한 번만 만들고 아래에서 environment로 내려보냅니다.
    @State private var locationService: LocationService
    @State private var measurementService: MeasurementService
    private let container = Result { try Persistence.makeContainer() }

    init() {
        let locationService = LocationService()
        _locationService = State(initialValue: locationService)
        _measurementService = State(initialValue: MeasurementService(locationUpdates: locationService))
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let modelContainer):
                SessionListView()
                    // 하위의 모든 View가 @Environment(LocationService.self)로 꺼내 쓸 수 있게 주입
                    .environment(locationService)
                    .environment(measurementService)
                    .modelContainer(modelContainer)
            case .failure(let error):
                ContentUnavailableView(
                    "기록을 열 수 없습니다",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(error.localizedDescription)
                )
            }
        }
    }
}
