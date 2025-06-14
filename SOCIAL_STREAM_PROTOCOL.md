# Social Stream WebRTC Protocol Analysis

## Key Understanding
Based on your clarification:
- **UUID**: Identifies the WebSocket connection (assigned by server, changes on reconnect)
- **session**: Identifies data channel messages within the same session (survives WebRTC reconnections)

## The "ICE DID NOT FIND A PC OPTION" Error
This error occurs when:
1. We send ICE candidates to the browser
2. The browser doesn't know which peer connection they belong to
3. This happens because our UUID isn't properly associated with the connection

## Current Issue
1. We join the room and get a listing
2. We seed ourselves (but might not be getting/storing the UUID correctly)
3. We request to view the target
4. We receive an offer from the browser
5. We send answer and ICE candidates
6. Browser doesn't recognize our UUID → "ICE DID NOT FIND A PC OPTION"

## What We Need
1. Properly capture our server-assigned UUID from the seed response
2. Include our UUID in ALL messages (answer, ICE candidates)
3. Make sure the browser knows our UUID before we send ICE candidates

## Debug Steps
1. Check the exact response format when we seed
2. Ensure we store the UUID correctly
3. Include UUID in all outgoing messages
4. Verify the browser recognizes our UUID

## VDO.Ninja Flow
1. Join room → Get listing
2. Seed with minimal info → Server assigns UUID
3. Request to view target → Browser creates offer
4. Send answer with our UUID → Browser knows who we are
5. Exchange ICE candidates with proper UUID identification