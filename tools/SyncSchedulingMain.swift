import Foundation

final class WatchShotDetector {}

@main
struct SyncSchedulingMain {
    @MainActor static func main() async throws {
        let scheduler = GolfSyncScheduler(delay: .milliseconds(10))
        var runs = 0
        var simultaneous = 0
        var peak = 0
        var cancelled = false
        let operation: @MainActor () async -> Void = {
            runs += 1
            simultaneous += 1
            peak = max(peak, simultaneous)
            defer { simultaneous -= 1 }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { cancelled = true }
        }
        scheduler.schedule(operation)
        while runs == 0 { try await Task.sleep(for: .milliseconds(1)) }
        // Auth refreshes and local edits arriving during a pull must not
        // cancel it, and should coalesce into just one subsequent pass.
        for _ in 0..<10 { scheduler.schedule(operation) }
        try await Task.sleep(for: .milliseconds(300))
        precondition(runs == 2 && peak == 1 && !cancelled)
        print("PASS rescheduling an active pull completes it and coalesces retries")

        let caller = Task { await scheduler.run(operation) }
        while runs < 3 { try await Task.sleep(for: .milliseconds(1)) }
        caller.cancel()
        await caller.value
        precondition(!cancelled && simultaneous == 0)
        print("PASS cancelling a UI caller does not cancel its sync")

        for _ in 0..<10 { scheduler.schedule(operation) }
        await scheduler.run(operation)
        try await Task.sleep(for: .milliseconds(50))
        precondition(runs == 4 && peak == 1 && !cancelled)
        print("PASS manual sync replaces the pending debounce without duplicate work")

        let busy = GolfSyncScheduler(delay: .milliseconds(30))
        var busyRuns = 0
        let quick: @MainActor () async -> Void = { busyRuns += 1 }
        for _ in 0..<20 {
            busy.schedule(quick)
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(busyRuns > 0)
        print("PASS continuous edits do not starve live uploads")
    }
}
