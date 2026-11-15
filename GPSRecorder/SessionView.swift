import SwiftUI
import SwiftData
import UIKit

// 묶음 1개의 화면: 측정 중이면 실시간 위치 + '기록' 버튼, 항상 기록 목록과 CSV 내보내기
struct SessionView: View {
    let session: RecordSession
    @Environment(LocationService.self) private var locationService

    var body: some View {
        // 이 body는 locationService의 값을 직접 읽지 않습니다.
        // → 위치가 1초마다 바뀌어도 이 View(와 긴 기록 목록)는 다시 그려지지 않고,
        //   위치를 읽는 MeasurementControls만 다시 그려집니다.
        let records = session.sortedRecords

        List {
            if session.isActive {
                Section("측정 중") {
                    MeasurementControls(session: session)
                }
            }

            Section {
                // 최신 기록이 위에 오도록 뒤집되, 번호는 기록 순서대로 유지
                ForEach(Array(records.enumerated()).reversed(), id: \.element.id) { index, record in
                    RecordRow(number: index + 1, record: record)
                }
            } header: {
                Text("기록 \(records.count)개")
            } footer: {
                if records.isEmpty {
                    Text("'기록' 버튼을 누를 때마다 현재 위치가 저장됩니다.")
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.isStarred.toggle()
                } label: {
                    Image(systemName: session.isStarred ? "star.fill" : "star")
                        .foregroundStyle(session.isStarred ? Color.yellow : Color.accentColor)
                }
                .accessibilityLabel(session.isStarred ? "중요 해제" : "중요 표시")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ExportButton(session: session)
            }
        }
        .onAppear {
            if session.isActive { locationService.start() }
        }
        .onDisappear {
            locationService.stop()   // 화면을 떠나면 배터리 절약을 위해 위치 업데이트 중지
        }
    }
}

// MARK: - 실시간 위치 + 기록 버튼

struct MeasurementControls: View {
    let session: RecordSession
    @Environment(LocationService.self) private var locationService

    var body: some View {
        switch locationService.authorizationStatus {
        case .notDetermined:
            Button("위치 권한 요청") { locationService.requestPermission() }
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Text("위치 권한이 없어 기록할 수 없습니다.")
                Link("설정에서 권한 켜기", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        default:
            authorizedContent
        }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        if locationService.accuracyAuthorization == .reducedAccuracy {
            Label("'정확한 위치'가 꺼져 있어 대략적인 위치만 기록됩니다.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }

        if let location = locationService.latestLocation {
            LabeledContent("위도", value: location.latitude.fixed(7))
            LabeledContent("경도", value: location.longitude.fixed(7))
            LabeledContent("수평 오차", value: "±\(location.horizontalAccuracy.fixed(1)) m")
            LabeledContent("고도", value: "\(location.altitude.fixed(1)) m")
            if let heading = locationService.latestHeading {
                LabeledContent("방위 (자북)", value: "\(heading.magneticHeading.fixed(0))°")
            }
            LabeledContent("위치 시각",
                           value: location.timestamp.formatted(date: .omitted, time: .standard))
        } else {
            HStack {
                ProgressView()
                Text("위치를 찾는 중…")
            }
        }

        if let message = locationService.lastErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        Button(action: record) {
            Label("기록", systemImage: "mappin.and.ellipse")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(locationService.latestLocation == nil)
        // 기록 개수가 바뀔 때마다 진동 피드백
        .sensoryFeedback(.success, trigger: session.records.count)

        Button("측정 종료", role: .destructive) {
            session.endedAt = .now
            locationService.stop()
        }
    }

    private func record() {
        guard let location = locationService.latestLocation else { return }
        let newRecord = LocationRecord(
            recordedAt: .now,
            location: location,
            heading: locationService.latestHeading
        )
        // 이미 저장소에 있는 session의 relationship에 추가하면 newRecord도 자동으로 저장됩니다.
        session.records.append(newRecord)
    }
}

// MARK: - 기록 1건 표시

struct RecordRow: View {
    let number: Int
    let record: LocationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(number)")
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(record.recordedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(record.latitude.fixed(7)), \(record.longitude.fixed(7))")
                .font(.subheadline.monospaced())
            Text("수평 오차 ±\(record.horizontalAccuracy.fixed(1)) m · 고도 \(record.altitude.fixed(1)) m")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - CSV 내보내기 버튼

// 별도 View로 분리한 이유: 이 View는 session의 기록만 읽으므로,
// 위치가 바뀔 때마다 CSV를 다시 만들지 않고 "기록이 바뀔 때만" 다시 만듭니다.
struct ExportButton: View {
    let session: RecordSession

    var body: some View {
        let document = CSVExporter.document(for: session)
        ShareLink(item: document, preview: SharePreview(document.fileName)) {
            Label("CSV 내보내기", systemImage: "square.and.arrow.up")
        }
        .disabled(session.records.isEmpty)
    }
}

// MARK: - 숫자 표시 도우미

extension Double {
    // 소수점 아래 digits자리로 고정, 천 단위 쉼표 없이 표시
    func fixed(_ digits: Int) -> String {
        formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }
}
