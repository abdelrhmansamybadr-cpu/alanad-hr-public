import { api } from "@/lib/http";

/**
 * Online meeting call for the website. It speaks EXACTLY the same protocol as the phone / laptop app (Flutter), so a person
 * on the website, one on the phone and one on the laptop can be in the same call:
 *   - the server only relays small set-up messages (offer / answer / ice) through /meetings/:id/signal and /poll (every 2 s)
 *   - audio and video go directly between the devices (WebRTC); the person with the LOWER user id makes the offer
 *   - a data channel "ctl" carries {t:"state", mic, cam} so everybody sees who is muted / has the camera on
 */

export interface MeetingPerson { userId: number; name: string; role: string; joined: boolean; removed: boolean }
export interface Meeting {
  id: number; title: string; notes?: string | null; scheduledAt: string; durationMin: number;
  status: "scheduled" | "live" | "ended" | "cancelled"; createdBy: number; participants: MeetingPerson[]; canJoin: boolean;
}

interface Signal { id: number; from: number; type: string; payload: string | null }

export interface Peer {
  userId: number;
  pc: RTCPeerConnection | null;
  stream: MediaStream | null;
  channel: RTCDataChannel | null;
  sid: string;
  state: "connecting" | "connected" | "failed";
  micOn: boolean;
  camOn: boolean;
  remoteSet: boolean;
  pendingIce: RTCIceCandidateInit[];
}

const ICE_SERVERS: RTCIceServer[] = [{ urls: "stun:stun.l.google.com:19302" }, { urls: "stun:stun1.l.google.com:19302" }];
const newSid = () => Array.from({ length: 10 }, () => Math.floor(Math.random() * 36).toString(36)).join("");

export class MeetingSession {
  meeting: Meeting;
  myId: number;
  isHost: boolean;
  peers = new Map<number, Peer>();
  present = new Set<number>();
  local: MediaStream | null = null;
  micOn = true;
  camOn = false;
  hasMic = false;
  hasCamera = false;
  mediaError = false;
  joining = true;
  error: string | null = null;
  ended = false;
  removed = false;
  joinedAt: number | null = null;
  /** bytes received / sent per person + decoded video frames (proof that media and pictures really flow) */
  traffic = new Map<number, { rx: number; tx: number; frames: number }>();

  // --- screen sharing ("present.*" messages, separate connections; the phone / laptop app speak the same protocol)
  presenting = false;
  screenError: string | null = null;
  /** the screen somebody else is sharing with the meeting */
  screenIn: MediaStream | null = null;
  presenterId: number | null = null;
  private screenOut: MediaStream | null = null;
  private outs = new Map<number, { sid: string; pc: RTCPeerConnection; remoteSet: boolean; pending: RTCIceCandidateInit[] }>();
  private inPc: RTCPeerConnection | null = null;
  private inSid = "";
  private inRemoteSet = false;
  private inPending: RTCIceCandidateInit[] = [];
  static get canShare() { return typeof navigator !== "undefined" && !!navigator.mediaDevices?.getDisplayMedia; }

  private lastSignal = 0;
  private timer: ReturnType<typeof setInterval> | null = null;
  private statsTimer: ReturnType<typeof setInterval> | null = null;
  private polling = false;
  private disposed = false;
  private listeners = new Set<() => void>();

  constructor(meeting: Meeting, myId: number, isAdmin: boolean) {
    this.meeting = meeting;
    this.myId = myId;
    this.isHost = meeting.createdBy === myId || isAdmin;
  }

  subscribe(fn: () => void) { this.listeners.add(fn); return () => { this.listeners.delete(fn); }; }
  private notify() { if (!this.disposed) this.listeners.forEach((f) => f()); }
  get over() { return this.ended || this.removed; }
  nameOf(id: number) { return this.meeting.participants.find((p) => p.userId === id)?.name ?? "?"; }

  // ----------------------------------------------------------------- start

  async start() {
    try {
      this.local = await this.getMediaWithTimeout(45000);
      if (this.local) {
        this.hasMic = this.local.getAudioTracks().length > 0;
        this.hasCamera = this.local.getVideoTracks().length > 0;
        this.local.getVideoTracks().forEach((t) => (t.enabled = false)); // the camera starts off
      } else {
        this.mediaError = true;
      }
      const r = await api<{ present: number[]; lastSignalId: number }>(`/meetings/${this.meeting.id}/join`, "POST");
      this.lastSignal = r.lastSignalId ?? 0;
      this.present = new Set([...(r.present ?? []), this.myId]);
      await this.syncPresence();
      this.joinedAt = Date.now();
      this.joining = false;
      this.timer = setInterval(() => void this.tick(), 2000);
      this.statsTimer = setInterval(() => void this.collectStats(), 2000);
    } catch (e: any) {
      this.joining = false;
      this.error = e?.message ?? "Could not join";
      this.stopLocal();
    }
    this.notify();
  }

  /** The browser asks "allow microphone / camera?" - wait for the answer, but never forever: after the timeout the person
   *  joins listen-only (and a stream that arrives late is released so the camera light does not stay on). */
  private async getMediaWithTimeout(ms: number): Promise<MediaStream | null> {
    const pending = this.getMedia();
    const r = await Promise.race([pending, new Promise<null>((res) => setTimeout(() => res(null), ms))]);
    if (r === null) pending.then((s) => s?.getTracks().forEach((t) => t.stop())).catch(() => {});
    return r;
  }

  private async getMedia(): Promise<MediaStream | null> {
    if (!navigator.mediaDevices?.getUserMedia) return null;
    try {
      return await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: { width: 640, height: 360, frameRate: 24 } });
    } catch {
      try { return await navigator.mediaDevices.getUserMedia({ audio: true, video: false }); } catch { return null; }
    }
  }

  // ------------------------------------------------------------- the mesh

  private async syncPresence() {
    if (this.disposed) return;
    for (const id of this.present) {
      if (id === this.myId || this.peers.has(id)) continue;
      const p = this.newPeer(id);
      this.peers.set(id, p);
      this.createConnection(p);
      if (this.myId < id) await this.makeOffer(p); // the lower id offers
    }
    for (const id of [...this.peers.keys()]) if (!this.present.has(id)) this.closePeer(id);
    if (this.presenterId !== null && !this.present.has(this.presenterId)) this.clearViewer();
    await this.syncPresenting();
    this.notify();
  }

  private newPeer(userId: number): Peer {
    return { userId, pc: null, stream: null, channel: null, sid: newSid(), state: "connecting", micOn: true, camOn: false, remoteSet: false, pendingIce: [] };
  }

  private send(to: number, type: string, payload: unknown) {
    return api(`/meetings/${this.meeting.id}/signal`, "POST", { to, type, payload: JSON.stringify(payload) }).catch(() => {});
  }

  private createConnection(p: Peer, sid?: string) {
    p.sid = sid ?? newSid();
    p.remoteSet = false;
    p.pendingIce = [];
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS, bundlePolicy: "max-bundle" });
    p.pc = pc;
    this.local?.getTracks().forEach((t) => pc.addTrack(t, this.local!));
    pc.onicecandidate = (e) => {
      if (!e.candidate) return;
      const c = e.candidate;
      void this.send(p.userId, "ice", { sid: p.sid, c: { candidate: c.candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex } });
    };
    pc.ontrack = (e) => {
      p.stream = e.streams[0] ?? p.stream ?? new MediaStream();
      if (!e.streams[0]) p.stream.addTrack(e.track);
      this.notify();
    };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "connected") p.state = "connected";
      else if (pc.connectionState === "failed") p.state = "failed";
      else if (pc.connectionState === "disconnected" && p.state === "connected") p.state = "connecting";
      this.notify();
    };
    pc.ondatachannel = (e) => this.attachChannel(p, e.channel);
  }

  private attachChannel(p: Peer, ch: RTCDataChannel) {
    p.channel = ch;
    ch.onmessage = (m) => {
      try {
        const j = JSON.parse(String(m.data));
        if (j && j.t === "state") { p.micOn = j.mic !== false; p.camOn = j.cam === true; this.notify(); }
      } catch { /* ignore */ }
    };
    ch.onopen = () => this.sendState(p);
  }

  private async makeOffer(p: Peer) {
    const pc = p.pc;
    if (!pc) return;
    this.attachChannel(p, pc.createDataChannel("ctl", { ordered: true }));
    const offer = await pc.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: true });
    await pc.setLocalDescription(offer);
    await this.send(p.userId, "offer", { sid: p.sid, d: { sdp: offer.sdp, type: offer.type } });
  }

  private async applyPendingIce(p: Peer) {
    for (const c of p.pendingIce) await p.pc!.addIceCandidate(c).catch(() => {});
    p.pendingIce = [];
  }

  private async handle(s: Signal) {
    const body = s.payload ? JSON.parse(s.payload) : {};
    if (s.type === "offer") {
      let p = this.peers.get(s.from);
      if (!p) { p = this.newPeer(s.from); this.peers.set(s.from, p); }
      else if (p.sid !== body.sid) { p.pc?.close(); p.pc = null; }   // the other side restarted: start clean
      if (!p.pc) this.createConnection(p, body.sid);
      p.sid = body.sid;
      await p.pc!.setRemoteDescription(body.d);
      p.remoteSet = true;
      await this.applyPendingIce(p);
      const answer = await p.pc!.createAnswer();
      await p.pc!.setLocalDescription(answer);
      await this.send(s.from, "answer", { sid: p.sid, d: { sdp: answer.sdp, type: answer.type } });
    } else if (s.type === "answer") {
      const p = this.peers.get(s.from);
      if (!p || !p.pc || p.sid !== body.sid) return;
      await p.pc.setRemoteDescription(body.d);
      p.remoteSet = true;
      await this.applyPendingIce(p);
    } else if (s.type.startsWith("present.")) {
      await this.handlePresent(s, body);
    } else if (s.type === "ice") {
      const p = this.peers.get(s.from);
      if (!p || p.sid !== body.sid) return;
      if (p.remoteSet && p.pc) await p.pc.addIceCandidate(body.c).catch(() => {});
      else p.pendingIce.push(body.c); // arrived before the offer/answer was applied: keep until then
    }
  }

  // ------------------------------------------------------------- screen sharing

  async startPresenting() {
    if (this.presenting) return;
    if (this.presenterId !== null) { this.screenError = "busy"; this.notify(); return; }
    this.screenError = null;
    try {
      this.screenOut = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 15 }, audio: false });
    } catch {
      this.screenError = "capture";
      this.notify();
      return;
    }
    this.presenting = true;
    // the browser's own "Stop sharing" bar ends the capture: follow it
    this.screenOut.getVideoTracks().forEach((t) => (t.onended = () => void this.stopPresenting()));
    this.notify();
    await this.syncPresenting();
  }

  async stopPresenting() {
    if (!this.presenting) return;
    this.presenting = false;
    for (const [id, o] of this.outs) { void this.send(id, "present.stop", { sid: o.sid }); try { o.pc.close(); } catch { /* */ } }
    this.outs.clear();
    this.screenOut?.getTracks().forEach((t) => t.stop());
    this.screenOut = null;
    this.notify();
  }

  /** Offer the screen to everybody present who does not have it yet; drop those who left. */
  private async syncPresenting() {
    if (!this.presenting || !this.screenOut) return;
    for (const id of this.present) {
      if (id === this.myId || this.outs.has(id)) continue;
      const sid = newSid();
      const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
      const o = { sid, pc, remoteSet: false, pending: [] as RTCIceCandidateInit[] };
      this.outs.set(id, o);
      this.screenOut.getVideoTracks().forEach((t) => pc.addTrack(t, this.screenOut!));
      pc.onicecandidate = (e) => { if (e.candidate) void this.send(id, "present.ice", { sid, c: { candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex } }); };
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await this.send(id, "present.offer", { sid, d: { sdp: offer.sdp, type: offer.type } });
    }
    for (const id of [...this.outs.keys()]) if (!this.present.has(id)) { try { this.outs.get(id)!.pc.close(); } catch { /* */ } this.outs.delete(id); }
  }

  private async handlePresent(s: Signal, body: any) {
    if (s.type === "present.offer") {
      if (this.presenting) return;                                   // I am presenting myself
      if (this.presenterId !== null && this.presenterId !== s.from) return; // one presenter at a time
      if (this.presenterId === s.from && this.inSid !== body.sid) this.clearViewer();
      this.inSid = body.sid; this.inRemoteSet = false; this.inPending = []; this.presenterId = s.from;
      const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
      this.inPc = pc;
      pc.onicecandidate = (e) => { if (e.candidate) void this.send(s.from, "present.ice", { sid: this.inSid, c: { candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex } }); };
      pc.ontrack = (e) => { this.screenIn = e.streams[0] ?? new MediaStream([e.track]); this.notify(); };
      await pc.setRemoteDescription(body.d);
      this.inRemoteSet = true;
      for (const c of this.inPending) await pc.addIceCandidate(c).catch(() => {});
      this.inPending = [];
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await this.send(s.from, "present.answer", { sid: this.inSid, d: { sdp: answer.sdp, type: answer.type } });
    } else if (s.type === "present.answer") {
      const o = this.outs.get(s.from);
      if (!o || o.sid !== body.sid) return;
      await o.pc.setRemoteDescription(body.d);
      o.remoteSet = true;
      for (const c of o.pending) await o.pc.addIceCandidate(c).catch(() => {});
      o.pending = [];
    } else if (s.type === "present.ice") {
      const o = this.outs.get(s.from);
      if (o && o.sid === body.sid) { o.remoteSet ? await o.pc.addIceCandidate(body.c).catch(() => {}) : o.pending.push(body.c); }
      else if (s.from === this.presenterId && body.sid === this.inSid) { this.inRemoteSet && this.inPc ? await this.inPc.addIceCandidate(body.c).catch(() => {}) : this.inPending.push(body.c); }
    } else if (s.type === "present.stop") {
      if (s.from === this.presenterId && body.sid === this.inSid) this.clearViewer();
      const o = this.outs.get(s.from);
      if (o) { try { o.pc.close(); } catch { /* */ } this.outs.delete(s.from); }
    }
  }

  private clearViewer() {
    if (this.presenterId === null && !this.inPc) return;
    this.presenterId = null; this.inSid = ""; this.inRemoteSet = false; this.inPending = [];
    try { this.inPc?.close(); } catch { /* */ }
    this.inPc = null;
    this.screenIn = null;
    this.notify();
  }

  // ----------------------------------------------------------------- polling

  private async tick() {
    if (this.polling || this.disposed || this.over) return;
    this.polling = true;
    try {
      const r = await api<{ status: string; removed: boolean; signals: Signal[]; present: number[] }>(`/meetings/${this.meeting.id}/poll?after=${this.lastSignal}`);
      if (this.disposed) return;
      if (r.signals.length) this.lastSignal = r.signals[r.signals.length - 1].id;
      this.present = new Set(r.present);
      const ended = r.status === "ended" || r.status === "cancelled";
      if (ended || r.removed) {
        this.ended = ended;
        this.removed = r.removed;
        this.hangUp();
        this.notify();
        return;
      }
      for (const s of r.signals) { try { await this.handle(s); } catch (e) { console.warn("meeting signal failed", s.type, e); } }
      await this.syncPresence();
    } catch { /* a missed poll is fine: the next one catches up */ }
    finally { this.polling = false; }
  }

  private async collectStats() {
    for (const [id, p] of this.peers) {
      if (!p.pc) continue;
      let rx = 0, tx = 0, frames = 0;
      try {
        (await p.pc.getStats()).forEach((r: any) => {
          if (r.type === "inbound-rtp") { rx += r.bytesReceived ?? 0; if ((r.kind ?? r.mediaType) === "video") frames = r.framesDecoded ?? 0; }
          if (r.type === "outbound-rtp") tx += r.bytesSent ?? 0;
        });
      } catch { /* closed */ }
      this.traffic.set(id, { rx, tx, frames });
    }
    this.notify();
  }

  // ---------------------------------------------------------------- controls

  private sendState(p: Peer) {
    if (p.channel?.readyState === "open") p.channel.send(JSON.stringify({ t: "state", mic: this.micOn, cam: this.camOn }));
  }
  private broadcastState() { this.peers.forEach((p) => this.sendState(p)); }

  setMic(on: boolean) {
    this.micOn = on;
    this.local?.getAudioTracks().forEach((t) => (t.enabled = on));
    this.broadcastState();
    this.notify();
  }
  setCam(on: boolean) {
    if (!this.hasCamera) return;
    this.camOn = on;
    this.local?.getVideoTracks().forEach((t) => (t.enabled = on));
    this.broadcastState();
    this.notify();
  }

  async kick(userId: number): Promise<string | null> {
    try { await api(`/meetings/${this.meeting.id}/members/${userId}`, "DELETE"); this.present.delete(userId); this.notify(); return null; }
    catch (e: any) { return e.message; }
  }

  // ----------------------------------------------------------------- closing

  private closePeer(id: number) {
    const p = this.peers.get(id);
    if (!p) return;
    try { p.channel?.close(); } catch { /* */ }
    try { p.pc?.close(); } catch { /* */ }
    this.peers.delete(id);
    this.traffic.delete(id);
  }

  private stopLocal() {
    this.local?.getTracks().forEach((t) => t.stop());
    this.local = null;
  }

  /** Close every connection and release the microphone / camera. */
  hangUp() {
    if (this.timer) clearInterval(this.timer);
    if (this.statsTimer) clearInterval(this.statsTimer);
    this.timer = this.statsTimer = null;
    [...this.peers.keys()].forEach((id) => this.closePeer(id));
    void this.stopPresenting();
    this.clearViewer();
    this.stopLocal();
  }

  async leave(endForAll = false) {
    if (endForAll) { try { await api(`/meetings/${this.meeting.id}/end`, "POST"); } catch { /* */ } }
    this.hangUp();
    try { await api(`/meetings/${this.meeting.id}/leave`, "POST"); } catch { /* */ }
    this.disposed = true;
    this.listeners.clear();
  }
}
