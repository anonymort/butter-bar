/// The planner protocol. Implementations are deterministic state machines:
/// same initial state + same input sequence at same timestamps → same output.
/// The planner must never read a real clock, use randomness, or touch I/O.
/// See spec 04 and addendum A3.
public protocol PiecePlanner {
    func handle(event: PlayerEvent,
                at time: Instant,
                session: TorrentSessionView) -> [PlannerAction]

    func tick(at time: Instant,
              session: TorrentSessionView) -> [PlannerAction]

    func currentHealth(at time: Instant,
                       session: TorrentSessionView) -> StreamHealth
}
