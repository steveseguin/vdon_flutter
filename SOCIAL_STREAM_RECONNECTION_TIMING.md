# Social Stream WebRTC Reconnection Timing

## Updated Reconnection Timing (VDO.Ninja Aligned)

The reconnection timing now matches VDO.Ninja's behavior:

### Reconnection Delays:
1. **1st attempt**: 100ms (near instant)
2. **2nd attempt**: 2 seconds
3. **3rd attempt**: 5 seconds
4. **4th+ attempts**: 10 seconds (max)

### Why This Pattern?

1. **Near instant first retry (100ms)**
   - Handles brief network hiccups
   - Recovers from temporary disconnects quickly
   - Minimal disruption to user experience

2. **2 second second retry**
   - Allows time for network to stabilize
   - Not too aggressive to overload the server
   - Still fast enough for good UX

3. **5 second third retry**
   - More conservative approach
   - Gives time for longer network issues to resolve
   - Prevents rapid reconnection attempts

4. **10 second max delay**
   - Prevents excessive delays
   - Continues trying without being too aggressive
   - Balances server load and recovery time

### Code Implementation:
```dart
int delay;
if (_reconnectAttempts == 0) {
  // First attempt is near instant
  delay = _initialReconnectDelay; // 100ms
} else if (_reconnectAttempts == 1) {
  // Second attempt waits 2 seconds
  delay = _baseReconnectDelay; // 2000ms
} else if (_reconnectAttempts == 2) {
  // Third attempt waits 5 seconds
  delay = 5000;
} else {
  // Subsequent attempts wait 10 seconds max
  delay = _maxReconnectDelay; // 10000ms
}
```

### Expected Console Output:
```
[SocialStream-WebRTC] WebSocket closed
[SocialStream] Scheduling reconnect attempt 1 in 100ms
[SocialStream] Executing reconnection attempt 1
// If fails...
[SocialStream] Scheduling reconnect attempt 2 in 2000ms
[SocialStream] Executing reconnection attempt 2
// If fails...
[SocialStream] Scheduling reconnect attempt 3 in 5000ms
[SocialStream] Executing reconnection attempt 3
// If fails...
[SocialStream] Scheduling reconnect attempt 4 in 10000ms
// Continues at 10s intervals...
```

This pattern provides optimal recovery for different types of network issues while preventing server overload from too-aggressive reconnection attempts.