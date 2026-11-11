import XCTest
import SwiftData
@testable import ClipboardManager

// Opt-in storage benchmark (skipped by default): 1000 entries, 300 of them
// 2 MB images. Reports store size, launch fetch time, per-keystroke filter
// time, and memory. Run with: BENCH=1 swift test -c release --filter StoreBenchmarkTests
@MainActor
final class StoreBenchmarkTests: XCTestCase {
    func testBenchmark() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BENCH"] == "1")
        let url = FileManager.default.temporaryDirectory.appending(path: "bench-\(UUID().uuidString).sqlite")
        defer {
            for path in [url.path, url.path + "-wal", url.path + "-shm"] {
                try? FileManager.default.removeItem(atPath: path)
            }
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appending(path: ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT"))
        }
        do {
            let store = ClipboardStore(modelContainer: try ModelContainer(for: ClipboardEntry.self, configurations: ModelConfiguration(url: url)))
            for i in 0..<1000 {
                if i % 10 < 3 {
                    var bytes = Data(count: 2_000_000)
                    bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }
                    store.add(.image(bytes))
                } else {
                    store.add(.text("entry \(i) some copied text https://example.com/\(i)"))
                }
            }
        }
        let dir = url.deletingLastPathComponent()
        let size = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.lastPathComponent.hasPrefix(url.lastPathComponent) || $0.path.contains(".\(url.deletingPathExtension().lastPathComponent)_SUPPORT") }
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let supportDir = dir.appending(path: ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT")
        let external = (FileManager.default.enumerator(at: supportDir, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

        let mem0 = footprint()
        let t0 = Date()
        let store = ClipboardStore(modelContainer: try ModelContainer(for: ClipboardEntry.self, configurations: ModelConfiguration(url: url)))
        _ = store.entries.count
        let load = Date().timeIntervalSince(t0)
        let t1 = Date()
        for q in ["e", "en", "ent", "entr", "entry", "entry 9", "entry 99"] {
            _ = HistoryFilter.apply(entries: store.entries, query: q, kind: .all)
            _ = HistoryFilter.apply(entries: store.entries, query: q, kind: .links)
        }
        let filter = Date().timeIntervalSince(t1) / 7
        let mem1 = footprint()
        print(String(format: "BENCH sqlite+wal=%.0fMB external=%.0fMB load=%.3fs filterPerKeystroke=%.3fs memDelta=%.0fMB entries=%d",
                     Double(size) / 1e6, Double(external) / 1e6, load, filter, Double(mem1 - mem0) / 1e6, store.entries.count))
    }

    private func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return Int(info.phys_footprint)
    }
}
