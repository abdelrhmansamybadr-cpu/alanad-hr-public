import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { TrendingUp, Trophy, CalendarCheck, LogOut, Rocket, ArrowLeftRight, Wallet, Shuffle } from "lucide-react";
import { api, money, ymd } from "@/lib/http";
import { Badge, Field, Modal, Orb, Spinner, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { useAuth } from "@/contexts/AuthContext";

interface Emp {
  id: number;
  firstName: string;
  lastName: string;
  status: string;
  position?: string | null;
  salary?: number | null;
  departmentId?: number | null;
}

type Tab = "career" | "rewards" | "attendance" | "exit";

/** Everything HR does about one person over time: career changes, reward points, attendance, leaving. */
export function EmployeeHub({ employee, onClose, initialTab = "career" }: { employee: Emp; onClose: () => void; initialTab?: Tab }) {
  const tr = useTr();
  const [tab, setTab] = useState<Tab>(initialTab);
  const tabs: { id: Tab; label: string; icon: any }[] = [
    { id: "career", label: tr("Career", "المسار الوظيفي"), icon: TrendingUp },
    { id: "rewards", label: tr("Rewards", "المكافآت"), icon: Trophy },
    { id: "attendance", label: tr("Attendance", "الحضور"), icon: CalendarCheck },
    { id: "exit", label: employee.status === "inactive" ? tr("Reinstate", "إعادة التفعيل") : tr("Leaving", "إنهاء الخدمة"), icon: LogOut },
  ];
  return (
    <Modal open title={`${employee.firstName} ${employee.lastName}`} onClose={onClose} wide>
      <div className="flex flex-wrap gap-2 mb-5">
        {tabs.map((t) => (
          <button key={t.id} onClick={() => setTab(t.id)} className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium ${tab === t.id ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:text-foreground"}`}>
            <t.icon className="h-4 w-4" />
            {t.label}
          </button>
        ))}
      </div>
      {tab === "career" && <Career employee={employee} />}
      {tab === "rewards" && <Rewards employee={employee} />}
      {tab === "attendance" && <AttendanceTab employee={employee} />}
      {tab === "exit" && <Exit employee={employee} onDone={onClose} />}
    </Modal>
  );
}

// -------------------------------------------------------------------- career

const TYPE_ICON: Record<string, any> = { promotion: Rocket, raise: Wallet, transfer: ArrowLeftRight, demotion: Shuffle };

function Career({ employee }: { employee: Emp }) {
  const tr = useTr();
  const qc = useQueryClient();
  const { company } = useAuth();
  const currency = company?.currency ?? "EGP";
  const { data: list = [], isLoading } = useQuery<any[]>({ queryKey: ["promotions", employee.id], queryFn: () => api(`/employees/${employee.id}/promotions`) });
  const { data: depts = [] } = useQuery<any[]>({ queryKey: ["departments-simple"], queryFn: () => api("/departments") });
  const [form, setForm] = useState({ type: "promotion", position: employee.position ?? "", salary: employee.salary != null ? String(employee.salary) : "", departmentId: String(employee.departmentId ?? ""), effectiveDate: ymd(new Date()), note: "" });
  const [busy, setBusy] = useState(false);

  const label: Record<string, string> = { promotion: tr("Promotion", "ترقية"), raise: tr("Salary raise", "زيادة راتب"), transfer: tr("Transfer", "نقل"), demotion: tr("Role change", "تغيير دور") };

  async function save() {
    const body: any = { type: form.type, effectiveDate: form.effectiveDate, note: form.note || undefined };
    if (form.position.trim() && form.position.trim() !== (employee.position ?? "")) body.position = form.position.trim();
    if (form.salary !== "" && Number(form.salary) !== Number(employee.salary ?? NaN)) body.salary = Number(form.salary);
    if (form.departmentId && Number(form.departmentId) !== Number(employee.departmentId ?? 0)) body.departmentId = Number(form.departmentId);
    if (!body.position && body.salary === undefined && !body.departmentId) return void toast.error(tr("Change the position, salary or department first.", "غيّر المسمى أو الراتب أو القسم أولاً."));
    setBusy(true);
    try {
      await api(`/employees/${employee.id}/promote`, "POST", body);
      toast.success(tr("Career change saved", "تم حفظ التغيير الوظيفي"));
      qc.invalidateQueries({ queryKey: ["promotions", employee.id] });
      qc.invalidateQueries({ queryKey: ["/api/employees"] });
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid md:grid-cols-2 gap-5">
      <div>
        <h3 className="font-semibold mb-3">{tr("History", "السجل")}</h3>
        {isLoading ? <Spinner /> : list.length === 0 ? (
          <p className="text-sm text-muted-foreground">{tr("No career changes yet.", "لا توجد تغييرات وظيفية بعد.")}</p>
        ) : (
          <ol className="relative border-s border-border ms-3 space-y-4">
            {list.map((p) => {
              const Icon = TYPE_ICON[p.type] ?? Rocket;
              return (
                <li key={p.id} className="ms-6">
                  <span className="absolute -start-3 flex h-6 w-6 items-center justify-center rounded-full bg-teal-100 text-teal-600 ring-4 ring-background"><Icon className="h-3.5 w-3.5" /></span>
                  <div className={cardCls + " !p-3"}>
                    <div className="flex items-center justify-between gap-2">
                      <span className="font-semibold text-sm">{label[p.type] ?? p.type}</span>
                      <span className="text-xs text-muted-foreground">{p.effectiveDate}{!p.applied && " · " + tr("scheduled", "مجدولة")}</span>
                    </div>
                    {p.toPosition && <div className="text-sm mt-1">{p.fromPosition || "—"} → <b>{p.toPosition}</b></div>}
                    {p.toDepartmentName && <div className="text-sm">{p.fromDepartmentName || "—"} → <b>{p.toDepartmentName}</b></div>}
                    {p.toSalary != null && <div className="text-sm">{p.fromSalary != null ? money(p.fromSalary, currency) : "—"} → <b>{money(p.toSalary, currency)}</b></div>}
                    {p.note && <div className="text-xs text-muted-foreground mt-1">{p.note}</div>}
                  </div>
                </li>
              );
            })}
          </ol>
        )}
      </div>
      {employee.status !== "inactive" && (
        <div className="space-y-3">
          <h3 className="font-semibold">{tr("New change", "تغيير جديد")}</h3>
          <div className="flex flex-wrap gap-2">
            {Object.keys(label).map((k) => (
              <button key={k} onClick={() => setForm({ ...form, type: k })} className={`px-3 py-1.5 rounded-full text-xs font-semibold ${form.type === k ? "bg-teal-600 text-white" : "bg-muted text-muted-foreground"}`}>{label[k]}</button>
            ))}
          </div>
          <Field label={tr("New position", "المسمى الجديد")}><input className={inputCls} value={form.position} onChange={(e) => setForm({ ...form, position: e.target.value })} /></Field>
          <Field label={`${tr("New salary", "الراتب الجديد")} (${currency})`}><input type="number" min={0} className={inputCls} value={form.salary} onChange={(e) => setForm({ ...form, salary: e.target.value })} /></Field>
          <Field label={tr("Department", "القسم")}>
            <select className={inputCls} value={form.departmentId} onChange={(e) => setForm({ ...form, departmentId: e.target.value })}>
              <option value="">—</option>
              {depts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </Field>
          <Field label={tr("Effective date", "تاريخ السريان")} hint={tr("A future date is applied automatically on that day.", "التاريخ المستقبلي يُطبَّق تلقائياً في يومه.")}><input type="date" className={inputCls} value={form.effectiveDate} onChange={(e) => setForm({ ...form, effectiveDate: e.target.value })} /></Field>
          <Field label={tr("Note", "ملاحظة")}><input className={inputCls} value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></Field>
          <button className={btnCls} disabled={busy} onClick={save}>{tr("Save change", "حفظ التغيير")}</button>
        </div>
      )}
    </div>
  );
}

// ------------------------------------------------------------------- rewards

function Rewards({ employee }: { employee: Emp }) {
  const tr = useTr();
  const qc = useQueryClient();
  const { data: s, isLoading, error } = useQuery<any>({ queryKey: ["points", employee.id], queryFn: () => api(`/points/employee/${employee.id}`) });
  const [note, setNote] = useState("");

  const refresh = () => qc.invalidateQueries({ queryKey: ["points", employee.id] });
  async function give(color: string) {
    try {
      await api("/points/adjust", "POST", { employeeId: employee.id, color, note: note.trim() || undefined });
      setNote("");
      toast.success(tr("Saved", "تم الحفظ"));
      refresh();
    } catch (e: any) { toast.error(e.message); }
  }
  async function toggle(entry: any) {
    try {
      await api(`/points/${entry.id}`, "PUT", { voided: !entry.voided });
      refresh();
    } catch (e: any) { toast.error(e.message); }
  }

  if (isLoading) return <Spinner />;
  if (error || !s) return <p className="text-sm text-muted-foreground">{tr("Reward points are not available for this person (no app account yet, or rewards are off).", "نقاط المكافآت غير متاحة لهذا الشخص (لا يوجد حساب بالتطبيق بعد أو المكافآت متوقفة).")}</p>;
  if (!s.enabled) return <p className="text-sm text-muted-foreground">{tr("Rewards are turned off.", "المكافآت متوقفة.")}</p>;

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-3 gap-4 text-center">
        {(["green", "red", "black"] as const).map((k) => (
          <div key={k} className={cardCls}>
            <div className="flex justify-center"><Orb kind={k} size={44} /></div>
            <div className="text-3xl font-extrabold mt-2">{s.net[k]}</div>
            <div className="text-xs text-muted-foreground capitalize">{k === "green" ? tr("Green", "أخضر") : k === "red" ? tr("Red", "أحمر") : tr("Black", "أسود")}</div>
          </div>
        ))}
      </div>
      <div className={cardCls}>
        <div className="flex flex-wrap items-center gap-3 justify-between">
          <div>
            <div className="font-bold">{tr("Level", "المستوى")} {s.level} · {s.levelName}</div>
            <div className="text-xs text-muted-foreground">{tr("Streak", "السلسلة")}: {s.streak} / {s.streakTarget} · {tr("Best", "الأفضل")} {s.bestStreak}</div>
          </div>
          {(s.cancelled.red > 0 || s.cancelled.black > 0) && <Badge tone="green">{tr(`Greens cancelled ${s.cancelled.red} red, ${s.cancelled.black} black`, `الأخضر ألغى ${s.cancelled.red} أحمر و${s.cancelled.black} أسود`)}</Badge>}
        </div>
        <div className="mt-3 h-2.5 rounded-full bg-muted overflow-hidden"><div className="h-full rounded-full bg-gradient-to-r from-emerald-500 via-yellow-300 to-orange-400" style={{ width: `${Math.min(100, (s.streak / Math.max(1, s.streakTarget)) * 100)}%` }} /></div>
      </div>
      <div className={cardCls}>
        <h3 className="font-semibold mb-2">{tr("Give a point", "منح نقطة")}</h3>
        <div className="flex flex-wrap items-center gap-2">
          <input className={inputCls + " flex-1 min-w-[12rem]"} placeholder={tr("Reason (shown to the employee)", "السبب (يظهر للموظف)")} value={note} onChange={(e) => setNote(e.target.value)} />
          {(["green", "red", "black"] as const).map((k) => (
            <button key={k} className={btnGhost} onClick={() => give(k)}><Orb kind={k} size={16} /> +1</button>
          ))}
        </div>
      </div>
      <div>
        <h3 className="font-semibold mb-2">{tr("Recent days", "آخر الأيام")}</h3>
        <div className="space-y-2 max-h-64 overflow-y-auto">
          {s.history.map((h: any) => (
            <div key={h.id} className={`flex items-center gap-3 px-3 py-2 rounded-xl border border-border ${h.voided ? "opacity-50" : ""}`}>
              {h.color === "none" ? <span className="h-4 w-4 rounded-full bg-muted" /> : <Orb kind={h.color} size={18} />}
              <span className="flex-1 text-sm">{h.source === "manual" ? h.note || tr("Given by HR", "من الموارد البشرية") : h.reason.replace(/_/g, " ")}</span>
              <span className="text-xs text-muted-foreground">{h.date}</span>
              <button className="text-xs text-primary" onClick={() => toggle(h)}>{h.voided ? tr("Restore", "استرجاع") : tr("Excuse", "إعفاء")}</button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- attendance

function AttendanceTab({ employee }: { employee: Emp }) {
  const tr = useTr();
  const [month, setMonth] = useState(ymd(new Date()).slice(0, 7));
  const [y, m] = month.split("-");
  const { data: s, isLoading } = useQuery<any>({ queryKey: ["att-summary", employee.id, month], queryFn: () => api(`/attendance/summary?employeeId=${employee.id}&month=${Number(m)}&year=${y}`) });
  return (
    <div className="space-y-4">
      <input type="month" className={inputCls + " max-w-[12rem]"} value={month} onChange={(e) => setMonth(e.target.value)} />
      {isLoading || !s ? <Spinner /> : (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
            {[
              [tr("Present", "حضور"), s.presentDays + s.lateDays + s.halfDays, "text-emerald-600"],
              [tr("Late", "تأخير"), s.lateDays, "text-amber-600"],
              [tr("Half days", "نصف يوم"), s.halfDays, "text-orange-600"],
              [tr("Absent", "غياب"), s.absentDays, "text-red-600"],
              [tr("On leave", "إجازة"), s.leaveDays, "text-blue-600"],
            ].map(([l, v, c]: any) => (
              <div key={l} className={cardCls + " text-center !p-3"}><div className={`text-2xl font-extrabold ${c}`}>{v}</div><div className="text-xs text-muted-foreground">{l}</div></div>
            ))}
          </div>
          <p className="text-sm text-muted-foreground">{tr("Hours", "ساعات")}: <b>{s.totalHours}</b> · {tr("Late minutes", "دقائق التأخير")}: <b>{s.lateMinutes}</b> · {tr("Overtime", "إضافي")}: <b>{(s.overtimeMinutes / 60).toFixed(1)}h</b> · {tr("Away from work", "خارج العمل")}: <b>{s.outZoneMinutes} m</b></p>
          <div className="grid grid-cols-7 gap-1 text-center text-xs">
            {Object.entries(s.days as Record<string, string>).sort().map(([d, st]) => (
              <div key={d} title={`${d} · ${st}`} className={`rounded-lg py-1.5 font-semibold ${st === "present" ? "bg-emerald-100 text-emerald-700" : st === "late" ? "bg-amber-100 text-amber-700" : st === "half_day" ? "bg-orange-100 text-orange-700" : st === "absent" ? "bg-red-100 text-red-700" : st === "on_leave" ? "bg-blue-100 text-blue-700" : "bg-muted text-muted-foreground"}`}>{Number(d.slice(8))}</div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------- exit

function Exit({ employee, onDone }: { employee: Emp; onDone: () => void }) {
  const tr = useTr();
  const qc = useQueryClient();
  const [date, setDate] = useState(ymd(new Date()));
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => setBusy(false), [employee.id]);

  async function go(kind: "terminate" | "reinstate") {
    if (kind === "terminate" && !confirm(tr("End this person's employment? They are signed out immediately.", "إنهاء خدمة هذا الشخص؟ سيتم تسجيل خروجه فوراً."))) return;
    setBusy(true);
    try {
      await api(`/employees/${employee.id}/${kind}`, "POST", kind === "terminate" ? { date, reason } : {});
      toast.success(kind === "terminate" ? tr("Employment ended", "تم إنهاء الخدمة") : tr("Reinstated", "تمت إعادة التفعيل"));
      qc.invalidateQueries({ queryKey: ["/api/employees"] });
      qc.invalidateQueries({ queryKey: ["departments"] });
      onDone();
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }

  if (employee.status === "inactive") {
    return (
      <div className="space-y-3">
        <p className="text-sm text-muted-foreground">{tr("This person is no longer active. Reinstating lets them sign in again.", "هذا الشخص غير نشط. إعادة التفعيل تتيح له تسجيل الدخول من جديد.")}</p>
        <button className={btnCls} disabled={busy} onClick={() => go("reinstate")}>{tr("Reinstate", "إعادة التفعيل")}</button>
      </div>
    );
  }
  return (
    <div className="space-y-3 max-w-md">
      <p className="text-sm text-muted-foreground">{tr("The employee can no longer sign in. History, attendance and payslips are kept. People they managed move to their manager.", "لا يستطيع الموظف تسجيل الدخول. يبقى سجله وحضوره وقسائمه. ينتقل من كان يديرهم إلى مديره.")}</p>
      <Field label={tr("Last working day", "آخر يوم عمل")}><input type="date" className={inputCls} value={date} onChange={(e) => setDate(e.target.value)} /></Field>
      <Field label={tr("Reason", "السبب")}><textarea rows={3} className={inputCls} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
      <button className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-red-600 text-white text-sm font-medium disabled:opacity-50" disabled={busy} onClick={() => go("terminate")}>{tr("End employment", "إنهاء الخدمة")}</button>
    </div>
  );
}

