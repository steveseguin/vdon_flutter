# Social Stream WebRTC ICE Candidate Fix

## The Problem
Browser was showing: "ICE DID NOT FIND A PC OPTION? peer might have left before ICE complete?"

## Root Cause
We were sending ICE candidates with `type: 'local'` which made the browser look in `session.rpcs[msg.UUID]` (remote peer connections). But since the browser initiated the connection to us, it stores our connection in `session.pcs` (peer connections), not `rpcs`.

## The Fix
Changed ICE candidate messages from:
```json
{
  "UUID": "browserUUID",
  "type": "local",
  "streamID": "ourUUID",
  "from": "ourUUID"
}
```

To:
```json
{
  "UUID": "browserUUID",
  "type": "remote",
  "session": "sessionFromOffer"
}
```

## Why This Works
- When `type: 'remote'`, the browser looks in `session.pcs[msg.UUID]`
- The browser created a peer connection to us with its own UUID
- By using `type: 'remote'` and the browser's UUID, we correctly target that connection

## VDO.Ninja Protocol Rules
1. `type: 'local'` = ICE from a peer that WE initiated connection to
2. `type: 'remote'` = ICE from a peer that initiated connection to US
3. The `UUID` field identifies which peer connection to add the ICE candidate to
4. Always include `session` field when available for proper routing