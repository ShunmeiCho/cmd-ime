/// Emitted only after an event-tap trigger successfully selects its input source.
public struct SetupTriggeredSwitch: Equatable, Sendable {
    public let slotID: InputRole
    public let sourceID: String
    public let trigger: KeyTrigger

    public init(slotID: InputRole, sourceID: String, trigger: KeyTrigger) {
        self.slotID = slotID
        self.sourceID = sourceID
        self.trigger = trigger
    }
}
