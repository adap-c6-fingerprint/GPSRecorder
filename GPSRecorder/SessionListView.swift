import SwiftUI
import SwiftData

// 첫 화면: 기록 묶음 목록
struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext

    // @Query: SwiftData에서 데이터를 읽어오고, 데이터가 바뀌면 화면을 자동 갱신
    @Query(sort: \RecordSession.startedAt, order: .reverse)
    private var sessions: [RecordSession]

    // NavigationStack의 경로. 여기에 묶음을 append하면 그 묶음 화면으로 이동합니다.
    @State private var path: [RecordSession] = []
    @State private var showStarredOnly = false

    private var visibleSessions: [RecordSession] {
        showStarredOnly ? sessions.filter(\.isStarred) : sessions
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(visibleSessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                    // 행을 오른쪽으로 밀면 중요 표시 토글
                    .swipeActions(edge: .leading) {
                        Button {
                            session.isStarred.toggle()
                        } label: {
                            Label(session.isStarred ? "중요 해제" : "중요",
                                  systemImage: session.isStarred ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
                .onDelete(perform: deleteSessions)
            }
            .overlay {
                if visibleSessions.isEmpty {
                    ContentUnavailableView(
                        showStarredOnly ? "중요 표시한 묶음이 없습니다" : "기록 묶음이 없습니다",
                        systemImage: "mappin.slash",
                        description: Text("오른쪽 위 + 버튼으로 새 측정을 시작하세요.")
                    )
                }
            }
            .navigationTitle("기록 묶음")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showStarredOnly.toggle()
                    } label: {
                        Image(systemName: showStarredOnly ? "star.fill" : "star")
                    }
                    .accessibilityLabel("중요 묶음만 보기")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("새 측정", systemImage: "plus", action: startNewSession)
                }
            }
            .navigationDestination(for: RecordSession.self) { session in
                SessionView(session: session)
            }
        }
    }

    private func startNewSession() {
        // 측정은 한 번에 하나만: 진행 중인 묶음이 있으면 먼저 종료
        for session in sessions where session.isActive {
            session.endedAt = .now
        }
        let title = "측정 " + Date.now.formatted(date: .abbreviated, time: .shortened)
        let newSession = RecordSession(title: title)
        modelContext.insert(newSession)   // 저장소에 추가
        path.append(newSession)           // 바로 측정 화면으로 이동
    }

    private func deleteSessions(at offsets: IndexSet) {
        // offsets는 화면에 보이는 배열(visibleSessions) 기준의 위치입니다.
        let targets = offsets.map { visibleSessions[$0] }
        for session in targets {
            modelContext.delete(session)  // cascade 규칙으로 안의 기록도 함께 삭제
        }
    }
}

struct SessionRow: View {
    let session: RecordSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.isStarred ? "star.fill" : "star")
                .foregroundStyle(session.isStarred ? Color.yellow : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headline)
                Text("기록 \(session.records.count)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.isActive {
                Text("측정 중")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green, in: Capsule())
            }
        }
    }
}
