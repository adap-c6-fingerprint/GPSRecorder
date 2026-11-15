import Foundation
import SwiftData

// 전달받은 저장소는 첫 실행에만 복사합니다. 이후에는 기기에 저장된 기록을 계속 사용합니다.
enum Persistence {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([RecordSession.self, LocationRecord.self])
        let configuration = ModelConfiguration(schema: schema)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: configuration.url.path) {
            try fileManager.createDirectory(
                at: configuration.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // 실제 측정 데이터는 로컬 전용입니다. 없으면 빈 저장소로 실행합니다.
            if let seedURL = Bundle.main.url(
                forResource: "default", withExtension: "store", subdirectory: "SeedData"
            ) {
                try fileManager.copyItem(at: seedURL, to: configuration.url)
            }
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
