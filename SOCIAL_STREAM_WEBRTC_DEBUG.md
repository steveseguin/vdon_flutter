# Social Stream WebRTC Debug - Current Status

## What's Working
1. WebSocket connects to `wss://wss.socialstream.ninja:443` ✓
2. We join the room and get a listing ✓
3. We receive SDP offers and ICE candidates ✓
4. We create answers and peer connections ✓

## The Problem
Browser shows: "ICE DID NOT FIND A PC OPTION? peer might have left before ICE complete?"

This means the browser doesn't recognize our UUID when we send ICE candidates back.

## Current Flow
1. Flutter app joins room: `{"request":"joinroom","roomid":"stever"}`
2. Gets empty listing: `{"request": "listing", "list": []}`
3. Requests to view: `{"request":"play","streamID":"stever"}`
4. Receives offer from browser (UUID: 28f92b6734d444b3a5e8ddd9666a27da)
5. Creates answer and sends ICE candidates
6. Browser doesn't recognize our connection

## The Issue
The browser (Social Stream publisher) doesn't know who we are because:
1. We never seeded ourselves with a UUID
2. The browser created a peer connection TO us but doesn't know our identity

## Solution Needed
When using VDO.Ninja's viewer mode (`&view=SESSION`), we need to:
1. Seed ourselves BEFORE requesting to view
2. Include our UUID in all messages so the browser knows who we are

## Next Steps
1. Always seed with our UUID first
2. Include our streamID in the answer message
3. Make sure ICE candidates include both our UUID and the target UUID

The key is that VDO.Ninja needs bidirectional identification - both peers need to know each other's UUIDs.