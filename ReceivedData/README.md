# 로컬 측정 데이터

실제 위치 좌표가 포함된 `default.store`, `default.store-shm`, `default.store-wal`은 공개 저장소에 포함하지 않습니다.

별도로 전달받은 원본을 보관하려면 이 폴더를 사용할 수 있습니다. 세 파일은 같은 시점의 묶음으로 취급해야 하며, WAL을 누락하면 최신 기록이 빠질 수 있습니다. 앱은 이 폴더를 직접 읽지 않습니다.

필요한 경우 세 파일을 SQLite 백업 API로 통합한 `default.store`를 `GPSRecorder/Resources/SeedData/`에 로컬로 추가하면 새 설치의 초기 데이터로 사용할 수 있습니다. 데이터가 없으면 빈 저장소로 시작하며, 이미 설치된 앱의 저장소는 유지합니다. 저장소 파일과 CSV 기록은 `.gitignore`로 제외됩니다.
