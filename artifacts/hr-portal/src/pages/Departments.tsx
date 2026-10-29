import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Users2, FolderGit2, Star, UserPlus, UserMinus, Trash2, Pencil, Share2, ArrowRightLeft } from "lucide-react";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { api } from "@/lib/http";
import { Badge, Field, Modal, PageHeader, Spinner, Empty, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { useLang } from "@/contexts/LanguageContext";
import { DepartmentInput, PositionInput, confirmNewTitle } from "@/components/Suggest";
import { ShareDialog } from "@/components/ShareDialog";
import { TransferDialog } from "@/components/TransferDialog";

interface Dept {
  id: number;
  name: string;
  description?: string | null;
  headEmployeeId?: number | null;
  headName?: string | null;
  headPosition?: string | null;
  employeeCount: number;
  members?: Member[];
  companyId?: number;
  shared?: boolean; // shared into this company by another one (read-only here)
  sharedFrom?: string;
  sharedCount?: number;
}
interface Member { id: number; firstName: string; lastName: string; position?: string | null; email?: string; status?: string; departmentId?: number | null; departmentName?: string | null; shared?: boolean; companyName?: string }

const initials = (a: string, b = "") => `${a[0] ?? ""}${b[0] ?? ""}`.toUpperCase();

export default function Departments() {
  const tr = useTr();
  const { isRTL } = useLang();
  const qc = useQueryClient();
  const { data: departments = [], isLoading } = useQuery<Dept[]>({ queryKey: ["departments"], queryFn: () => api("/departments") });
  const [editing, setEditing] = useState<Partial<Dept> | null>(null);
  const [openId, setOpenId] = useState<number | null>(null);

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["departments"] });
    qc.invalidateQueries({ queryKey: ["department"] });
    qc.invalidateQueries({ queryKey: ["/api/departments"] });
    qc.invalidateQueries({ queryKey: ["/api/employees"] });
  };

  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Departments", "الأقسام")} subtitle={tr("Organise your company, choose each head and manage the people in every department.", "نظّم شركتك، اختر رئيس كل قسم وأدِر الأشخاص في كل قسم.")}>
        <button className={btnCls} onClick={() => setEditing({})} data-testid="button-add-department"><Plus className="h-4 w-4" />{tr("Add department", "إضافة قسم")}</button>
      </PageHeader>

      {isLoading ? <Spinner /> : departments.length === 0 ? <Empty text={tr("No departments yet.", "لا توجد أقسام بعد.")} /> : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {departments.map((d, i) => (
            <motion.button
              key={d.id}
              initial={{ opacity: 0, scale: 0.97 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: i * 0.05 }}
              onClick={() => setOpenId(d.id)}
              className={`${cardCls} text-start hover:shadow-md transition-shadow relative overflow-hidden`}
            >
              <div className="p-3 bg-secondary rounded-xl text-primary w-fit"><FolderGit2 className="h-6 w-6" /></div>
              <h3 className="text-xl font-bold mt-4">{d.name}</h3>
              {d.shared ? <div className="mt-1"><Badge tone="blue">{tr("From", "من")} {d.sharedFrom}</Badge></div> : (d.sharedCount ?? 0) > 0 ? <div className="mt-1"><Badge tone="blue">{tr(`Shared with ${d.sharedCount}`, `مشارك مع ${d.sharedCount}`)}</Badge></div> : null}
              <p className="text-sm text-muted-foreground mt-1 line-clamp-2 min-h-[2.5rem]">{d.description || "—"}</p>
              <div className="mt-5 pt-4 border-t border-border/50 flex items-center justify-between">
                <span className="flex items-center gap-1.5 text-sm text-muted-foreground"><Users2 className="h-4 w-4" /><b className="text-foreground">{d.employeeCount}</b> {tr("people", "أشخاص")}</span>
                {d.headName ? <Badge tone="amber"><Star className="h-3 w-3 me-1" />{d.headName}</Badge> : <Badge>{tr("No head", "بدون رئيس")}</Badge>}
              </div>
            </motion.button>
          ))}
        </div>
      )}

      {editing && <DeptForm dept={editing} onClose={() => setEditing(null)} onSaved={refresh} />}
      {openId !== null && <DeptDetail id={openId} onClose={() => setOpenId(null)} onChanged={refresh} onEdit={(d) => { setOpenId(null); setEditing(d); }} />}
    </div>
  );
}

// ------------------------------------------------------------ create / edit

function DeptForm({ dept, onClose, onSaved }: { dept: Partial<Dept>; onClose: () => void; onSaved: () => void }) {
  const tr = useTr();
  const { data: own = [] } = useQuery<Member[]>({ queryKey: ["employees-all"], queryFn: () => api("/employees") });
  // the head may also be someone another company of the group shares with this one
  const { data: sharedIn = [] } = useQuery<Member[]>({ queryKey: ["employees-shared-in"], queryFn: () => api("/employees/shared-in"), retry: false });
  const employees = [...own, ...sharedIn];
  const [name, setName] = useState(dept.name ?? "");
  const [description, setDescription] = useState(dept.description ?? "");
  const [head, setHead] = useState<string>(dept.headEmployeeId ? String(dept.headEmployeeId) : "");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!name.trim()) return void toast.error(tr("Name is required", "الاسم مطلوب"));
    setBusy(true);
    try {
      const body = { name: name.trim(), description, headId: head ? Number(head) : null };
      dept.id ? await api(`/departments/${dept.id}`, "PUT", body) : await api("/departments", "POST", body);
      toast.success(tr("Saved", "تم الحفظ"));
      onSaved();
      onClose();
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }
  async function remove() {
    if (!dept.id || !confirm(tr("Delete this department? Its people become unassigned.", "حذف هذا القسم؟ سيصبح أعضاؤه بدون قسم."))) return;
    try { await api(`/departments/${dept.id}`, "DELETE"); onSaved(); onClose(); } catch (e: any) { toast.error(e.message); }
  }

  return (
    <Modal open title={dept.id ? tr("Edit department", "تعديل القسم") : tr("New department", "قسم جديد")} onClose={onClose}>
      <div className="space-y-4">
        <Field label={tr("Name", "الاسم")} hint={tr("Pick from the list or type any name — both are saved.", "اختر من القائمة أو اكتب أي اسم — كلاهما يُحفظ.")}><DepartmentInput value={name} onChange={setName} /></Field>
        <Field label={tr("Description", "الوصف")}><textarea rows={2} className={inputCls} value={description} onChange={(e) => setDescription(e.target.value)} /></Field>
        <Field label={tr("Department head", "رئيس القسم")} hint={tr("The head approves their team's leave and requests.", "يوافق الرئيس على إجازات وطلبات فريقه.")}>
          <select className={inputCls} value={head} onChange={(e) => setHead(e.target.value)}>
            <option value="">{tr("No head", "بدون رئيس")}</option>
            {employees.filter((e) => e.status !== "inactive").map((e) => <option key={e.id} value={e.id}>{e.firstName} {e.lastName}{e.position ? ` — ${e.position}` : ""}{(e as any).sharedFrom ? ` (${(e as any).sharedFrom})` : ""}</option>)}
          </select>
        </Field>
        <div className="flex items-center justify-between pt-2">
          {dept.id ? <button className="text-sm text-red-600 inline-flex items-center gap-1" onClick={remove}><Trash2 className="h-4 w-4" />{tr("Delete", "حذف")}</button> : <span />}
          <div className="flex gap-2"><button className={btnGhost} onClick={onClose}>{tr("Cancel", "إلغاء")}</button><button className={btnCls} disabled={busy} onClick={save}>{tr("Save", "حفظ")}</button></div>
        </div>
      </div>
    </Modal>
  );
}

// ------------------------------------------------------------------ detail

function DeptDetail({ id, onClose, onChanged, onEdit }: { id: number; onClose: () => void; onChanged: () => void; onEdit: (d: Dept) => void }) {
  const tr = useTr();
  const { isRTL } = useLang();
  const qc = useQueryClient();
  const { data: d, isLoading } = useQuery<Dept>({ queryKey: ["department", id], queryFn: () => api(`/departments/${id}`) });
  const { data: all = [] } = useQuery<Member[]>({ queryKey: ["employees-all"], queryFn: () => api("/employees") });
  const [sharing, setSharing] = useState(false);
  const [transferring, setTransferring] = useState(false);
  const [adding, setAdding] = useState(false);
  const [picked, setPicked] = useState<number[]>([]);
  const [q, setQ] = useState("");
  const [fresh, setFresh] = useState({ firstName: "", lastName: "", email: "", position: "", salary: "" });
  const [creating, setCreating] = useState(false);
  const [code, setCode] = useState<string | null>(null);

  const reload = () => { qc.invalidateQueries({ queryKey: ["department", id] }); qc.invalidateQueries({ queryKey: ["employees-all"] }); onChanged(); };

  async function setHead(employeeId: number | null) {
    try { await api(`/departments/${id}`, "PUT", { headId: employeeId }); reload(); toast.success(tr("Saved", "تم الحفظ")); } catch (e: any) { toast.error(e.message); }
  }
  async function removeMember(m: Member) {
    if (!confirm(tr(`Remove ${m.firstName} from this department?`, `إزالة ${m.firstName} من هذا القسم؟`))) return;
    try { await api(`/departments/${id}/members/${m.id}`, "DELETE"); reload(); } catch (e: any) { toast.error(e.message); }
  }
  async function addPicked() {
    if (!picked.length) return;
    try { await api(`/departments/${id}/members`, "POST", { employeeIds: picked }); setPicked([]); setAdding(false); reload(); toast.success(tr("Added", "تمت الإضافة")); } catch (e: any) { toast.error(e.message); }
  }
  async function createNew() {
    if (!fresh.firstName.trim() || !fresh.lastName.trim() || !fresh.email.trim()) return void toast.error(tr("Name and email are required", "الاسم والبريد مطلوبان"));
    if (!confirmNewTitle(fresh.position, d?.name ?? "", isRTL, all.filter((x) => x.departmentId === id).map((x) => x.position ?? ""))) return;
    setCreating(true);
    try {
      const e: any = await api("/employees", "POST", { firstName: fresh.firstName.trim(), lastName: fresh.lastName.trim(), email: fresh.email.trim(), position: fresh.position.trim(), salary: fresh.salary ? Number(fresh.salary) : undefined, departmentId: id });
      setCode(e.inviteCode ?? null);
      setFresh({ firstName: "", lastName: "", email: "", position: "", salary: "" });
      reload();
    } catch (err: any) { toast.error(err.message); } finally { setCreating(false); }
  }

  const memberIds = new Set((d?.members ?? []).map((m) => m.id));
  const candidates = all.filter((e) => e.status !== "inactive" && !memberIds.has(e.id) && (!q || `${e.firstName} ${e.lastName} ${e.position ?? ""}`.toLowerCase().includes(q.toLowerCase())));

  return (
    <Modal open title={d?.name ?? "…"} onClose={onClose} wide>
      {isLoading || !d ? <Spinner /> : (
        <div className="space-y-6">
          <div className="flex items-start justify-between gap-3">
            <p className="text-sm text-muted-foreground">{d.description || tr("No description", "بدون وصف")}</p>
            {d.shared ? null : <div className="flex gap-2"><button className={btnGhost} onClick={() => setSharing(true)}><Share2 className="h-4 w-4" />{tr("Share", "مشاركة")}</button><button className={btnGhost} onClick={() => setTransferring(true)}><ArrowRightLeft className="h-4 w-4" />{tr("Move", "نقل")}</button><button className={btnGhost} onClick={() => onEdit(d)}><Pencil className="h-4 w-4" />{tr("Edit", "تعديل")}</button></div>}
          </div>
          {d.shared && <div className="rounded-xl bg-sky-50 text-sky-800 border border-sky-200 p-3 text-sm">{tr(`Shared by ${d.sharedFrom}. You can add your own people to it, but only ${d.sharedFrom} can change it.`, `مشارك من ${d.sharedFrom}. يمكنك إضافة موظفيك إليه، لكن ${d.sharedFrom} فقط تستطيع تعديله.`)}</div>}
          {transferring && <TransferDialog kind="department" id={d.id} name={d.name} onClose={() => setTransferring(false)} onMoved={() => { onChanged(); onClose(); }} />}
          {sharing && <ShareDialog kind="department" id={d.id} name={d.name} onClose={() => setSharing(false)} onSaved={reload} />}

          <div className={cardCls + " flex items-center gap-4"}>
            <div className="h-12 w-12 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center font-bold">{d.headName ? initials(d.headName.split(" ")[0], d.headName.split(" ")[1] ?? "") : <Star className="h-5 w-5" />}</div>
            <div className="flex-1">
              <div className="text-xs uppercase tracking-wide text-muted-foreground">{tr("Department head", "رئيس القسم")}</div>
              <div className="font-bold">{d.headName ?? tr("No head assigned", "لم يُعيَّن رئيس")}</div>
              {d.headPosition && <div className="text-xs text-muted-foreground">{d.headPosition}</div>}
            </div>
            {d.headEmployeeId && !d.shared && <button className={btnGhost} onClick={() => setHead(null)}>{tr("Clear", "إزالة")}</button>}
          </div>

          <div>
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-semibold">{tr("Members", "الأعضاء")} ({d.members?.length ?? 0})</h3>
              <button className={btnCls} onClick={() => { setAdding(!adding); setCode(null); }}><UserPlus className="h-4 w-4" />{tr("Add people", "إضافة أشخاص")}</button>
            </div>

            {adding && (
              <div className="grid md:grid-cols-2 gap-4 mb-4">
                <div className={cardCls + " space-y-3"}>
                  <h4 className="font-medium text-sm">{tr("Existing employees", "موظفون موجودون")}</h4>
                  <input className={inputCls} placeholder={tr("Search…", "بحث…")} value={q} onChange={(e) => setQ(e.target.value)} />
                  <div className="max-h-56 overflow-y-auto space-y-1">
                    {candidates.length === 0 && <p className="text-xs text-muted-foreground">{tr("Nobody to add.", "لا أحد لإضافته.")}</p>}
                    {candidates.map((e) => (
                      <label key={e.id} className="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-muted cursor-pointer text-sm">
                        <input type="checkbox" checked={picked.includes(e.id)} onChange={() => setPicked(picked.includes(e.id) ? picked.filter((x) => x !== e.id) : [...picked, e.id])} />
                        <span className="flex-1">{e.firstName} {e.lastName}<span className="text-xs text-muted-foreground"> · {e.position || "—"}{e.departmentName ? ` · ${e.departmentName}` : ""}</span></span>
                      </label>
                    ))}
                  </div>
                  <button className={btnCls} disabled={!picked.length} onClick={addPicked}>{tr(`Add ${picked.length}`, `إضافة ${picked.length}`)}</button>
                </div>
                <div className={cardCls + " space-y-3"}>
                  <h4 className="font-medium text-sm">{tr("New employee in this department", "موظف جديد في هذا القسم")}</h4>
                  <div className="grid grid-cols-2 gap-2">
                    <input className={inputCls} placeholder={tr("First name", "الاسم الأول")} value={fresh.firstName} onChange={(e) => setFresh({ ...fresh, firstName: e.target.value })} />
                    <input className={inputCls} placeholder={tr("Last name", "اسم العائلة")} value={fresh.lastName} onChange={(e) => setFresh({ ...fresh, lastName: e.target.value })} />
                  </div>
                  <input className={inputCls} placeholder={tr("Work email", "البريد الإلكتروني")} value={fresh.email} onChange={(e) => setFresh({ ...fresh, email: e.target.value })} />
                  <div className="grid grid-cols-2 gap-2">
                    <PositionInput className={inputCls} deptName={d?.name ?? ""} existing={all.filter((x) => x.departmentId === id).map((x) => x.position ?? "")} value={fresh.position} onChange={(v) => setFresh({ ...fresh, position: v })} />
                    <input type="number" className={inputCls} placeholder={tr("Salary", "الراتب")} value={fresh.salary} onChange={(e) => setFresh({ ...fresh, salary: e.target.value })} />
                  </div>
                  <button className={btnCls} disabled={creating} onClick={createNew}>{tr("Create", "إنشاء")}</button>
                  {code && <div className="rounded-xl bg-emerald-50 text-emerald-800 p-3 text-sm">{tr("Invite code", "كود الدعوة")}: <b className="text-lg tracking-widest">{code}</b><div className="text-xs">{tr("Give it to the employee; valid 7 days.", "أعطه للموظف؛ صالح 7 أيام.")}</div></div>}
                </div>
              </div>
            )}

            {(d.members ?? []).length === 0 ? <p className="text-sm text-muted-foreground">{tr("Nobody in this department yet.", "لا أحد في هذا القسم بعد.")}</p> : (
              <div className="grid sm:grid-cols-2 gap-3">
                {(d.members ?? []).map((m) => (
                  <div key={m.id} className="flex items-center gap-3 px-3 py-2.5 rounded-xl border border-border">
                    <div className="h-10 w-10 rounded-full bg-primary/10 text-primary flex items-center justify-center text-sm font-bold">{initials(m.firstName, m.lastName)}</div>
                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-sm truncate">{m.firstName} {m.lastName}{m.id === d.headEmployeeId && <Star className="inline h-3.5 w-3.5 ms-1 text-amber-500" />}</div>
                      <div className="text-xs text-muted-foreground truncate">{m.position || "—"}</div>
                    </div>
                    {m.shared ? <Badge tone="blue">{m.companyName}</Badge> : <>
                      {m.id !== d.headEmployeeId && !d.shared && <button className="text-xs text-primary" onClick={() => setHead(m.id)}>{tr("Make head", "تعيين رئيساً")}</button>}
                      <button className="p-1.5 text-muted-foreground hover:text-red-600" title={tr("Remove", "إزالة")} onClick={() => removeMember(m)}><UserMinus className="h-4 w-4" /></button>
                    </>}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </Modal>
  );
}
