import { useEffect, useRef, useState } from "react";
import { useLocation, useRoute } from "wouter";
import { ChevronDown, Mic, MicOff, MonitorOff, MonitorUp, PhoneOff, UserMinus, Users, Video, VideoOff } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/http";
import { useTr } from "@/components/kit";
import { useMeeting } from "@/contexts/MeetingContext";
import { useAuth } from "@/contexts/AuthContext";
import { MeetingSession, type Meeting } from "@/lib/meetingCall";

/** One tile (picture only: the voices are played by <PeerAudio> in MeetingProvider, so the call keeps sounding when this page is closed). */
function Tile({ name, avatarName, stream, mirror, showVideo, micOn, state, info }: { name: string; avatarName?: string; stream: MediaStream | null; mirror?: boolean; showVideo: boolean; micOn: boolean; state?: string; info?: string }) {
  const tr = useTr();
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => { if (ref.current && ref.current.srcObject !== stream) ref.current.srcObject = stream; }, [stream]);
  return (
    <div className="relative rounded-2xl overflow-hidden bg-[#16213A] aspect-video min-h-40" data-tile={name}>
      <video ref={ref} autoPlay playsInline muted className={`absolute inset-0 h-full w-full object-cover ${mirror ? "-scale-x-100" : ""} ${showVideo ? "" : "invisible"}`} />
      {!showVideo && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="h-20 w-20 rounded-full bg-primary/80 text-white text-3xl font-bold flex items-center justify-center">{((avatarName ?? name).trim()[0] ?? "?").toUpperCase()}</div>
        </div>
      )}
      <div className="absolute bottom-2 left-2 right-2 flex items-center gap-2">
        <span className="px-2 py-1 rounded-lg bg-black/60 text-white text-xs truncate">{name}</span>
        {!micOn && <MicOff className="h-4 w-4 text-red-400" />}
      </div>
      {state === "connecting" && <span className="absolute top-2 left-2 px-2 py-1 rounded-lg bg-black/60 text-white text-[11px]">{tr("Connecting…", "جارٍ الاتصال…")}</span>}
      {state === "failed" && <span className="absolute top-2 left-2 px-2 py-1 rounded-lg bg-red-500 text-white text-[11px]">{tr("Connection failed", "فشل الاتصال")}</span>}
      {info && state === "connected" && <span className="absolute top-2 right-2 text-[10px] text-white/50" data-traffic>{info}</span>}
    </div>
  );
}

function ScreenVideo({ stream }: { stream: MediaStream }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => { if (ref.current && ref.current.srcObject !== stream) ref.current.srcObject = stream; }, [stream]);
  return <video ref={ref} autoPlay playsInline muted className="h-full w-full object-contain" />;
}

function Round({ on, danger, onClick, children, label }: { on?: boolean; danger?: boolean; onClick?: () => void; children: React.ReactNode; label: string }) {
  return (
    <button onClick={onClick} disabled={!onClick} aria-label={label} title={label}
      className={`h-14 w-14 rounded-full flex items-center justify-center transition disabled:opacity-40 ${danger ? "bg-red-500 text-white" : on ? "bg-white/20 text-white" : "bg-white text-black"}`}>
      {children}
    </button>
  );
}

export default function MeetingRoom() {
  const tr = useTr();
  const [, params] = useRoute("/meetings/:id");
  const id = Number(params?.id);
  const [, nav] = useLocation();
  const { user } = useAuth();
  const { session, enter, leave, clearOver } = useMeeting();
  const [meeting, setMeeting] = useState<Meeting | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showPeople, setShowPeople] = useState(false);
  const [, tick] = useState(0);
  const mine = session && session.meeting.id === id ? session : null;

  useEffect(() => {
    if (mine) return;
    api<Meeting>(`/meetings/${id}`).then((m) => {
      setMeeting(m);
      // an old / cancelled / not-yet-open meeting (e.g. from an old notification): say so instead of trying to join
      if (m.status === "ended" || m.status === "cancelled") { setError(m.status === "cancelled" ? tr("This meeting was cancelled", "تم إلغاء هذا الاجتماع") : tr("The meeting has ended", "انتهى الاجتماع")); return; }
      if (!m.canJoin) { setError(tr("You can join 5 minutes before the start", "يمكنك الانضمام قبل الموعد بـ 5 دقائق")); return; }
      if (!enter(m)) { toast.error(tr("You are already in another meeting. Leave it first.", "أنت بالفعل في اجتماع آخر. غادره أولًا.")); nav("/meetings"); }
    }).catch((e) => setError(e.message));
  }, [id]);
  useEffect(() => { const t = setInterval(() => tick((n) => n + 1), 1000); return () => clearInterval(t); }, []);

  const back = () => nav("/meetings");
  const dark = "fixed inset-0 z-40 bg-[#0B1220] text-white flex flex-col";
  const msg = (text: string, btn?: boolean) => (
    <div className={`${dark} items-center justify-center gap-5 p-8 text-center`}>
      <p className="text-lg">{text}</p>
      {btn && <button className="px-5 py-2 rounded-xl bg-white text-black font-medium" onClick={() => { clearOver(); back(); }}>{tr("Back to meetings", "العودة إلى الاجتماعات")}</button>}
    </div>
  );

  if (error) return msg(error, true);
  if (!mine) return msg(tr("Joining…", "جارٍ الانضمام…"));
  if (mine.joining) return msg(tr("Joining… If the browser asks, allow the microphone and camera.", "جارٍ الانضمام… إذا سأل المتصفح فاسمح بالميكروفون والكاميرا."));
  if (mine.error) return msg(mine.error, true);
  if (mine.over) return msg(mine.removed ? tr("The host removed you from the meeting", "أخرجك المنظّم من الاجتماع") : tr("The meeting has ended", "انتهى الاجتماع"), true);

  const s: MeetingSession = mine;
  const peers = [...s.peers.values()].sort((a, b) => a.userId - b.userId);
  const secs = Math.floor((Date.now() - (s.joinedAt ?? Date.now())) / 1000);
  const clock = `${String(Math.floor(secs / 60)).padStart(2, "0")}:${String(secs % 60).padStart(2, "0")}`;
  const kb = (id: number) => { const t = s.traffic.get(id); return t ? `↓${Math.round(t.rx / 1024)} KB ↑${Math.round(t.tx / 1024)} KB${t.frames > 0 ? ` ▶${t.frames}` : ""}` : undefined; };
  const n = peers.length + 1;
  const cols = n <= 1 ? "grid-cols-1 max-w-3xl mx-auto" : n <= 4 ? "grid-cols-1 md:grid-cols-2" : "grid-cols-2 lg:grid-cols-3";

  async function doLeave() {
    let all = false;
    if (s.isHost) all = window.confirm(tr("End the meeting for everybody? (Cancel = just leave)", "إنهاء الاجتماع للجميع؟ (إلغاء = المغادرة فقط)"));
    await leave(all);
    back();
  }

  return (
    <div className={dark} data-meeting-room>
      <div className="flex items-center gap-3 px-4 py-3">
        <button onClick={back} className="p-2 rounded-lg hover:bg-white/10" title={tr("Keep the call and go back", "ابقَ في المكالمة وارجع")}><ChevronDown className="h-6 w-6" /></button>
        <div className="flex-1 min-w-0">
          <p className="font-bold truncate">{s.meeting.title}</p>
          <p className="text-xs text-white/60" data-clock>{clock} · {s.present.size} {tr("people", "أشخاص")}</p>
        </div>
        <button onClick={() => setShowPeople((v) => !v)} className="p-2 rounded-lg hover:bg-white/10"><Users className="h-5 w-5" /></button>
      </div>
      {s.mediaError && <div className="bg-orange-900 text-sm px-4 py-2">{tr("No microphone or camera access: you can listen, but others cannot hear you. Allow access in the browser address bar.", "لا يوجد إذن للميكروفون أو الكاميرا: يمكنك الاستماع لكن الآخرين لن يسمعوك. اسمح بالوصول من شريط عنوان المتصفح.")}</div>}
      {s.presenting && (
        <div className="bg-sky-900 px-4 py-2 flex items-center gap-3 text-sm">
          <MonitorUp className="h-4 w-4" /><span className="flex-1">{tr("You are sharing your screen with the meeting", "أنت تشارك شاشتك مع الاجتماع")}</span>
          <button className="px-3 py-1 rounded-lg bg-white/15 hover:bg-white/25" onClick={() => void s.stopPresenting()}>{tr("Stop sharing", "إيقاف المشاركة")}</button>
        </div>
      )}
      <div className="flex-1 overflow-y-auto p-3">
        {s.screenIn && (
          <div className="relative rounded-2xl overflow-hidden bg-black mb-3 h-[55vh]" data-screen-share>
            <ScreenVideo stream={s.screenIn} />
            <span className="absolute top-2 left-2 px-2 py-1 rounded-lg bg-black/60 text-white text-xs">{tr(`${s.nameOf(s.presenterId ?? 0)} is sharing their screen`, `${s.nameOf(s.presenterId ?? 0)} يشارك شاشته`)}</span>
          </div>
        )}
        <div className={`grid gap-3 ${cols}`}>
          <Tile name={`${s.nameOf(s.myId) || user?.name || ""} (${tr("You", "أنت")})`} avatarName={s.nameOf(s.myId) || user?.name || ""} stream={s.local} mirror showVideo={s.camOn && s.hasCamera} micOn={s.micOn} />
          {peers.map((p) => (
            <Tile key={p.userId} name={s.nameOf(p.userId)} stream={p.stream} showVideo={!!p.stream?.getVideoTracks().length && p.camOn} micOn={p.micOn} state={p.state} info={kb(p.userId)} />
          ))}
        </div>
        {peers.length === 0 && <p className="text-center text-white/60 mt-4">{tr("Waiting for others to join…", "في انتظار انضمام الآخرين…")}</p>}
      </div>
      <div className="flex justify-center gap-4 py-4">
        <Round on={s.micOn} onClick={s.hasMic ? () => s.setMic(!s.micOn) : undefined} label={tr("Microphone", "الميكروفون")}>{s.micOn ? <Mic /> : <MicOff />}</Round>
        <Round on={s.camOn} onClick={s.hasCamera ? () => s.setCam(!s.camOn) : undefined} label={tr("Camera", "الكاميرا")}>{s.camOn ? <Video /> : <VideoOff />}</Round>
        {MeetingSession.canShare && (
          <Round on={!s.presenting} onClick={s.screenIn && !s.presenting ? undefined : () => void (s.presenting ? s.stopPresenting() : s.startPresenting())} label={s.presenting ? tr("Stop sharing", "إيقاف المشاركة") : tr("Share screen", "مشاركة الشاشة")}>{s.presenting ? <MonitorOff /> : <MonitorUp />}</Round>
        )}
        <Round danger onClick={doLeave} label={tr("Leave", "مغادرة")}><PhoneOff /></Round>
      </div>
      {showPeople && (
        <div className="absolute top-14 right-3 w-72 rounded-2xl bg-[#16213A] border border-white/10 p-3 space-y-1 shadow-xl">
          {s.meeting.participants.filter((p) => !p.removed).map((p) => (
            <div key={p.userId} className="flex items-center gap-2 text-sm py-1">
              <span className={`h-2.5 w-2.5 rounded-full ${s.present.has(p.userId) ? "bg-green-500" : "bg-gray-500"}`} />
              <span className="flex-1 truncate">{p.name}{p.userId === s.myId ? ` (${tr("You", "أنت")})` : ""}{p.role === "host" ? ` · ${tr("Host", "المنظّم")}` : ""}</span>
              {s.isHost && p.role !== "host" && p.userId !== s.myId && (
                <button title={tr("Remove from meeting", "إخراج من الاجتماع")} className="p-1 rounded hover:bg-white/10 text-red-400"
                  onClick={async () => { const e = await s.kick(p.userId); e ? toast.error(e) : toast.success(`${p.name}`); }}><UserMinus className="h-4 w-4" /></button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
