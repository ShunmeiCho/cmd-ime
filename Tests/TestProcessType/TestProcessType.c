#include "TestProcessType.h"

#include <ApplicationServices/ApplicationServices.h>

// Keeps a process that loads the test bundle out of the Dock.
//
// macOS registers a command-line process that touches certain AppKit-level APIs as a foreground
// app under the terminal it descends from, so every `swift test` put an extra terminal icon in the
// Dock for the length of the run (measured 2026-10-02: `xctest` listed as "Ghostty",
// type="Foreground"). Turning the process into a background application at load prevents that
// without creating NSApplication, which changes how the event-tap tests behave.
__attribute__((constructor))
static void keep_test_process_out_of_the_dock(void) {
    ProcessSerialNumber process = {0, kCurrentProcess};
    // TransformProcessType is deprecated and has no replacement that leaves NSApplication alone:
    // setActivationPolicy needs the shared application, and creating it here made ten
    // EventTapMonitorTests assertions fail. The call is kept on purpose.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    TransformProcessType(&process, kProcessTransformToBackgroundApplication);
#pragma clang diagnostic pop
}

void test_process_type_anchor(void) {}
