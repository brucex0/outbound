export const LIVE_COACH_STREAM_CONTENT_TYPE = "application/vnd.plainstride.live-coach-stream";

export function liveCoachStreamFrame(type: 1 | 2 | 3 | 4, payload: Uint8Array | object): Uint8Array {
  const body = payload instanceof Uint8Array
    ? payload
    : new TextEncoder().encode(JSON.stringify(payload));
  const frame = new Uint8Array(5 + body.byteLength);
  const view = new DataView(frame.buffer);
  frame[0] = type;
  view.setUint32(1, body.byteLength, false);
  frame.set(body, 5);
  return frame;
}
