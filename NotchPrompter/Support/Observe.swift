import Observation
import Foundation

/// Calls `apply` with the result of `track` now, and again whenever an @Observable
/// property read inside `track` changes. Only `track` is observed, so side effects in
/// `apply` can't accidentally subscribe to more state.
@MainActor
func observe<Value>(_ track: @escaping @MainActor () -> Value,
                    apply: @escaping @MainActor (Value) -> Void) {
    let value = withObservationTracking {
        track()
    } onChange: {
        // onChange fires on willSet; hop to the next main-loop turn to read the new value.
        DispatchQueue.main.async {
            observe(track, apply: apply)
        }
    }
    apply(value)
}
