import IOKit.pwr_mgt

/// Keeps the display awake and the Mac out of idle sleep while the dashboard window
/// is open, so the KPI screen stays lit and up to date at all times.
final class DisplaySleepBlocker {
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0
    private var isActive = false

    func start() {
        guard !isActive else { return }
        let reason = "Claude Usage Dashboard affiché" as CFString

        var displayID: IOPMAssertionID = 0
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayID
        )
        if displayResult == kIOReturnSuccess {
            displayAssertionID = displayID
        }

        var systemID: IOPMAssertionID = 0
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemID
        )
        if systemResult == kIOReturnSuccess {
            systemAssertionID = systemID
        }

        isActive = displayResult == kIOReturnSuccess || systemResult == kIOReturnSuccess
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(displayAssertionID)
        IOPMAssertionRelease(systemAssertionID)
        isActive = false
    }
}
