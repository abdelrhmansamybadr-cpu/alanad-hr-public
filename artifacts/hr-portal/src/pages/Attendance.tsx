import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Download, Footprints, AlarmClock, LogOut, Timer, Pencil, Trash2, ShieldAlert } from "lucide-react";
import { toast } from "sonner";
import { api, downloadFile, ymd } from "@/lib/http";
import { Badge, Field, Modal, PageHeader, Spinner, STATUS_TONE, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { useLang } from "@/contexts/LanguageContext";
import { ExplainPanel } from "@/components/ExplainPanel";

interface Row {
  employeeId: number;
  employeeName: string;
  position?: string | null;
  departmentName?: string | null;
  attendanceId?: number | null;
  checkIn?: string | null;
  checkOut?: string | null;
  boardStatus: string;
  lateMinutes: number;
  earlyLeaveMinutes: number;
  overtimeMinutes: number;
  outZoneMinutes: number;
  outsideNow: boolean;
  flags?: string | null;
  securityFlags?: string | null;
  hoursWorked?: number | null;
  leaveType?: string | null;
}
interface Board { date: string; holiday?: string | null; counts: Record<string, number>; total: number; employees: Row[] }

const FILTERS = ["", "present", "late", "half_day", "absent", "on_leave", "not_in", "not_started", "outside"];

export default function Attendance() {
  const tr = useTr();
  const { isRTL } = useLang();
  const qc = useQueryClient();
  const [day, setDay] = useState(ymd(new Date()));
  const [tab, setTab] = useState<"board" | "month">("board");
  const [filter, setFilter] = useState("");
  const [edit, setEdit] = useState<Row | null>(null);

  const { data: board, isLoading } = useQuery<Board>({ queryKey: ["board", day], queryFn: () => api(`/attendance/board?date=${day}`), refetchInterval: 60000 });

  const statusLabel: Record<string, string> = {
    present: tr("Present", "حاضر"), late: tr("Late", "متأخر"), half_day: tr("Half day", "نصف يوم"), absent: tr("Absent", "غائب"),
    on_leave: tr("On leave", "إجازة"), not_in: tr("Not in yet", "لم يحضر بعد"), not_started: tr("Not signed in yet (not counted)", "لم يسجّل الدخول بعد (غير محسوب)"), off: tr("Day off", "يوم راحة"), holiday: tr("Holiday", "عطلة"),
  };
  const shift = (n: number) => { const d = new Date(day + "T12:00:00"); d.setDate(d.getDate() + n); setDay(ymd(d)); };
  const rows = (board?.employees ?? []).filter((r) => (filter === "" ? true : filter === "outside" ? r.outsideNow : r.boardStatus === filter));
  const c = board?.counts ?? {};
  const outsideCount = (board?.employees ?? []).filter((r) => r.outsideNow).length;

  const refresh = () => { qc.invalidateQueries({ queryKey: ["board"] }); qc.invalidateQueries({ queryKey: ["/api/attendance"] }); };

  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Attendance", "الحضور")} subtitle={tr("Status is worked out automatically from each shift, the times and the location.", "تُحسب الحالة تلقائياً من الوردية والأوقات والموقع.")}>
        <button className={btnGhost} onClick={() => downloadFile(`/reports/attendance-daily?from=${day}&to=${day}&format=csv`, `attendance-${day}.csv`).catch((e) => toast.error(e.message))}><Download className="h-4 w-4" />{tr("Export day", "تصدير اليوم")}</button>
        <button className={btnGhost} onClick={() => downloadFile(`/reports/attendance?month=${day.slice(0, 7)}&format=csv`, `attendance-${day.slice(0, 7)}.csv`).catch((e) => toast.error(e.message))}><Download className="h-4 w-4" />{tr("Export month", "تصدير الشهر")}</button>
      </PageHeader>

      <div className="flex gap-2">
        {(["board", "month"] as const).map((k) => (
          <button key={k} onClick={() => setTab(k)} className={`px-4 py-2 rounded-xl text-sm font-medium ${tab === k ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>{k === "board" ? tr("Daily board", "لوحة اليوم") : tr("Monthly summary", "ملخص الشهر")}</button>
        ))}
      </div>

      {tab === "month" ? <Monthly month={day.slice(0, 7)} onMonth={(m) => setDay(m + "-01")} /> : (
        <>
          <div className="flex items-center gap-2">
            <button className={btnGhost} onClick={() => shift(-1)}>{isRTL ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}</button>
            <input type="date" className={inputCls + " max-w-[11rem]"} value={day} onChange={(e) => e.target.value && setDay(e.target.value)} />
            <button className={btnGhost} onClick={() => shift(1)}>{isRTL ? <ChevronLeft className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}</button>
            {board?.holiday && <Badge tone="violet">{board.holiday}</Badge>}
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
            {[
              ["present", c.present, "text-emerald-600"], ["late", c.late, "text-amber-600"], ["half_day", c.half_day, "text-orange-600"],
              ["absent", c.absent, "text-red-600"], ["on_leave", c.on_leave, "text-blue-600"], ["not_in", c.not_in, "text-muted-foreground"], ["not_started", c.not_started ?? 0, "text-muted-foreground"],
            ].map(([k, v, cls]: any) => (
              <button key={k} onClick={() => setFilter(filter === k ? "" : k)} className={`${cardCls} !p-4 text-start ${filter === k ? "ring-2 ring-primary" : ""}`}>
                <div className={`text-3xl font-extrabold ${cls}`}>{v ?? 0}</div>
                <div className="text-xs text-muted-foreground">{statusLabel[k]}</div>
              </button>
            ))}
          </div>

          <div className="flex flex-wrap gap-2">
            {FILTERS.map((f) => (
              <button key={f} onClick={() => setFilter(f)} className={`px-3 py-1.5 rounded-full text-xs font-semibold ${filter === f ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>
                {f === "" ? tr("All", "الكل") : f === "outside" ? `${tr("Away now", "خارج العمل الآن")} (${outsideCount})` : statusLabel[f]}
              </button>
            ))}
          </div>

          <div className="bg-card rounded-2xl border border-border overflow-hidden">
            {isLoading ? <Spinner /> : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/40 text-xs uppercase text-muted-foreground">
                    <tr>{[tr("Employee", "الموظف"), tr("Status", "الحالة"), tr("Check in", "الحضور"), tr("Check out", "الانصراف"), tr("Hours", "ساعات"), tr("Details", "تفاصيل"), ""].map((h, i) => <th key={i} className="px-4 py-3 text-start font-semibold">{h}</th>)}</tr>
                  </thead>
                  <tbody>
                    {rows.length === 0 && <tr><td colSpan={7} className="p-10 text-center text-muted-foreground">{tr("Nothing to show", "لا يوجد ما يُعرض")}</td></tr>}
                    {rows.map((r) => (
                      <tr key={r.employeeId} className="border-t border-border hover:bg-muted/30">
                        <td className="px-4 py-3"><div className="font-medium">{r.employeeName}</div><div className="text-xs text-muted-foreground">{r.departmentName || r.position || ""}</div></td>
                        <td className="px-4 py-3"><Badge tone={STATUS_TONE[r.boardStatus] ?? "gray"}>{statusLabel[r.boardStatus] ?? r.boardStatus}</Badge>{r.leaveType && <div className="text-xs text-muted-foreground mt-1">{r.leaveType}</div>}</td>
                        <td className="px-4 py-3 tabular-nums">{r.checkIn ?? "—"}</td>
                        <td className="px-4 py-3 tabular-nums">{r.checkOut ?? (r.checkIn ? <span className="text-muted-foreground">…</span> : "—")}</td>
                        <td className="px-4 py-3 tabular-nums">{r.hoursWorked ?? "—"}</td>
                        <td className="px-4 py-3">
                          <div className="flex flex-wrap gap-1.5">
                            {r.lateMinutes > 0 && <Badge tone="amber"><AlarmClock className="h-3 w-3 me-1" />{r.lateMinutes}m</Badge>}
                            {r.earlyLeaveMinutes > 0 && r.checkOut && <Badge tone="amber"><LogOut className="h-3 w-3 me-1" />{r.earlyLeaveMinutes}m</Badge>}
                            {r.overtimeMinutes > 0 && <Badge tone="blue"><Timer className="h-3 w-3 me-1" />+{r.overtimeMinutes}m</Badge>}
                            {r.outZoneMinutes > 0 && <Badge tone="red"><Footprints className="h-3 w-3 me-1" />{r.outZoneMinutes}m</Badge>}
                            {r.outsideNow && <Badge tone="red">{tr("away now", "خارج الآن")}</Badge>}
                            {r.flags?.includes("missed_checkout") && <Badge tone="red">{tr("no check-out", "بدون انصراف")}</Badge>}
                            {r.securityFlags?.split(",").filter(Boolean).map((f) => (
                              <Badge key={f} tone="amber"><ShieldAlert className="h-3 w-3 me-1" />{({ mock_location: tr("fake location", "موقع مزيّف"), shared_device: tr("shared phone", "هاتف مشترك"), offline_sync: tr("synced offline", "مزامنة بعد انقطاع") } as Record<string, string>)[f] ?? f}</Badge>
                            ))}
                          </div>
                        </td>
                        <td className="px-4 py-3 text-end">
                          {!["on_leave", "off", "holiday"].includes(r.boardStatus) && <button className="p-1.5 text-muted-foreground hover:text-primary" onClick={() => setEdit(r)} title={tr("Edit", "تعديل")}><Pencil className="h-4 w-4" /></button>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {edit && <EditModal row={edit} date={day} onClose={() => setEdit(null)} onSaved={refresh} />}
    </div>
  );
}

function EditModal({ row, date, onClose, onSaved }: { row: Row; date: string; onClose: () => void; onSaved: () => void }) {
  const tr = useTr();
  const [inT, setIn] = useState(row.checkIn ?? "");
  const [outT, setOut] = useState(row.checkOut ?? "");
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);
  async function save() {
    if (!inT && !status) return void toast.error(tr("Enter the check-in time", "أدخل وقت الحضور"));
    setBusy(true);
    try {
      const body: any = { employeeId: row.employeeId, date, checkIn: inT || "", checkOut: outT || "" };
      if (status) body.status = status;
      row.attendanceId ? await api(`/attendance/${row.attendanceId}`, "PUT", body) : await api("/attendance", "POST", body);
      toast.success(tr("Saved", "تم الحفظ"));
      onSaved();
      onClose();
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }
  async function remove() {
    if (!row.attendanceId || !confirm(tr("Delete this record?", "حذف هذا السجل؟"))) return;
    try { await api(`/attendance/${row.attendanceId}`, "DELETE"); onSaved(); onClose(); } catch (e: any) { toast.error(e.message); }
  }
  return (
    <Modal open title={row.employeeName} onClose={onClose}>
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <Field label={tr("Check in", "الحضور")}><input type="time" className={inputCls} value={inT} onChange={(e) => setIn(e.target.value)} /></Field>
          <Field label={tr("Check out", "الانصراف")}><input type="time" className={inputCls} value={outT} onChange={(e) => setOut(e.target.value)} /></Field>
        </div>
        <Field label={tr("Status", "الحالة")} hint={status ? tr("Forced by HR — overrides the automatic result for this day.", "بقرار من الموارد البشرية — يلغي النتيجة التلقائية لهذا اليوم.") : tr("Automatic: worked out from the shift, the times and the location.", "تلقائي: يُحسب من الوردية والأوقات والموقع.")}>
          <select className={inputCls} value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">{tr("Automatic (recommended)", "تلقائي (موصى به)")}</option>
            {["present", "late", "half_day", "absent"].map((s) => <option key={s} value={s}>{tr("Force: ", "فرض: ")}{s.replace("_", " ")}</option>)}
          </select>
        </Field>
        <ExplainPanel date={date} employeeId={row.employeeId} />
        <div className="flex items-center justify-between pt-2">
          {row.attendanceId ? <button className="text-sm text-red-600 inline-flex items-center gap-1" onClick={remove}><Trash2 className="h-4 w-4" />{tr("Delete", "حذف")}</button> : <span />}
          <div className="flex gap-2"><button className={btnGhost} onClick={onClose}>{tr("Cancel", "إلغاء")}</button><button className={btnCls} disabled={busy} onClick={save}>{tr("Save", "حفظ")}</button></div>
        </div>
      </div>
    </Modal>
  );
}

function Monthly({ month, onMonth }: { month: string; onMonth: (m: string) => void }) {
  const tr = useTr();
  const { data, isLoading } = useQuery<{ rows: any[] }>({ queryKey: ["att-month", month], queryFn: () => api(`/reports/attendance?month=${month}`) });
  return (
    <div className="space-y-4">
      <input type="month" className={inputCls + " max-w-[12rem]"} value={month} onChange={(e) => e.target.value && onMonth(e.target.value)} />
      <div className="bg-card rounded-2xl border border-border overflow-x-auto">
        {isLoading ? <Spinner /> : (
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-xs uppercase text-muted-foreground"><tr>{[tr("Employee", "الموظف"), tr("Working days", "أيام العمل"), tr("Present", "حضور"), tr("Late", "تأخير"), tr("Half days", "نصف يوم"), tr("Absent", "غياب"), tr("Leave", "إجازة"), tr("Hours", "ساعات"), tr("Overtime h", "إضافي"), tr("Late min", "دقائق تأخير"), tr("Away min", "دقائق خارج")].map((h) => <th key={h} className="px-3 py-3 text-start font-semibold">{h}</th>)}</tr></thead>
            <tbody>
              {(data?.rows ?? []).map((r) => (
                <tr key={r.employee} className="border-t border-border">
                  <td className="px-3 py-2.5 font-medium">{r.employee}</td><td className="px-3">{r.workdays}</td><td className="px-3 text-emerald-600 font-semibold">{r.present}</td><td className="px-3 text-amber-600">{r.late}</td>
                  <td className="px-3 text-orange-600">{r.halfDay}</td><td className="px-3 text-red-600 font-semibold">{r.absent}</td><td className="px-3 text-blue-600">{r.leave}</td><td className="px-3">{r.hours}</td><td className="px-3">{r.overtimeHours}</td><td className="px-3">{r.lateMinutes}</td><td className="px-3">{r.outZoneMinutes}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
