import { createContext, useCallback, useContext, useEffect, useReducer, useRef, useState, ReactNode } from "react";
import { navigate } from "wouter/use-browser-location";
import { Phone, PhoneOff, Video } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { api } from "@/lib/http";
import { Meeting, MeetingSession } from "@/lib/meetingCall";

interface MeetingCtx {
  /** The meeting the person is in right now (kept at app level, so changing page does not drop the call). */
  session: MeetingSession | null;
  /** Start (or re-use) the call for a meeting. Returns false when the person is already in a DIFFERENT live meeting. */
  enter: (m: Meeting) => boolean;
  leave: (endForAll?: boolean) => Promise<void>;
  /** Forget a session that already ended (nothing to leave on the server). */
  clearOver: () => void;
}

const Ctx = createContext<MeetingCtx | null>(null);

/** Plays one person's voice. Lives in the provider (always mounted), not in the room page. */
function PeerAudio({ stream }: { stream: MediaStream | null }) {
  const ref = useRef<HTMLAudioElement>(null);
  useEffect(() => { if (ref.current && ref.current.srcObject !== stream) ref.current.srcObject = stream; }, [stream]);
  return <audio ref={ref} autoPlay data-peer-audio />;
}

export function useMeeting() {
  const c = useContext(Ctx);
  if (!c) throw new Error("useMeeting must be used inside MeetingProvider");
  return c;
}

interface Ring { id: number; title: string; hostName: string }

/** A repeating phone-like double beep (Web Audio). Returns a function that stops it. */
function startRingtone(): () => void {
  let ctx: AudioContext | null = null;
  try { ctx = new (window.AudioContext || (window as any).webkitAudioContext)(); void ctx.resume(); } catch { return () => {}; }
  const c = ctx;
  const beep = () => {
    [0, 0.28].forEach((d) => {
      const o = c.createOscillator(); const g = c.createGain();
      o.type = "sine"; o.frequency.value = 880; g.gain.value = 0.15;
      o.connect(g); g.connect(c.destination);
      o.start(c.currentTime + d); o.stop(c.currentTime + d + 0.2);
    });
  };
  beep();
  const t = setInterval(beep, 1600);
  return () => { clearInterval(t); void c.close().catch(() => {}); };
}

export function MeetingProvider({ children }: { children: ReactNode }) {
  const { user, company } = useAuth();
  const [ring, setRing] = useState<Ring | null>(null);
  const handled = useRef(new Set<number>());
  const [session, setSession] = useState<MeetingSession | null>(null);
  const [, bump] = useReducer((n: number) => n + 1, 0);
  const sessionRef = useRef<MeetingSession | null>(null);
  sessionRef.current = session;

  // re-render whenever the call changes (people, tracks, timers...)
  useEffect(() => (session ? session.subscribe(bump) : undefined), [session]);

  const enter = useCallback((m: Meeting) => {
    const cur = sessionRef.current;
    if (cur && cur.meeting.id !== m.id && !cur.over) return false;
    if (cur && cur.meeting.id === m.id) return true;
    if (cur) cur.hangUp();
    if (!user) return false;
    const s = new MeetingSession(m, user.id, user.role === "hr_admin");
    setSession(s);
    void s.start();
    return true;
  }, [user]);

  const leave = useCallback(async (endForAll = false) => {
    const cur = sessionRef.current;
    if (!cur) return;
    setSession(null);
    await cur.leave(endForAll);
  }, []);

  const clearOver = useCallback(() => {
    sessionRef.current?.hangUp();
    setSession(null);
  }, []);

  // Signing out, or working in another company, ends the call: a meeting belongs to one company.
  const companyId = company?.id;
  useEffect(() => {
    if (!user) void leave();
  }, [user, leave]);
  useEffect(() => () => { sessionRef.current?.hangUp(); }, [companyId]);

  // RINGING: ask the server every 4 s whether a meeting I am invited to is due. The server decides who is rung (invited, not the
  // host, not already in the call, not declined); the same alert rings on the phone and the laptop app.
  useEffect(() => {
    if (!user) { setRing(null); return; }
    let stop = false;
    const check = async () => {
      if (sessionRef.current && !sessionRef.current.over) { setRing(null); return; }   // already in a call
      try {
        const list = await api<{ id: number; title: string; hostName: string }[]>("/meetings/ring");
        if (stop) return;
        const fresh = (Array.isArray(list) ? list : []).filter((m) => !handled.current.has(m.id));
        setRing((cur) => (fresh[0] ? (cur?.id === fresh[0].id ? cur : { id: fresh[0].id, title: fresh[0].title, hostName: fresh[0].hostName ?? "" }) : null));
      } catch { /* a missed check is fine */ }
    };
    void check();
    const t = setInterval(check, 4000);
    return () => { stop = true; clearInterval(t); };
  }, [user]);

  // while ringing: sound, flashing tab title, system notification
  useEffect(() => {
    if (!ring) return;
    const stopTone = startRingtone();
    const original = document.title;
    let on = true;
    const flash = setInterval(() => { document.title = on ? `📞 ${ring.title}` : original; on = !on; }, 900);
    let n: Notification | null = null;
    try {
      if (typeof Notification !== "undefined" && Notification.permission === "granted") {
        n = new Notification("Incoming meeting", { body: ring.title, tag: `ring-${ring.id}` });
        n.onclick = () => { window.focus(); n?.close(); };
      }
    } catch { /* ignore */ }
    return () => { stopTone(); clearInterval(flash); document.title = original; n?.close(); };
  }, [ring]);

  const joinRing = () => { if (!ring) return; handled.current.add(ring.id); const id = ring.id; setRing(null); navigate(`/meetings/${id}`); };
  const declineRing = () => { if (!ring) return; handled.current.add(ring.id); const id = ring.id; setRing(null); void api(`/meetings/${id}/dismiss`, "POST").catch(() => {}); };

  return (
    <Ctx.Provider value={{ session, enter, leave, clearOver }}>
      {children}
      {ring && (
        <div className="fixed inset-0 z-[100] bg-[#061B26]/95 flex items-center justify-center p-6" data-ring>
          <div className="text-center text-white max-w-sm w-full space-y-6">
            <div className="mx-auto h-28 w-28 rounded-full bg-white/10 flex items-center justify-center animate-pulse"><Video className="h-14 w-14" /></div>
            <p className="text-white/70">Incoming meeting · اجتماع وارد</p>
            <h2 className="text-3xl font-extrabold">{ring.title}</h2>
            {ring.hostName && <p className="text-white/70">{ring.hostName}</p>}
            <div className="flex justify-center gap-12 pt-4">
              <button onClick={declineRing} className="flex flex-col items-center gap-2" aria-label="Decline"><span className="h-16 w-16 rounded-full bg-red-500 flex items-center justify-center"><PhoneOff className="h-7 w-7" /></span><span className="text-sm">Decline · رفض</span></button>
              <button onClick={joinRing} className="flex flex-col items-center gap-2" aria-label="Join"><span className="h-16 w-16 rounded-full bg-emerald-500 flex items-center justify-center"><Phone className="h-7 w-7" /></span><span className="text-sm">Join · انضمام</span></button>
            </div>
          </div>
        </div>
      )}
      {session && [...session.peers.values()].map((p) => <PeerAudio key={p.userId} stream={p.stream} />)}
    </Ctx.Provider>
  );
}
