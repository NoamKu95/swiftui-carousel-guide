import Combine
import Foundation

/// Owns the auto-advance timer and pause/resume semantics for carousel demos.
@MainActor
final class AutoScrollController: ObservableObject {
    @Published private(set) var tick: UInt64 = 0
    @Published private(set) var isPausedByUserInteraction = false

    private var timer: AnyCancellable?
    private var resumeWorkItem: DispatchWorkItem?
    private var interval: TimeInterval = 3
    private var isEnabled = false

    func configure(enabled: Bool, interval: TimeInterval) {
        self.interval = max(interval, 0.8)
        self.isEnabled = enabled
        rebuildTimer()
    }

    func pauseForUserInteraction(resumeAfter: TimeInterval = 2.4) {
        guard isEnabled else { return }
        isPausedByUserInteraction = true
        resumeWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isPausedByUserInteraction = false
            self.rebuildTimer()
        }
        resumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + resumeAfter, execute: work)
        rebuildTimer()
    }

    func stop() {
        isEnabled = false
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        isPausedByUserInteraction = false
        timer?.cancel()
        timer = nil
    }

    private func rebuildTimer() {
        timer?.cancel()
        timer = nil

        guard isEnabled, !isPausedByUserInteraction else { return }

        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick &+= 1
            }
    }
}
