import SwiftUI
import SwiftData
import UIKit

// 묶음 1개의 화면: 측정 중이면 실시간 위치 + '기록' 버튼, 항상 기록 목록과 CSV 내보내기
struct SessionView: View {
    let session: RecordSession

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
                BarometerControls(session: session)
                ArrivalControls(session: session)
                SessionStopControls(session: session)
            }

            Section("추가 기록") {
                SurveyRecordSummary(session: session)
            }
            RecordingSaveStatus()

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
                ExportMenu(session: session)
            }
        }
        // 화면 이동으로 센서를 재시작하면 상대 고도 기준이 바뀌므로 종료 버튼에서만 멈춥니다.
    }
}

// MARK: - 실시간 위치 + 기록 버튼

struct MeasurementControls: View {
    let session: RecordSession
    @Environment(LocationService.self) private var locationService
    @Environment(MeasurementService.self) private var measurementService

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
        .disabled(locationService.latestLocation == nil || !measurementService.isRecording(session))
        // 기록 개수가 바뀔 때마다 진동 피드백
        .sensoryFeedback(.success, trigger: session.records.count)

    }

    private func record() {
        guard measurementService.isRecording(session), let location = locationService.latestLocation else { return }
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

// MARK: - 기압 자동 기록과 도착 표시

struct BarometerControls: View {
    let session: RecordSession
    @Environment(MeasurementService.self) private var measurementService

    var body: some View {
        Section {
            if measurementService.isRecording(session) {
                Text(measurementService.barometerStatus)
                if let sample = measurementService.latestBarometerSample {
                    LabeledContent("기압", value: "\(sample.pressureKPa.fixed(5)) kPa")
                    LabeledContent("상대 고도", value: "\(sample.relativeAltitudeM.fixed(3)) m")
                }
                LabeledContent("기압 기록", value: "\(measurementService.barometerCount)개")
                if measurementService.motionPermissionDenied {
                    Link("설정에서 동작 및 피트니스 권한 켜기", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            } else {
                Text("중단된 측정입니다. 이 세션을 종료하고 새 측정을 시작하세요.")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("기압 자동 기록")
        } footer: {
            Text("기압은 업데이트마다 자동 저장됩니다. 상대 고도는 이번 측정의 첫 기압 업데이트가 기준이며, 세션 간 비교에는 기압을 사용하세요.")
        }
    }
}

struct ArrivalControls: View {
    let session: RecordSession
    @Environment(MeasurementService.self) private var measurementService
    @State private var arrivalFloor = 1

    var body: some View {
        Section {
            Stepper("도착 층: \(arrivalFloor)층", value: $arrivalFloor, in: -10...100)
            Button {
                measurementService.recordArrival(floor: arrivalFloor)
            } label: {
                Label("\(arrivalFloor)층 도착", systemImage: "flag.fill")
            }
            .disabled(!measurementService.isRecording(session))
            .sensoryFeedback(.success, trigger: session.arrivals.count)
            ForEach(session.arrivals.sorted { $0.sequenceIndex > $1.sequenceIndex }.prefix(5)) { marker in
                LabeledContent("\(marker.floorLevel)층 도착", value: marker.recordedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption)
            }
        } header: {
            Text("층 도착 표시")
        } footer: {
            Text("층을 선택하고 도착할 때 누르세요. 누를 때마다 시각과 층을 별도 도착 CSV에 기록합니다.")
        }
    }
}

struct SessionStopControls: View {
    let session: RecordSession
    @Environment(\.modelContext) private var modelContext
    @Environment(MeasurementService.self) private var measurementService

    var body: some View {
        Section {
            Button("측정 종료", role: .destructive) {
                measurementService.finish(session: session, context: modelContext)
            }
        } footer: {
            Text("위치와 기압을 함께 종료합니다. 연속 측정 중에는 앱을 켜두세요. 측정 중 자동 화면 잠금은 꺼집니다.")
        }
    }
}

struct RecordingSaveStatus: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MeasurementService.self) private var measurementService

    var body: some View {
        if let error = measurementService.persistenceError {
            Section("저장 상태") {
                Text(error).foregroundStyle(.red)
                Button("저장 다시 시도") {
                    measurementService.retrySave(context: modelContext)
                }
            }
        }
    }
}

struct SurveyRecordSummary: View {
    let session: RecordSession

    var body: some View {
        LabeledContent("기압 기록", value: "\(session.barometerRecords.count)개")
        LabeledContent("도착 표시", value: "\(session.arrivals.count)개")
    }
}

// MARK: - CSV를 선택할 때만 생성하고 각각 별도 파일로 공유

private struct SharedCSVFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExportMenu: View {
    let session: RecordSession
    @State private var sharedFile: SharedCSVFile?
    @State private var exportError: String?

    var body: some View {
        Menu {
            Button("위치 CSV", systemImage: "location") {
                share(CSVExporter.document(for: session))
            }
            .disabled(session.records.isEmpty)
            Button("기압 CSV", systemImage: "barometer") {
                share(SurveyCSVExporter.barometerDocument(for: session))
            }
            .disabled(session.barometerRecords.isEmpty)
            Button("도착 CSV", systemImage: "flag") {
                share(SurveyCSVExporter.arrivalDocument(for: session))
            }
            .disabled(session.arrivals.isEmpty)
        } label: {
            Label("CSV 내보내기", systemImage: "square.and.arrow.up")
        }
        .sheet(item: $sharedFile) { file in
            CSVShareSheet(url: file.url)
        }
        .alert("CSV를 내보낼 수 없습니다", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func share(_ document: CSVDocument) {
        do {
            sharedFile = SharedCSVFile(url: try document.writeTemporaryFile())
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct CSVShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 숫자 표시 도우미

extension Double {
    // 소수점 아래 digits자리로 고정, 천 단위 쉼표 없이 표시
    func fixed(_ digits: Int) -> String {
        formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }
}
