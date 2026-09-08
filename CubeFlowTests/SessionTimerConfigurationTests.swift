import CoreData
import Testing
@testable import CubeFlow

@MainActor
struct SessionTimerConfigurationTests {
    @Test func twoSessionsRestoreIndependentEventAndTimingAcrossRepeatedSwitches() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let sessionA = Session(
            name: "A",
            selectedEventRawValue: "square-1",
            selectedTimingMethodRawValue: SessionTimingMethod.gan.rawValue,
            context: context
        )
        let sessionB = Session(
            name: "B",
            selectedEventRawValue: "3x3",
            selectedTimingMethodRawValue: SessionTimingMethod.smartCube.rawValue,
            context: context
        )
        try context.save()

        for session in [sessionA, sessionB, sessionA, sessionB] {
            let restored = session.restoreTimerConfiguration(
                legacyTimingMethodRawValue: SessionTimingMethod.timer.rawValue
            )
            if session === sessionA {
                #expect(restored.eventRawValue == "square-1")
                #expect(restored.timingMethod == .gan)
            } else {
                #expect(restored.eventRawValue == "3x3")
                #expect(restored.timingMethod == .smartCube)
            }
        }

        #expect(sessionA.selectedTimingMethodRawValue == SessionTimingMethod.gan.rawValue)
        #expect(sessionB.selectedTimingMethodRawValue == SessionTimingMethod.smartCube.rawValue)
    }

    @Test func savedConfigurationSurvivesContextResetEquivalentToRelaunch() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let session = Session(
            name: "Square-1",
            selectedEventRawValue: "square-1",
            selectedTimingMethodRawValue: SessionTimingMethod.gan.rawValue,
            context: context
        )
        let sessionID = session.id
        try context.save()
        context.reset()

        let fetchedSession = try context.fetchSession(with: sessionID)
        let restoredSession = try #require(fetchedSession)
        let restored = restoredSession.restoreTimerConfiguration(
            legacyTimingMethodRawValue: SessionTimingMethod.smartCube.rawValue
        )
        #expect(restored.eventRawValue == "square-1")
        #expect(restored.timingMethod == .gan)
    }

    @Test func legacyTimingFallbackMigratesOnceAndCannotOverwritePersistedValue() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let session = Session(name: "Legacy", selectedEventRawValue: "square-1", context: context)
        session.selectedTimingMethodRawValue = nil

        let migrated = session.restoreTimerConfiguration(
            legacyTimingMethodRawValue: SessionTimingMethod.gan.rawValue
        )
        #expect(migrated.eventRawValue == "square-1")
        #expect(migrated.timingMethod == .gan)
        #expect(session.selectedTimingMethodRawValue == SessionTimingMethod.gan.rawValue)

        let restoredAgain = session.restoreTimerConfiguration(
            legacyTimingMethodRawValue: SessionTimingMethod.smartCube.rawValue
        )
        #expect(restoredAgain.timingMethod == .gan)
        #expect(session.selectedTimingMethodRawValue == SessionTimingMethod.gan.rawValue)
    }

    @Test func changingOneSessionDoesNotOverwriteAnotherAndNewDefaultsRemainStable() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let bluetoothSession = Session(
            name: "Bluetooth",
            selectedEventRawValue: "square-1",
            selectedTimingMethodRawValue: SessionTimingMethod.gan.rawValue,
            context: context
        )
        let smartCubeSession = Session(name: "Smart Cube", context: context)
        smartCubeSession.persistTimerConfiguration(
            eventRawValue: "3x3",
            timingMethodRawValue: SessionTimingMethod.smartCube.rawValue
        )

        #expect(bluetoothSession.selectedEventRawValue == "square-1")
        #expect(bluetoothSession.selectedTimingMethodRawValue == SessionTimingMethod.gan.rawValue)
        #expect(smartCubeSession.selectedEventRawValue == "3x3")
        #expect(smartCubeSession.selectedTimingMethodRawValue == SessionTimingMethod.smartCube.rawValue)

        let newSession = Session(name: "New", context: context)
        #expect(newSession.selectedEventRawValue == SessionTimerConfiguration.defaultEventRawValue)
        #expect(newSession.selectedTimingMethodRawValue == SessionTimingMethod.timer.rawValue)
    }
}
