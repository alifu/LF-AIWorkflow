//
//  ResearchViewModelTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
struct ResearchViewModelTests {
    private func task(_ state: ResearchState, id: UUID = UUID()) -> ResearchTask {
        ResearchTask(id: id, question: "Which is faster?", output: .comparison, deep: false, state: state)
    }

    private func statuses(_ row: ResearchRowModel) -> [StageChip.Status] { row.chips.map(\.status) }

    private func makeModel(clock: any Clock<Duration> = ManualClock()) -> ResearchViewModel {
        ResearchViewModel(updates: AsyncStream<ResearchTask>.makeStream().stream, clock: clock,
                          now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    @Test func stepsHaveDistinctIconsLabelsAndReuseExistingColorRoles() {
        let steps = ResearchStep.allCases
        #expect(steps == [.capture, .clean, .extract, .analyze, .report])
        #expect(Set(steps.map(\.icon)).count == steps.count)
        #expect(Set(steps.map(\.label)).count == steps.count)
        #expect(steps.map(\.colorRole) == [.plan, .test, .fix, .code, .review])
    }

    @Test func chipsFollowTheStateCursor() {
        let model = makeModel()
        model.receive(task(.capture))
        #expect(statuses(model.rows[0]) == [.active, .pending, .pending, .pending, .pending])
    }

    @Test func queuedShowsAllPending() {
        let model = makeModel()
        model.receive(task(.queued))
        #expect(statuses(model.rows[0]) == Array(repeating: .pending, count: 5))
    }

    @Test func doneShowsAllDone() {
        let model = makeModel()
        model.receive(task(.done))
        #expect(statuses(model.rows[0]) == Array(repeating: .done, count: 5))
    }

    @Test func skippedExtractShowsAsDoneWithSkippedDetail() {
        let model = makeModel()
        let id = UUID()
        for state: ResearchState in [.awaitingPreview, .analyze] { model.receive(task(state, id: id)) }
        model.flush()
        let extract = model.rows[0].chips[2]
        #expect(extract.status == .done)
        #expect(extract.label.contains("skipped"))
        #expect(model.rows[0].chips[3].status == .active)
    }

    @Test func ranExtractIsNotMarkedSkipped() {
        let model = makeModel()
        let id = UUID()
        for state: ResearchState in [.awaitingPreview, .extract, .analyze] { model.receive(task(state, id: id)) }
        model.flush()
        #expect(!model.rows[0].chips[2].label.contains("skipped"))
        #expect(model.rows[0].chips[2].status == .done)
    }

    @Test func failedMarksTheStepReached() {
        let model = makeModel()
        let id = UUID()
        model.receive(task(.capture, id: id))
        model.receive(task(.failed, id: id))
        model.flush()
        #expect(statuses(model.rows[0]) == [.failed, .pending, .pending, .pending, .pending])
    }

    @Test func awaitingInputNeedsAttention() {
        let model = makeModel()
        model.receive(task(.awaitingInput))
        #expect(model.rows[0].needsAttention)
        #expect(model.pose == .attention)
    }

    @Test func poseIsReadingDuringCaptureAndAnalyze() {
        for state: ResearchState in [.capture, .analyze] {
            let model = makeModel()
            model.receive(task(state))
            #expect(model.pose == .reading, "state \(state)")
        }
        let other = makeModel()
        other.receive(task(.report))
        #expect(other.pose != .reading)
        #expect(makeModel().pose == nil)
    }

    @Test func chipDisplayCarriesLabelIconMarkerAndRole() {
        let model = makeModel()
        model.receive(task(.clean))
        let chip = model.rows[0].chips[1]
        #expect(chip.status == .active)
        #expect(chip.colorRole == .test)
        #expect(!chip.icon.isEmpty && !chip.marker.isEmpty)
        #expect(chip.accessibilityLabel.contains("active"))
    }

    @Test func updatesInsideTheWindowAreCoalesced() async {
        let clock = ManualClock()
        let model = makeModel(clock: clock)
        let id = UUID()
        model.receive(task(.capture, id: id))
        #expect(model.rows[0].state == .capture)
        model.receive(task(.clean, id: id))
        model.receive(task(.awaitingPreview, id: id))
        #expect(model.rows[0].state == .capture)
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(100))
        for _ in 0..<200 where model.rows[0].state != .awaitingPreview { await Task.yield() }
        #expect(model.rows[0].state == .awaitingPreview)
    }

    @Test func safariStateAndInboxCountAreSettable() {
        let model = makeModel()
        model.setSafariState(.denied)
        model.setInboxCount(3)
        #expect(model.safariState == .denied)
        #expect(model.inboxCount == 3)
    }

    @Test func readingPoseDrawsADistinctFrameWithAPaper() {
        let reading = MascotFrame.frame(for: .reading, at: 0.5, reduceMotion: false)
        for pose: MascotPose in [.idle, .typing, .done, .error, .attention] {
            #expect(reading != MascotFrame.frame(for: pose, at: 0.5, reduceMotion: false))
        }
        #expect(reading.paper)
        #expect(MascotFrame.frame(for: .reading, at: 0, reduceMotion: true) ==
                MascotFrame.frame(for: .reading, at: 1.3, reduceMotion: true))
        #expect(MascotPose.reading.accessibilityLabel == "Reading")
    }
}
