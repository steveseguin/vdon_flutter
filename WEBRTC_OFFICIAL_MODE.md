# VDO.Ninja Official WSS Mode Implementation

## Key Changes Made

1. **Session Tracking**: Added `_peerSessions` map to track session IDs for each peer connection

2. **Simplified ICE Messages**: 
   - Only include `UUID` (target) and `session`
   - Remove `room` and `streamID` from ICE candidates (not needed in official mode)

3. **Answer Format**:
   - Include `UUID` (target), `streamID` (our ID), and `session`
   - Session comes from the offer we received

4. **Seed Process**:
   - Let server assign our UUID (don't generate one)
   - Wait for seed confirmation before requesting to view

## Official WSS Mode Message Format

### ICE Candidate:
```json
{
  "candidate": {
    "candidate": "...",
    "sdpMLineIndex": 0,
    "sdpMid": "..."
  },
  "UUID": "targetPeerUUID",
  "session": "sessionFromOffer"
}
```

### Answer:
```json
{
  "description": {
    "type": "answer",
    "sdp": "..."
  },
  "UUID": "targetPeerUUID",
  "streamID": "ourUUID",
  "session": "sessionFromOffer"
}
```

## Current Flow
1. Join room
2. Seed (server assigns UUID)
3. Request to view target
4. Receive offer (with session ID)
5. Store session ID
6. Send answer with session
7. Exchange ICE candidates with session

This should resolve the "ICE DID NOT FIND A PC OPTION" error!