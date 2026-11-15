import CoreMotion
import Foundation
import SwiftData
import Testing
@testable import GPSRecorder

@MainActor
private final class FakeAltitudeSource: RelativeAltitudeSource {
    var isAvailable = true
    var authorizationStatus: CMAuthorizationStatus = .authorized
    var handlers: [@MainActor (BarometerSample?, String?) -> Void] = []
    var stopCount = 0

    func start(receive: @escaping @MainActor (BarometerSample?, String?) -> Void) {
        handlers.append(receive)
    }

    func stop() { stopCount += 1 }

    func emit(_ sample: BarometerSample?, error: String? = nil, handlerIndex: Int? = nil) {
        let index = handlerIndex ?? (handlers.count - 1)
        handlers[index](sample, error)
    }
}

@MainActor
private final class FakeLocationUpdates: LocationUpdating {
    var startCount = 0
    var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@Suite(.serialized)
@MainActor
struct SurveyTests {
    private static var schema: Schema {
        Schema([RecordSession.self, LocationRecord.self, BarometerRecord.self, ArrivalRecord.self])
    }

    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: Self.schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    private func makeSession(context: ModelContext, title: String = "Library3F") -> RecordSession {
        let session = RecordSession(title: title, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(session)
        return session
    }

    private func sample(at index: Int = 0) -> BarometerSample {
        BarometerSample(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000.125 + Double(index)),
            sensorTimestamp: 1234.56789,
            pressureKPa: 101.23456789,
            relativeAltitudeM: -0.123456789
        )
    }

    @Test func savesEveryCallbackIncludingRepeatedSensorValuesAndTimestamps() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = makeSession(context: context)
        let source = FakeAltitudeSource()
        let locations = FakeLocationUpdates()
        let service = MeasurementService(locationUpdates: locations, altitudeSource: source)
        defer { service.finish() }
        service.start(session: session, context: context)
        service.start(session: session, context: context)
        #expect(source.handlers.count == 1)
        #expect(locations.startCount == 1)

        for index in 0..<300 { source.emit(sample(at: -index)) }
        #expect(try context.fetchCount(FetchDescriptor<BarometerRecord>()) == 300)
        #expect(session.barometerRecords.count == 300)
        #expect(service.barometerCount == 300)
        #expect(service.persistenceError == nil)
        let ordered = session.barometerRecords.sorted { $0.sequenceIndex < $1.sequenceIndex }
        #expect(ordered.map(\.sequenceIndex) == Array(0..<300))
        #expect(ordered.first?.recordedAt == sample().recordedAt)
        #expect(ordered.last?.recordedAt == sample(at: -299).recordedAt)
        #expect(ordered.allSatisfy { $0.sensorTimestamp == 1234.56789 && $0.pressureKPa == 101.23456789 })
        #expect(ordered.allSatisfy { $0.session === session })
        #expect(try context.fetchCount(FetchDescriptor<LocationRecord>()) == 0)
    }

    @Test func commonStopAndSessionSwitchRejectLateCallbacks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = makeSession(context: context)
        let source = FakeAltitudeSource()
        let locations = FakeLocationUpdates()
        let service = MeasurementService(locationUpdates: locations, altitudeSource: source)
        defer { service.finish() }
        service.start(session: first, context: context)
        source.emit(sample())
        service.finish()
        source.emit(sample(at: 1))
        service.recordArrival(floor: 5)
        #expect(first.barometerRecords.count == 1)
        #expect(first.arrivals.isEmpty)
        #expect(!first.isActive)
        #expect(locations.stopCount == 1)
        #expect(source.stopCount == 1)

        let second = makeSession(context: context, title: "Library4F")
        service.start(session: second, context: context)
        source.emit(sample(at: 2), handlerIndex: 0)
        source.emit(sample(at: 3), handlerIndex: 1)
        #expect(first.barometerRecords.count == 1)
        #expect(second.barometerRecords.count == 1)
        #expect(second.barometerRecords.first?.recordedAt == sample(at: 3).recordedAt)
        #expect(locations.startCount == 2)
    }

    @Test func unavailableAndDeniedMotionStillAllowLocationAndArrivalRecording() throws {
        for denied in [false, true] {
            let container = try makeContainer()
            let context = container.mainContext
            let session = makeSession(context: context)
            let source = FakeAltitudeSource()
            source.isAvailable = denied
            source.authorizationStatus = denied ? .denied : .authorized
            let locations = FakeLocationUpdates()
            let service = MeasurementService(locationUpdates: locations, altitudeSource: source)
            service.start(session: session, context: context)
            service.recordArrival(floor: 1, at: sample().recordedAt)
            #expect(source.handlers.isEmpty)
            #expect(locations.startCount == 1)
            #expect(service.motionPermissionDenied == denied)
            #expect(session.arrivals.count == 1)
            #expect(session.barometerRecords.isEmpty)
            service.finish()
            #expect(locations.stopCount == 1)
        }
    }

    @Test func undeterminedPermissionStartsTheSystemAuthorizationFlow() throws {
        let container = try makeContainer()
        let source = FakeAltitudeSource()
        source.authorizationStatus = .notDetermined
        let service = MeasurementService(locationUpdates: FakeLocationUpdates(), altitudeSource: source)
        defer { service.finish() }
        let session = makeSession(context: container.mainContext)
        service.start(session: session, context: container.mainContext)
        #expect(source.handlers.count == 1)
        source.authorizationStatus = .authorized
        source.emit(sample())
        #expect(session.barometerRecords.count == 1)
    }

    @Test func sensorErrorsAreVisibleAndDoNotFabricateSamplesOrStopLocation() throws {
        let container = try makeContainer()
        let source = FakeAltitudeSource()
        let locations = FakeLocationUpdates()
        let service = MeasurementService(locationUpdates: locations, altitudeSource: source)
        defer { service.finish() }
        let session = makeSession(context: container.mainContext)
        service.start(session: session, context: container.mainContext)
        source.emit(nil, error: "sensor disconnected")
        #expect(session.barometerRecords.isEmpty)
        #expect(service.barometerStatus.contains("sensor disconnected"))
        #expect(locations.stopCount == 0)
        #expect(source.stopCount == 1)
        source.emit(sample())
        #expect(session.barometerRecords.isEmpty)
    }

    @Test func exportsExactBarometerColumnsInCallbackOrderWithUTCAndEscaping() throws {
        let container = try makeContainer()
        let session = makeSession(context: container.mainContext, title: "Library, \"3F\"\n실험")
        let source = FakeAltitudeSource()
        let service = MeasurementService(locationUpdates: FakeLocationUpdates(), altitudeSource: source)
        defer { service.finish() }
        service.start(session: session, context: container.mainContext)
        source.emit(sample())
        source.emit(sample(at: -1))
        let expected = "\u{FEFF}recorded_at_utc,sensor_timestamp_s,pressure_kpa,relative_altitude_m,session_title\r\n"
            + "2023-11-14T22:13:20.125Z,1234.56789,101.23456789,-0.123456789,\"Library, \"\"3F\"\"\n실험\"\r\n"
            + "2023-11-14T22:13:19.125Z,1234.56789,101.23456789,-0.123456789,\"Library, \"\"3F\"\"\n실험\"\r\n"
        #expect(SurveyCSVExporter.barometerCSV(for: session) == expected)
        #expect(!SurveyCSVExporter.barometerCSV(for: session).contains("location_timestamp_utc"))
    }

    @Test func eachArrivalPressIsSavedSeparatelyWithTheSelectedFloorAndTime() throws {
        let container = try makeContainer()
        let session = makeSession(context: container.mainContext)
        let service = MeasurementService(locationUpdates: FakeLocationUpdates(), altitudeSource: FakeAltitudeSource())
        defer { service.finish() }
        service.start(session: session, context: container.mainContext)
        service.recordArrival(floor: 1, at: sample().recordedAt)
        service.recordArrival(floor: 5, at: sample(at: 60).recordedAt)
        service.recordArrival(floor: 5, at: sample(at: 61).recordedAt)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ArrivalRecord>()) == 3)
        let expected = "\u{FEFF}recorded_at_utc,floor_level,session_title\r\n"
            + "2023-11-14T22:13:20.125Z,1,Library3F\r\n"
            + "2023-11-14T22:14:20.125Z,5,Library3F\r\n"
            + "2023-11-14T22:14:21.125Z,5,Library3F\r\n"
        #expect(SurveyCSVExporter.arrivalCSV(for: session) == expected)
        #expect(session.barometerRecords.isEmpty)
    }

    @Test func exportsSeparateFilesWithoutOverwritingAnEarlierShare() throws {
        let container = try makeContainer()
        let session = makeSession(context: container.mainContext)
        let barometer = SurveyCSVExporter.barometerDocument(for: session)
        let arrivals = SurveyCSVExporter.arrivalDocument(for: session)
        #expect(barometer.fileName == "Library3F_baro.csv")
        #expect(arrivals.fileName == "Library3F_arrivals.csv")
        let first = try barometer.writeTemporaryFile()
        let second = try barometer.writeTemporaryFile()
        let third = try arrivals.writeTemporaryFile()
        #expect(first != second)
        #expect(first.lastPathComponent == "Library3F_baro.csv")
        #expect(third.lastPathComponent == "Library3F_arrivals.csv")
        #expect(try Data(contentsOf: first) == Data(barometer.text.utf8))
        session.title = "../Library/3F\n실험"
        let safeName = SurveyCSVExporter.barometerDocument(for: session).fileName
        #expect(!safeName.contains("/"))
        #expect(!safeName.contains("\n"))
    }

    @Test(.enabled(
        if: Bundle.main.url(forResource: "default", withExtension: "store", subdirectory: "SeedData") != nil,
        "로컬 초기 데이터가 있을 때만 원본 저장소 마이그레이션을 검증합니다."
    ))
    func migratedSeedRetainsAllOriginalLocationRecordsAndPersistsNewStreams() throws {
        let seedURL = try #require(Bundle.main.url(forResource: "default", withExtension: "store", subdirectory: "SeedData"))
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: seedURL, to: url)
        do {
            let container = try makeContainer(url: url)
            let context = container.mainContext
            let sessions = try context.fetch(FetchDescriptor<RecordSession>())
            #expect(sessions.count == 4)
            #expect(try context.fetchCount(FetchDescriptor<LocationRecord>()) == 3509)
            #expect(sessions.allSatisfy { $0.barometerRecords.isEmpty && $0.arrivals.isEmpty })
            let session = makeSession(context: context, title: "New survey")
            let source = FakeAltitudeSource()
            let service = MeasurementService(locationUpdates: FakeLocationUpdates(), altitudeSource: source)
            service.start(session: session, context: context)
            source.emit(sample())
            service.recordArrival(floor: 3, at: sample().recordedAt)
            service.finish()
        }
        let reopened = try makeContainer(url: url)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<RecordSession>()) == 5)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<LocationRecord>()) == 3509)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<BarometerRecord>()) == 1)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<ArrivalRecord>()) == 1)
        let record = try #require(reopened.mainContext.fetch(FetchDescriptor<BarometerRecord>()).first)
        #expect(record.session?.title == "New survey")
        #expect(record.recordedAt == sample().recordedAt)
        #expect(record.sensorTimestamp == sample().sensorTimestamp)
        #expect(record.pressureKPa == sample().pressureKPa)
        #expect(record.relativeAltitudeM == sample().relativeAltitudeM)
    }

    @Test func deletingASessionCascadesItsNewStreams() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = makeSession(context: context)
        let source = FakeAltitudeSource()
        let service = MeasurementService(locationUpdates: FakeLocationUpdates(), altitudeSource: source)
        service.start(session: session, context: context)
        source.emit(sample())
        service.recordArrival(floor: 3)
        service.finish()
        let other = makeSession(context: context, title: "Keep")
        context.delete(session)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<BarometerRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ArrivalRecord>()) == 0)
        #expect(try context.fetch(FetchDescriptor<RecordSession>()).first === other)
    }
}
