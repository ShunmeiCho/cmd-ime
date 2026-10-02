import TestProcessType

/// Refers to the `TestProcessType` module so that the linker keeps it in the test bundle. Its
/// load-time constructor keeps the test process out of the Dock; nothing calls this.
let testProcessTypeAnchor: @convention(c) () -> Void = test_process_type_anchor
