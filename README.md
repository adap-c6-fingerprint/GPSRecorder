# GPSRecorder

SwiftUI, SwiftData, Core Location과 Core Motion을 사용하는 iOS 측량 앱입니다. 위치 기록, 기압 자동 기록, 층 도착 표시를 지원합니다.

## 실행

1. `GPSRecorder.xcodeproj`를 Xcode에서 엽니다.
2. `GPSRecorder` 스킴과 실행할 iPhone을 선택합니다. 시뮬레이터에서는 화면과 데이터 처리를 확인할 수 있지만 기압 측정은 지원하지 않습니다.
3. Run (`⌘R`)으로 실행합니다.
4. 실기기에서는 타깃의 **Signing & Capabilities → Team**을 본인 팀으로 선택하고, 필요하면 Bundle Identifier를 고유한 값으로 변경합니다.

Swift 6 언어 모드와 기본 MainActor 격리를 사용합니다. 원본의 `nonisolated struct` 구문 때문에 Xcode 26 이상(Swift 6.2 이상)이 필요합니다. 앱의 최소 지원 버전은 iOS 17.0이며, 외부 패키지 의존성은 없습니다.

## 로컬 측정 데이터

**실제 위치 기록과 원본 데이터베이스는 공개 저장소에 포함하지 않습니다.** 초기 데이터 없이도 빈 SwiftData 저장소로 실행되며, 이미 설치된 앱의 데이터는 유지합니다.

- `ReceivedData/`는 별도로 전달받은 원본 저장소를 로컬에 보관하는 경로입니다. [데이터 보관 안내](ReceivedData/README.md)를 참고하세요.
- 필요하면 SQLite 백업 API로 통합한 `default.store`를 `GPSRecorder/Resources/SeedData/`에 로컬로 추가할 수 있습니다. 앱 저장소가 없는 첫 실행에만 복사합니다.
- `default.store`, `default.store-shm`, `default.store-wal` 및 CSV 파일은 `.gitignore`로 제외합니다.
- Downloads에 전달받았던 원본 파일과 로컬 초기 데이터는 보존했습니다.

## 구성

```text
GPSRecorder/
├── GPSRecorder.xcodeproj/       # Xcode 프로젝트와 공유 스킴
├── Configuration/Info.plist    # 위치·동작 및 피트니스 권한 안내
├── GPSRecorder/
│   ├── GPSRecorderApp.swift    # 앱 진입점
│   ├── Persistence.swift       # 첫 실행 데이터 복사와 SwiftData 구성
│   ├── Models.swift
│   ├── LocationService.swift
│   ├── MeasurementService.swift # 위치·기압 공통 시작/종료 및 기압 콜백 저장
│   ├── SurveyRecords.swift     # 기압·도착 데이터 모델
│   ├── SessionListView.swift
│   ├── SessionView.swift
│   ├── CSVExporter.swift
│   ├── SurveyCSVExporter.swift # 기압·도착 CSV
│   └── Resources/
│       ├── Assets.xcassets/
│       └── SeedData/           # 선택적인 로컬 초기 데이터 (Git 제외)
├── GPSRecorderTests/           # 콜백·CSV·데이터 마이그레이션 테스트
└── ReceivedData/README.md      # 로컬 측정 데이터 안내
```

기존 위치 기록 모델의 필드, 위치 CSV의 모든 열과 값 생성 로직, `LocationService.swift`는 유지했습니다. 위치 기록은 원래처럼 **기록** 버튼을 누를 때 저장합니다. 위치 CSV에는 `floor_level`, `location_timestamp_utc` 등 기존 열이 그대로 포함됩니다.

## 기압과 도착 기록 사용법

1. 목록의 **+ → 세션 이름 → 측정 시작**으로 시작합니다. 예를 들어 `Library3F`를 입력합니다.
2. 위치와 기압 측정을 함께 시작합니다. 처음 표시되는 위치 및 동작·피트니스 권한 요청을 허용합니다. 기압은 별도 기록 버튼 없이 업데이트가 올 때마다 저장됩니다.
3. 층에 도착하면 **도착 층**을 선택하고 **N층 도착** 버튼을 누릅니다. 누를 때마다 UTC 시각과 선택한 층이 별도 기록됩니다. 위치 권한이나 기압 센서가 없어도 도착 표시는 사용할 수 있습니다.
4. **측정 종료**를 누르면 위치와 기압을 함께 멈추고 저장합니다. **새 측정**을 시작해도 이전 세션은 함께 종료됩니다.
5. 오른쪽 위 **CSV 내보내기**에서 **위치 CSV**, **기압 CSV**, **도착 CSV**를 각각 공유하거나 파일에 저장합니다. 해당 기록이 없는 CSV 항목은 비활성화됩니다.

`NSMotionUsageDescription`과 `CMAltimeter.isRelativeAltitudeAvailable()` 확인을 추가했습니다. 미지원 기기, 권한 거부, 센서 오류는 화면에 표시하며, 가짜 기압 데이터는 만들지 않습니다. 저장 실패 시 오류를 표시하고 **저장 다시 시도**를 제공합니다.

센서 기준이 바뀌지 않도록 목록으로 돌아갔다가 측정 화면을 다시 열어도 센서를 재시작하지 않습니다. 연속 측정 중에는 **앱을 전면에 켜둔 상태**로 사용합니다. 측정 중 자동 화면 잠금을 끄고, 종료 시 다시 켭니다. 백그라운드 수집은 구현하지 않았습니다. 앱 강제 종료 등으로 중단된 세션은 재개하지 않고 종료한 뒤 새 세션을 시작합니다.

## CSV 형식

위치 CSV는 기존 `GPS_<시작시각>.csv` 형식을 유지합니다. `Library3F` 세션의 추가 파일은 다음과 같습니다.

| 파일 | 열 순서 |
| --- | --- |
| `Library3F_baro.csv` | `recorded_at_utc,sensor_timestamp_s,pressure_kpa,relative_altitude_m,session_title` |
| `Library3F_arrivals.csv` | `recorded_at_utc,floor_level,session_title` |

기압은 콜백 데이터 한 건당 CSV 한 행입니다. 간격 제한, 평균화, 값/타임스탬프 중복 제거를 하지 않으며, 수신 순서를 보존합니다. UTC 시각은 콜백을 받은 즉시 캡처하고 기존 위치 CSV와 같은 소수 초 포함 ISO-8601 형식으로 출력합니다. 센서 타임스탬프는 변환하지 않고 원본 초 값을 기록합니다. 모든 CSV는 UTF-8 BOM과 CRLF 줄바꿈을 사용하고 쉼표·따옴표·줄바꿈을 이스케이프합니다.

측정 중 데이터는 SwiftData에 자동 저장하며 기압 콜백마다 디스크 저장을 시도합니다. CSV는 내보내기를 선택할 때 각각 별도 파일로 생성합니다. 같은 이름을 다시 공유해도 기존 임시 공유 파일을 덮어쓰지 않습니다. 파일명에 사용할 수 없는 세션 이름 문자는 `_`로 바꾸지만, CSV의 `session_title` 값은 위치 CSV와 동일한 원래 이름을 유지합니다.

Apple은 `relativeAltitude`를 **첫 이벤트 대비 상대 변화량(m)**으로 정의하며 첫 값은 0이라고 명시합니다. 따라서 새 세션마다 새 `CMAltimeter`로 업데이트를 시작하고, 세션 사이의 비교에는 `pressure`를 사용합니다. 센서 `timestamp`는 기기 부팅 후 초이고 `pressure`의 단위는 kPa입니다. [상대 고도 문서](https://developer.apple.com/documentation/coremotion/cmaltitudedata/relativealtitude), [센서 시각 문서](https://developer.apple.com/documentation/coremotion/cmlogitem/timestamp), [기압 단위 문서](https://developer.apple.com/documentation/coremotion/cmaltitudedata), [지원 여부·권한 문서](https://developer.apple.com/documentation/coremotion/cmaltimeter).

## 요청받은 측정 절차

**A. 층별 데이터(문턱값 계산용)**

- 1층부터 5층까지 층마다 세션을 하나씩 만듭니다. 예: `Library1F` … `Library5F`.
- 해당 층 안에서만 3분 이상 돌아다닙니다.
- 출입문, 계단실 문, 엘리베이터 앞을 지나는 구간을 포함한 뒤 측정을 종료합니다.

**B. 연속 데이터(검증용)**

- 새 세션 하나를 시작하고 전체 경로를 마칠 때까지 종료하지 않습니다.
- 계단으로 1층 → 5층을 올라가며 각 층에서 60초 머뭅니다. 각 층에 도착할 때 층을 선택하고 **도착**을 누릅니다.
- 같은 방식으로 5층 → 1층을 내려옵니다.
- 엘리베이터로 1층 → 5층, 5층 → 1층을 각각 한 번 이동하고 도착을 표시합니다.
- 전체 측정을 종료하고 위치·기압·도착 CSV를 각각 내보냅니다.

시뮬레이터의 위치는 Xcode의 위치 시뮬레이션으로 확인할 수 있습니다. 실제 GPS 정확도와 나침반 센서 동작은 iPhone에서 확인해야 합니다.

## 확인한 내용

2026-11-14, Xcode 27.2 / Swift 6 모드에서 최종 Debug 빌드와 자동 테스트 **10개**를 통과했습니다. 다음을 검증했습니다.

- 같은 값·센서 시각의 연속 콜백 300건을 모두 저장하고 수신 순서를 유지합니다.
- 중복 시작으로 센서를 재시작하지 않으며 공통 종료, 세션 변경 후 늦게 온 콜백이 다른 세션에 섞이지 않습니다.
- 미지원 기기·권한 거부 시 위치 측정과 도착 표시가 유지됩니다. 센서 오류 시 가짜 기록을 만들지 않습니다.
- 기압·도착 CSV의 열, UTC 시각, 숫자 정밀도, 이스케이프와 별도 파일 생성·동일 이름 공유를 검증했습니다.
- 원본 초기 데이터의 측정 묶음 4개·위치 기록 3,509개를 보존하며 새 기압·도착 기록을 저장하고 저장소를 다시 열 수 있습니다. 세션 삭제 시 새 기록의 cascade 삭제도 검증했습니다.

iPhone 18 Pro / iOS 27.2 시뮬레이터에 최신 앱을 설치·실행해 목록을 확인했습니다. 실행 중 저장소의 기존 위치 기록 3,509개와 관계, 새 테이블, SQLite 무결성도 확인했습니다. 원본 파일 및 위치 CSV 생성 로직은 변경하지 않았습니다. 기기 허브의 자동 화면 조작 연결이 실패해 새 측정 화면과 iOS 공유시트의 직접 조작은 확인하지 못했습니다.

Xcode의 **Product → Test (`⌘U`)**로 테스트를 다시 실행할 수 있습니다. 센서 테스트는 주입된 테스트 입력으로 수행하며, 앱 자체는 실제 Core Motion 데이터만 수집합니다. 원본 초기 데이터 마이그레이션 테스트 1개는 로컬 `SeedData/default.store`가 있을 때만 실행되고, 공개 저장소에서는 건너뜁니다. 나머지 테스트는 실제 위치 기록 없이 실행됩니다.

실기기 서명·설치, 동작 및 피트니스 권한 프롬프트, 실제 센서 측정과 A/B 현장 측정은 수행하지 않았습니다. 지원 iPhone에서 위 절차로 확인해야 합니다.

2026-11-16 공개 저장소 등록 시, 측정 데이터를 제외한 최초 프로젝트의 빌드와 최종 버전 테스트를 다시 확인했습니다. 데이터 없이 실행 가능한 테스트 9개가 통과했고, 로컬 원본 데이터가 필요한 마이그레이션 테스트 1개는 건너뛰었습니다. 실패는 없습니다.
