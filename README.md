# GPSRecorder

SwiftUI, SwiftData, Core Location을 사용하는 iOS 위치 측정 앱입니다. 전달받은 Swift 파일을 Xcode에서 바로 열 수 있는 프로젝트로 구성했습니다.

## 실행

1. `GPSRecorder.xcodeproj`를 Xcode에서 엽니다.
2. `GPSRecorder` 스킴과 실행할 iPhone 또는 시뮬레이터를 선택합니다.
3. Run (`⌘R`)으로 실행합니다.
4. 실기기에서는 **Signing & Capabilities → Team**을 본인 팀으로 선택하고 필요하면 Bundle Identifier를 변경합니다.

Swift 6 언어 모드와 기본 MainActor 격리를 사용합니다. 원본의 `nonisolated struct` 구문 때문에 Xcode 26 이상(Swift 6.2 이상)이 필요합니다. 최소 지원 버전은 iOS 17.0이며 외부 패키지는 사용하지 않습니다.

## 사용법

- **+** 버튼으로 측정 세션을 만들고 위치 권한을 허용합니다.
- **기록** 버튼을 누를 때마다 현재 위치와 센서 정보를 저장합니다.
- **측정 종료**로 세션을 끝내고 공유 버튼으로 위치 CSV를 내보냅니다.
- 중요 표시와 기록 묶음 삭제를 지원합니다.

CSV에는 UTC 기록 시각, 위치 계산 시각, 위도·경도, 고도·오차, 속력·방향, 층, 나침반 정보와 세션 이름이 포함됩니다. UTF-8 BOM과 CRLF 줄바꿈을 사용합니다.

## 로컬 측정 데이터

**실제 위치 기록과 원본 데이터베이스는 공개 저장소에 포함하지 않습니다.** 앱은 초기 데이터 없이도 빈 SwiftData 저장소로 실행됩니다. 기존에 설치된 앱의 데이터는 유지합니다.

필요한 경우 SQLite 백업 API로 통합한 `default.store`를 `GPSRecorder/Resources/SeedData/`에 로컬로 추가하면 첫 실행의 초기 데이터로 사용할 수 있습니다. 원본 저장소를 보관하는 방법은 [ReceivedData 안내](ReceivedData/README.md)를 참고하세요. 저장소 파일과 CSV는 `.gitignore`로 제외됩니다.

## 구성

- `GPSRecorder/`: 앱 진입점, 모델, 위치 서비스, 화면, CSV 생성 및 저장소 구성
- `Configuration/Info.plist`: 위치 사용 권한 안내 및 앱 설정
- `GPSRecorder/Resources/SeedData/`: 선택적인 로컬 초기 데이터 경로
- `ReceivedData/README.md`: 공개 저장소에서 제외되는 측정 데이터 안내

기존 위치 기록 필드와 CSV 생성 로직을 유지했습니다. 실제 GPS 정확도와 나침반 동작은 iPhone에서 확인해야 합니다.
