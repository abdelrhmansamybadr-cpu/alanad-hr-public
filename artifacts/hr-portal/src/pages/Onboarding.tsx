import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, CheckCircle2, Circle, ListChecks, Pencil, Plus, Rocket, Search, SlidersHorizontal, Trash2, UserPlus, X } from "lucide-react";
import { api } from "@/lib/http";
import { Badge, Empty, Modal, PageHeader, Spinner, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { useLang } from "@/contexts/LanguageContext";

interface Row { employeeId: number; name: string; position?: string | null; departmentName?: string | null; total: number; done: number; nextDue?: string | null; overdue: number }
interface Task { id: number; title: string; description?: string | null; owner: "employee" | "hr"; dueDate?: string | null; done: number | boolean; doneByName?: string | null }
interface View { total: number; done: number; complete: boolean; tasks: Task[] }
interface Tpl { id: number; title: string; description?: string | null; owner: "employee" | "hr"; dueDays: number }
interface Emp { id: number; firstName: string; lastName: string; status: string }

/** The standard steps every company starts with, shown in Arabic when the page is Arabic. */
const AR: Record<string, [string, string]> = {
  "Read and sign your employment contract": ["اقرأ عقد العمل ووقّعه", "راجع التفاصيل وأكّدها مع الموارد البشرية."],
  "Complete your personal details": ["أكمل بياناتك الشخصية", "اطلب من الموارد البشرية تصحيح أي خطأ."],
  "Upload your ID and required documents": ["ارفع بطاقتك والمستندات المطلوبة", "المستندات ← ارفع كل ملف مطلوب."],
  "Set up your work account and equipment": ["جهّز حساب العمل والمعدات", "الحاسوب والبريد وصلاحيات النظام."],
  "Add the employee to payroll": ["أضف الموظف إلى كشف الرواتب", "أكّد الراتب وبيانات البنك."],
  "Meet your manager and team": ["تعرّف على مديرك وفريقك", "تعارف قصير في الأيام الأولى."],
  "Read the company policies": ["اقرأ سياسات الشركة", "الحضور والإجازات وقواعد السلوك."],
  "Turn on notifications and check in once from the app": ["فعّل الإشعارات وسجّل حضورك مرة من التطبيق", "جرّب تسجيل الحضور."],
};

const isDone = (t: Task) => t.done === true || Number(t.done) === 1;
const todayStr = () => new Date().toISOString().slice(0, 10);
const isOverdue = (t: Task) => !isDone(t) && !!t.dueDate && t.dueDate < todayStr();

export default function Onboarding() {
  const tr = useTr();
  const { isRTL } = useLang();
  const qc = useQueryClient();
  const [open, setOpen] = useState<number | null>(null);
  const [tplOpen, setTplOpen] = useState(false);
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState<"all" | "progress" | "overdue" | "complete">("all");
  const [startFor, setStartFor] = useState("");
  const [msg, setMsg] = useState("");

  const title = (t: { title: string }) => (isRTL && AR[t.title] ? AR[t.title][0] : t.title);
  const note = (t: { title: string; description?: string | null }) => (isRTL && AR[t.title] && t.description ? AR[t.title][1] : t.description || "");

  const { data: rows, isLoading } = useQuery<Row[]>({ queryKey: ["onboarding-overview"], queryFn: () => api("/onboarding/overview") });
  const { data: emps } = useQuery<Emp[]>({ queryKey: ["employees-min"], queryFn: () => api("/employees") });
  const { data: view } = useQuery<View>({ queryKey: ["onboarding", open], queryFn: () => api(`/onboarding/employee/${open}`), enabled: open !== null });

  const refresh = () => { qc.invalidateQueries({ queryKey: ["onboarding-overview"] }); qc.invalidateQueries({ queryKey: ["onboarding"] }); };
  const startAll = useMutation({
    mutationFn: () => api<{ started: number }>("/onboarding/start-all", "POST", {}),
    onSuccess: (r) => { setMsg(tr(`Checklist created for ${r.started} employee(s).`, `تم إنشاء قائمة تهيئة لعدد ${r.started} موظف.`)); refresh(); },
  });
  const startOne = useMutation({
    mutationFn: (id: string) => api(`/onboarding/employee/${id}/start`, "POST", {}),
    onSuccess: (_r, id) => { setStartFor(""); refresh(); setOpen(Number(id)); },
  });

  const withList = new Set((rows ?? []).map((r) => r.employeeId));
  const without = (emps ?? []).filter((e) => e.status !== "inactive" && !withList.has(e.id));

  const stats = useMemo(() => {
    const list = rows ?? [];
    return {
      progress: list.filter((r) => r.done < r.total).length,
      overdue: list.filter((r) => Number(r.overdue) > 0).length,
      complete: list.filter((r) => r.total > 0 && r.done === r.total).length,
    };
  }, [rows]);

  const shown = (rows ?? []).filter((r) => {
    if (q && !r.name.toLowerCase().includes(q.toLowerCase())) return false;
    if (filter === "progress") return r.done < r.total;
    if (filter === "overdue") return Number(r.overdue) > 0;
    if (filter === "complete") return r.total > 0 && r.done === r.total;
    return true;
  });
  const current = rows?.find((r) => r.employeeId === open);
  const chip = (k: typeof filter, label: string) => (
    <button key={k} onClick={() => setFilter(k)} className={`px-3 py-1.5 rounded-full text-sm border ${filter === k ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}>{label}</button>
  );

  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Onboarding", "التهيئة الوظيفية")} subtitle={tr("Every new employee gets the company checklist automatically. Follow their progress, tick HR's own steps, and edit anything per person.", "يحصل كل موظف جديد على قائمة الشركة تلقائياً. تابع تقدمه وأنجز خطوات الموارد البشرية وعدّل أي شيء لكل شخص.")}>
        <button className={btnGhost} onClick={() => setTplOpen(true)}><SlidersHorizontal className="h-4 w-4" />{tr("Standard checklist", "القائمة الأساسية")}</button>
        <button className={btnCls} disabled={startAll.isPending} onClick={() => startAll.mutate()}><Rocket className="h-4 w-4" />{tr("Start for everyone without one", "ابدأ لمن ليس لديه قائمة")}</button>
      </PageHeader>

      {msg && <div className="rounded-xl border border-emerald-300 bg-emerald-50 text-emerald-800 px-4 py-2 text-sm flex justify-between"><span>{msg}</span><button onClick={() => setMsg("")} aria-label="close"><X className="h-4 w-4" /></button></div>}

      <div className="grid grid-cols-3 gap-3">
        {[[tr("In progress", "قيد التهيئة"), stats.progress, "text-primary"], [tr("Overdue", "متأخرة"), stats.overdue, "text-red-600"], [tr("Complete", "مكتملة"), stats.complete, "text-emerald-600"]].map(([l, v, c]) => (
          <div key={String(l)} className={cardCls + " text-center"}><div className={`text-3xl font-extrabold ${c}`}>{v as number}</div><div className="text-xs text-muted-foreground mt-1">{l as string}</div></div>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="h-4 w-4 absolute top-1/2 -translate-y-1/2 start-3 text-muted-foreground" />
          <input className={inputCls + " ps-9"} value={q} onChange={(e) => setQ(e.target.value)} placeholder={tr("Search by name", "ابحث بالاسم")} />
        </div>
        {chip("all", tr("All", "الكل"))}{chip("progress", tr("In progress", "قيد التهيئة"))}{chip("overdue", tr("Overdue", "متأخرة"))}{chip("complete", tr("Complete", "مكتملة"))}
      </div>

      {without.length > 0 && (
        <div className={cardCls + " flex flex-wrap items-center gap-2"}>
          <UserPlus className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm">{tr(`${without.length} employee(s) have no checklist:`, `${without.length} موظف بلا قائمة تهيئة:`)}</span>
          <select className={inputCls + " max-w-[240px]"} value={startFor} onChange={(e) => setStartFor(e.target.value)}>
            <option value="">{tr("Choose…", "اختر…")}</option>
            {without.map((e) => <option key={e.id} value={e.id}>{e.firstName} {e.lastName}</option>)}
          </select>
          <button className={btnCls} disabled={!startFor || startOne.isPending} onClick={() => startOne.mutate(startFor)}>{tr("Start checklist", "ابدأ القائمة")}</button>
        </div>
      )}

      {isLoading ? <Spinner /> : !shown.length ? <Empty text={rows?.length ? tr("No one matches this filter.", "لا يوجد من يطابق هذا الفلتر.") : tr("Nobody is onboarding yet. New employees get the checklist automatically.", "لا أحد في التهيئة بعد. يحصل الموظفون الجدد على القائمة تلقائياً.")} /> : (
        <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-4">
          {shown.map((r) => {
            const pct = r.total ? Math.round((r.done / r.total) * 100) : 0;
            return (
              <button key={r.employeeId} onClick={() => setOpen(r.employeeId)} className={cardCls + " text-start hover:border-primary/50 transition"}>
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0"><div className="font-semibold truncate">{r.name}</div><div className="text-xs text-muted-foreground truncate">{r.departmentName || r.position || ""}</div></div>
                  <Badge tone={pct === 100 ? "green" : "amber"}>{r.done}/{r.total}</Badge>
                </div>
                <div className="mt-3 h-2 rounded-full bg-muted overflow-hidden"><div className={`h-full rounded-full ${pct === 100 ? "bg-emerald-500" : "bg-primary"}`} style={{ width: `${pct}%` }} /></div>
                <div className="mt-2 flex items-center gap-2 text-xs text-muted-foreground">
                  {Number(r.overdue) > 0 && <span className="inline-flex items-center gap-1 text-red-600 font-semibold"><AlertTriangle className="h-3.5 w-3.5" />{tr(`${r.overdue} overdue`, `${r.overdue} متأخرة`)}</span>}
                  {pct < 100 && r.nextDue && <span>{tr("Next due", "الموعد القادم")}: <bdi dir="ltr">{r.nextDue}</bdi></span>}
                  {pct === 100 && <span className="text-emerald-600 font-semibold">{tr("Complete", "مكتملة")}</span>}
                </div>
              </button>
            );
          })}
        </div>
      )}

      <Modal open={open !== null} onClose={() => setOpen(null)} title={current ? `${tr("Onboarding", "التهيئة")} — ${current.name}` : tr("Onboarding", "التهيئة")} wide>
        {open !== null && !view ? <Spinner /> : view && open !== null && <Checklist key={open} employeeId={open} view={view} onChanged={refresh} title={title} note={note} />}
      </Modal>

      <TemplateModal open={tplOpen} onClose={() => setTplOpen(false)} title={title} />
    </div>
  );
}

function Checklist({ employeeId, view, onChanged, title, note }: { employeeId: number; view: View; onChanged: () => void; title: (t: { title: string }) => string; note: (t: { title: string; description?: string | null }) => string }) {
  const tr = useTr();
  const [editing, setEditing] = useState<number | null>(null);
  const [form, setForm] = useState({ title: "", description: "", owner: "employee", dueDate: "" });
  const [adding, setAdding] = useState(false);
  const pct = view.total ? Math.round((view.done / view.total) * 100) : 0;

  const toggle = useMutation({ mutationFn: (t: Task) => api(`/onboarding/tasks/${t.id}`, "PUT", { done: !isDone(t) }), onSuccess: onChanged });
  const remove = useMutation({ mutationFn: (id: number) => api(`/onboarding/tasks/${id}`, "DELETE"), onSuccess: onChanged });
  const save = useMutation({
    mutationFn: () => editing !== null
      ? api(`/onboarding/tasks/${editing}`, "PUT", { title: form.title.trim(), description: form.description.trim(), owner: form.owner, dueDate: form.dueDate || null })
      : api(`/onboarding/employee/${employeeId}/tasks`, "POST", { title: form.title.trim(), description: form.description.trim(), owner: form.owner, dueDate: form.dueDate || undefined }),
    onSuccess: () => { setEditing(null); setAdding(false); onChanged(); },
  });
  const begin = (t?: Task) => {
    setForm(t ? { title: t.title, description: t.description || "", owner: t.owner, dueDate: t.dueDate || "" } : { title: "", description: "", owner: "employee", dueDate: "" });
    setEditing(t ? t.id : null);
    setAdding(!t);
  };
  const formUi = (
    <div className="rounded-xl border border-primary/40 bg-primary/5 p-3 space-y-2">
      <input className={inputCls} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder={tr("Task", "المهمة")} />
      <input className={inputCls} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder={tr("Note (optional)", "ملاحظة (اختياري)")} />
      <div className="flex flex-wrap gap-2">
        <select className={inputCls + " flex-1 min-w-[140px]"} value={form.owner} onChange={(e) => setForm({ ...form, owner: e.target.value })}>
          <option value="employee">{tr("Done by the employee", "ينجزها الموظف")}</option>
          <option value="hr">{tr("Done by HR", "تنجزها الموارد البشرية")}</option>
        </select>
        <input type="date" className={inputCls + " flex-1 min-w-[140px]"} value={form.dueDate} onChange={(e) => setForm({ ...form, dueDate: e.target.value })} />
      </div>
      <div className="flex gap-2 justify-end">
        <button className={btnGhost} onClick={() => { setEditing(null); setAdding(false); }}>{tr("Cancel", "إلغاء")}</button>
        <button className={btnCls} disabled={!form.title.trim() || save.isPending} onClick={() => save.mutate()}>{tr("Save", "حفظ")}</button>
      </div>
    </div>
  );

  return (
    <div className="space-y-3">
      <div>
        <div className="flex items-center justify-between text-sm mb-1">
          <span className="inline-flex items-center gap-2 text-muted-foreground"><ListChecks className="h-4 w-4" />{view.done}/{view.total}</span>
          {view.complete ? <Badge tone="green">{tr("Complete", "مكتمل")}</Badge> : <span className="font-semibold">{pct}%</span>}
        </div>
        <div className="h-2 rounded-full bg-muted overflow-hidden"><div className={`h-full rounded-full ${view.complete ? "bg-emerald-500" : "bg-primary"}`} style={{ width: `${pct}%` }} /></div>
      </div>

      <ul className="space-y-2">
        {view.tasks.map((t) => editing === t.id ? <li key={t.id}>{formUi}</li> : (
          <li key={t.id} className={`flex items-start gap-3 rounded-xl border p-3 ${isOverdue(t) ? "border-red-300 bg-red-50/40" : "border-border"}`}>
            <button onClick={() => toggle.mutate(t)} className="mt-0.5" aria-label="toggle">{isDone(t) ? <CheckCircle2 className="h-5 w-5 text-emerald-500" /> : <Circle className="h-5 w-5 text-muted-foreground" />}</button>
            <div className="flex-1 min-w-0">
              <div className={`text-sm font-medium ${isDone(t) ? "line-through text-muted-foreground" : ""}`}>{title(t)}</div>
              {note(t) && <div className="text-xs text-muted-foreground mt-0.5">{note(t)}</div>}
              <div className="flex flex-wrap gap-2 mt-1.5 text-xs items-center">
                <Badge tone={t.owner === "hr" ? "blue" : "violet"}>{t.owner === "hr" ? tr("HR", "الموارد البشرية") : tr("Employee", "الموظف")}</Badge>
                {t.dueDate && !isDone(t) && <span className={isOverdue(t) ? "text-red-600 font-semibold inline-flex items-center gap-1" : "text-muted-foreground"}>{isOverdue(t) && <AlertTriangle className="h-3.5 w-3.5" />}{isOverdue(t) ? tr("Overdue", "متأخرة") + " · " : tr("Due", "الموعد") + " "}<bdi dir="ltr">{t.dueDate}</bdi></span>}
                {isDone(t) && t.doneByName ? <span className="text-emerald-600">{t.doneByName}</span> : null}
              </div>
            </div>
            <button onClick={() => begin(t)} className="text-muted-foreground hover:text-primary" aria-label="edit"><Pencil className="h-4 w-4" /></button>
            <button onClick={() => { if (confirm(tr("Remove this task?", "حذف هذه المهمة؟"))) remove.mutate(t.id); }} className="text-muted-foreground hover:text-red-600" aria-label="delete"><Trash2 className="h-4 w-4" /></button>
          </li>
        ))}
      </ul>

      {adding ? formUi : <button className={btnGhost + " w-full"} onClick={() => begin()}><Plus className="h-4 w-4" />{tr("Add a task", "إضافة مهمة")}</button>}
    </div>
  );
}

function TemplateModal({ open, onClose, title }: { open: boolean; onClose: () => void; title: (t: { title: string }) => string }) {
  const tr = useTr();
  const qc = useQueryClient();
  const { data: tpls } = useQuery<Tpl[]>({ queryKey: ["onboarding-templates"], queryFn: () => api("/onboarding/templates"), enabled: open });
  const [editing, setEditing] = useState<number | null>(null);
  const [form, setForm] = useState({ title: "", owner: "employee", dueDays: 7 });
  const reload = () => qc.invalidateQueries({ queryKey: ["onboarding-templates"] });
  const save = useMutation({
    mutationFn: () => editing ? api(`/onboarding/templates/${editing}`, "PUT", { ...form, title: form.title.trim() }) : api("/onboarding/templates", "POST", { ...form, title: form.title.trim() }),
    onSuccess: () => { setEditing(null); setForm({ title: "", owner: "employee", dueDays: 7 }); reload(); },
  });
  const del = useMutation({ mutationFn: (id: number) => api(`/onboarding/templates/${id}`, "DELETE"), onSuccess: reload });

  return (
    <Modal open={open} onClose={onClose} title={tr("Standard checklist", "القائمة الأساسية")}>
      <p className="text-sm text-muted-foreground mb-3">{tr("These steps are added to every new employee. Changing them does not affect checklists that already exist.", "تُضاف هذه الخطوات لكل موظف جديد. تعديلها لا يغيّر القوائم الموجودة بالفعل.")}</p>
      <ul className="space-y-2 mb-3">
        {(tpls ?? []).map((t) => (
          <li key={t.id} className="flex items-center justify-between gap-3 rounded-xl border border-border px-3 py-2 text-sm">
            <span className="min-w-0 truncate">{title(t)}<span className="text-xs text-muted-foreground"> · {t.owner === "hr" ? tr("HR", "الموارد البشرية") : tr("Employee", "الموظف")} · {t.dueDays} {tr("days", "أيام")}</span></span>
            <span className="flex gap-2 shrink-0">
              <button onClick={() => { setEditing(t.id); setForm({ title: t.title, owner: t.owner, dueDays: t.dueDays }); }} className="text-muted-foreground hover:text-primary" aria-label="edit"><Pencil className="h-4 w-4" /></button>
              <button onClick={() => del.mutate(t.id)} className="text-muted-foreground hover:text-red-600" aria-label="delete"><Trash2 className="h-4 w-4" /></button>
            </span>
          </li>
        ))}
      </ul>
      <div className="rounded-xl border border-border p-3 space-y-2">
        <div className="text-sm font-semibold">{editing ? tr("Edit step", "تعديل الخطوة") : tr("New step", "خطوة جديدة")}</div>
        <input className={inputCls} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder={tr("Step title", "عنوان الخطوة")} />
        <div className="flex gap-2">
          <select className={inputCls} value={form.owner} onChange={(e) => setForm({ ...form, owner: e.target.value })}>
            <option value="employee">{tr("Employee", "الموظف")}</option><option value="hr">{tr("HR", "الموارد البشرية")}</option>
          </select>
          <input type="number" min={0} max={365} className={inputCls + " max-w-[110px]"} value={form.dueDays} onChange={(e) => setForm({ ...form, dueDays: Number(e.target.value) })} title={tr("Days after joining", "أيام بعد الانضمام")} />
        </div>
        <div className="flex gap-2 justify-end">
          {editing && <button className={btnGhost} onClick={() => { setEditing(null); setForm({ title: "", owner: "employee", dueDays: 7 }); }}>{tr("Cancel", "إلغاء")}</button>}
          <button className={btnCls} disabled={!form.title.trim() || save.isPending} onClick={() => save.mutate()}><Plus className="h-4 w-4" />{editing ? tr("Save", "حفظ") : tr("Add", "إضافة")}</button>
        </div>
      </div>
    </Modal>
  );
}
