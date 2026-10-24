import { useEffect, useState } from "react";
import { Link, useLocation } from "wouter";
import { CalendarClock, Plus, Video, Users } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/http";
import { Badge, Empty, Field, Modal, PageHeader, Spinner, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { useMeeting } from "@/contexts/MeetingContext";
import type { Meeting } from "@/lib/meetingCall";

interface Boot { canSchedule: boolean; invitable: { id: number; name: string; role: string }[] }

const fmt = (iso: string, isRTL: boolean) =>
  new Date(iso).toLocaleString(isRTL ? "ar" : "en", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/** My meetings: live now, upcoming, and the last two weeks. HR (and team leads) can start or schedule one. */
export default function Meetings() {
  const tr = useTr();
  const isRTL = tr("a", "b") === "b";
  const { session } = useMeeting();
  const [, nav] = useLocation();
  const [items, setItems] = useState<Meeting[] | null>(null);
  const [boot, setBoot] = useState<Boot | null>(null);
  const [form, setForm] = useState(false);

  const load = () => api<Meeting[]>("/meetings").then((d) => setItems(Array.isArray(d) ? d : [])).catch((e) => { toast.error(e.message); setItems([]); });
  useEffect(() => { load(); api<Boot>("/meetings/bootstrap").then(setBoot).catch(() => {}); }, []);

  if (!items) return <Spinner />;
  const now = Date.now();
  const live = items.filter((m) => m.status === "live");
  const upcoming = items.filter((m) => m.status === "scheduled" && new Date(m.scheduledAt).getTime() + (m.durationMin + 30) * 60000 > now);
  const past = items.filter((m) => !live.includes(m) && !upcoming.includes(m)).reverse();

  const card = (m: Meeting) => (
    <div key={m.id} className={`${cardCls} flex flex-wrap items-center gap-3`}>
      <div className={`h-10 w-10 rounded-xl flex items-center justify-center ${m.status === "live" ? "bg-emerald-100 text-emerald-700" : "bg-primary/10 text-primary"}`}>
        {m.status === "live" ? <Video className="h-5 w-5" /> : <CalendarClock className="h-5 w-5" />}
      </div>
      <div className="flex-1 min-w-48">
        <p className="font-semibold">{m.title}</p>
        <p className="text-sm text-muted-foreground">
          {fmt(m.scheduledAt, isRTL)} · <Users className="inline h-3.5 w-3.5" /> {m.participants.filter((p) => !p.removed).length}
          {m.status === "live" && m.participants.some((p) => p.joined) ? ` · ${m.participants.filter((p) => p.joined).length} ${tr("in the call", "داخل المكالمة")}` : ""}
        </p>
      </div>
      {m.canJoin ? (
        <button className={btnCls} onClick={() => nav(`/meetings/${m.id}`)}><Video className="h-4 w-4" />{tr("Join", "انضمام")}</button>
      ) : (
        <Badge tone={m.status === "live" ? "green" : m.status === "scheduled" ? "blue" : "gray"}>{{ scheduled: tr("Scheduled", "مجدول"), live: tr("Live", "مباشر"), ended: tr("Ended", "انتهى"), cancelled: tr("Cancelled", "ملغي") }[m.status]}</Badge>
      )}
    </div>
  );
  const section = (title: string, ms: Meeting[]) => ms.length ? <div className="space-y-3"><h2 className="text-lg font-bold">{title}</h2>{ms.map(card)}</div> : null;

  return (
    <div className="space-y-6">
      <PageHeader title={tr("Meetings", "الاجتماعات")}>
        {boot?.canSchedule && <button className={btnCls} onClick={() => setForm(true)}><Plus className="h-4 w-4" />{tr("New meeting", "اجتماع جديد")}</button>}
      </PageHeader>
      {session && !session.over && (
        <Link href={`/meetings/${session.meeting.id}`} className={`${cardCls} flex items-center justify-between border-primary/40`}>
          <span className="font-semibold">{tr("You are in a meeting", "أنت داخل اجتماع")}: {session.meeting.title}</span>
          <span className="text-primary font-semibold">{tr("Return to the meeting", "العودة إلى الاجتماع")}</span>
        </Link>
      )}
      {items.length === 0 && <Empty text={tr("No meetings yet. Meetings you are invited to appear here.", "لا توجد اجتماعات بعد. الاجتماعات التي تُدعى إليها تظهر هنا.")} />}
      {section(tr("Live now", "جارٍ الآن"), live)}
      {section(tr("Upcoming", "القادمة"), upcoming)}
      {section(tr("Recent", "الأخيرة"), past)}
      {form && boot && <MeetingForm invitable={boot.invitable} onClose={() => setForm(false)} onCreated={(m, now) => { setForm(false); load(); if (now) nav(`/meetings/${m.id}`); }} />}
    </div>
  );
}

function MeetingForm({ invitable, onClose, onCreated }: { invitable: Boot["invitable"]; onClose: () => void; onCreated: (m: Meeting, now: boolean) => void }) {
  const tr = useTr();
  const [title, setTitle] = useState("");
  const [now, setNow] = useState(true);
  const [at, setAt] = useState("");
  const [duration, setDuration] = useState(30);
  const [notes, setNotes] = useState("");
  const [picked, setPicked] = useState<number[]>([]);
  const [busy, setBusy] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!picked.length) return void toast.error(tr("Choose at least one person", "اختر شخصًا واحدًا على الأقل"));
    if (!now && !at) return void toast.error(tr("Choose the date and time", "اختر التاريخ والوقت"));
    setBusy(true);
    try {
      const m = await api<Meeting>("/meetings", "POST", { title, userIds: picked, durationMin: duration, notes: notes || undefined, ...(now ? { startNow: true } : { scheduledAt: new Date(at).toISOString() }) });
      toast.success(tr("Meeting created", "تم إنشاء الاجتماع"));
      onCreated(m, now);
    } catch (err: any) { toast.error(err.message); } finally { setBusy(false); }
  }

  return (
    <Modal open title={tr("New meeting", "اجتماع جديد")} onClose={onClose}>
      <form onSubmit={save} className="space-y-4">
        <Field label={tr("Meeting title", "عنوان الاجتماع")}><input required maxLength={150} className={inputCls} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={now} onChange={(e) => setNow(e.target.checked)} />{tr("Start now", "ابدأ الآن")}</label>
        {!now && <Field label={tr("Date and time", "التاريخ والوقت")}><input type="datetime-local" className={inputCls} value={at} onChange={(e) => setAt(e.target.value)} /></Field>}
        <Field label={tr("Length (minutes)", "المدة (بالدقائق)")}>
          <select className={inputCls} value={duration} onChange={(e) => setDuration(Number(e.target.value))}>{[15, 30, 45, 60, 90, 120].map((m) => <option key={m} value={m}>{m}</option>)}</select>
        </Field>
        <Field label={tr("Notes (optional)", "ملاحظات (اختياري)")}><input className={inputCls} value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
        <div>
          <p className="text-sm font-medium mb-1">{tr("Invite people", "دعوة الأشخاص")}</p>
          <div className="max-h-48 overflow-y-auto border border-border rounded-xl p-2 space-y-1">
            {invitable.map((p) => (
              <label key={p.id} className="flex items-center gap-2 text-sm px-1">
                <input type="checkbox" checked={picked.includes(p.id)} onChange={(e) => setPicked(e.target.checked ? [...picked, p.id] : picked.filter((x) => x !== p.id))} />{p.name}
              </label>
            ))}
          </div>
        </div>
        <div className="flex gap-2">
          <button className={`${btnCls} flex-1`} disabled={busy}>{now ? tr("Start now", "ابدأ الآن") : tr("Save", "حفظ")}</button>
          <button type="button" className={btnGhost} onClick={onClose}>{tr("Cancel", "إلغاء")}</button>
        </div>
      </form>
    </Modal>
  );
}
