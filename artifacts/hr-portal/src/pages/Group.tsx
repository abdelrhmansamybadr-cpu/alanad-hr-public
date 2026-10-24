import { useEffect, useState } from "react";
import { Building2, KeyRound, LogIn, Pencil, Plus, UserCog, Trash2, PauseCircle, PlayCircle } from "lucide-react";
import { toast } from "sonner";
import { useAuth, type GroupInfo } from "@/contexts/AuthContext";
import { api } from "@/lib/http";
import { Badge, Empty, Field, Modal, PageHeader, Spinner, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { accessLabel } from "@/components/CompanySwitcher";

interface Person { id: number; name: string; email: string; role: string; companyId: number; companyName: string; isSuperAdmin?: number | boolean }
interface Manager { id: number; name: string; email: string; source: "own" | "granted" }
interface Grant { id: number; userId: number; userName: string; userEmail: string; homeCompanyName: string; companyId: number; companyName: string; level: "full" | "custom"; modules: string[] | null; readOnly: boolean }

const MODULES: [string, string, string][] = [
  ["dashboard", "Dashboard", "لوحة المعلومات"], ["employees", "Employees", "الموظفون"], ["departments", "Departments", "الأقسام"],
  ["leaves", "Leave", "الإجازات"], ["attendance", "Attendance", "الحضور"], ["shifts", "Shifts", "الورديات"], ["payroll", "Payroll", "المرتبات"],
  ["recruitment", "Recruitment", "التوظيف"], ["talent_pool", "Talent pool", "بنك المواهب"], ["reviews", "Performance reviews", "تقييم الأداء"],
  ["announcements", "Announcements", "الإعلانات"], ["documents", "Documents", "المستندات"], ["hr_staff", "HR team", "فريق الموارد البشرية"], ["requests", "Requests", "الطلبات"],
];

/** Group management: the companies under the holding and who may work inside which of them (super admin only). */
export default function Group() {
  const { group, company, switchCompany } = useAuth();
  const tr = useTr();
  const [tab, setTab] = useState<"companies" | "access">("companies");
  const [data, setData] = useState<GroupInfo | null>(null);
  const [grants, setGrants] = useState<Grant[]>([]);
  const [people, setPeople] = useState<Person[]>([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState<null | { kind: "company" } | { kind: "rename"; id: number; name: string } | { kind: "ceo"; id: number; name: string } | { kind: "grant" }>(null);

  const load = () => {
    setLoading(true);
    Promise.all([api<GroupInfo>("/group/companies"), api<Grant[]>("/group/access"), api<Person[]>("/group/people")])
      .then(([d, g, p]) => { setData(d); setGrants(Array.isArray(g) ? g : []); setPeople(Array.isArray(p) ? p : []); })
      .catch((e) => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  if (group && !group.isSuperAdmin && !group.isOwner) return <Empty text={tr("Only the owner or the group super admin can manage companies.", "المالك أو المدير العام للمجموعة فقط يستطيع إدارة الشركات.")} />;
  const isOwner = !!group?.isOwner;

  async function setPrivate(id: number, ownerManaged: boolean) {
    try { await api(`/group/companies/${id}`, "PUT", { ownerManaged }); toast.success(tr("Saved", "تم الحفظ")); load(); } catch (e: any) { toast.error(e.message); }
  }

  async function setStatus(id: number, status: "active" | "suspended") {
    if (status === "suspended" && !window.confirm(tr("Nobody in this company can sign in while it is suspended. Continue?", "لا يستطيع أحد في هذه الشركة تسجيل الدخول أثناء إيقافها. هل تريد المتابعة؟"))) return;
    try { await api(`/group/companies/${id}`, "PUT", { status }); toast.success(tr("Saved", "تم الحفظ")); load(); } catch (e: any) { toast.error(e.message); }
  }
  async function revoke(g: Grant) {
    if (!window.confirm(tr(`Take access away from ${g.userName}? They go back to their own company at once.`, `سحب صلاحية ${g.userName}؟ سيعود إلى شركته فورًا.`))) return;
    try { await api(`/group/access/${g.id}`, "DELETE"); toast.success(tr("Access removed", "تم سحب الصلاحية")); load(); } catch (e: any) { toast.error(e.message); }
  }

  return (
    <div className="space-y-6">
      <PageHeader title={tr("Group management", "إدارة المجموعة")}>
        {tab === "companies" ? (
          isOwner ? <button className={btnCls} onClick={() => setModal({ kind: "company" })}><Plus className="h-4 w-4" />{tr("Add company", "إضافة شركة")}</button> : <span />
        ) : (
          <button className={btnCls} onClick={() => setModal({ kind: "grant" })}><KeyRound className="h-4 w-4" />{tr("Give access", "منح صلاحية")}</button>
        )}
      </PageHeader>

      <div className="flex gap-2">
        {(["companies", "access"] as const).map((k) => (
          <button key={k} onClick={() => setTab(k)} className={`px-4 py-2 rounded-xl text-sm font-medium border ${tab === k ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}>
            {k === "companies" ? tr("Companies", "الشركات") : tr("Access to companies", "الوصول إلى الشركات")}
          </button>
        ))}
      </div>

      {loading ? <Spinner /> : tab === "companies" ? (
        <>
          <p className="text-sm text-muted-foreground">{tr("Every company is completely separate: its own departments, employees, attendance and payroll.", "كل شركة منفصلة تمامًا: أقسامها وموظفوها وحضورها ومرتباتها الخاصة.")}</p>
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            {data?.companies.map((c) => (
              <div key={c.id} className={`${cardCls} space-y-3`}>
                <div className="flex items-start gap-3">
                  <div className="h-10 w-10 rounded-xl bg-primary/10 text-primary flex items-center justify-center"><Building2 className="h-5 w-5" /></div>
                  <div className="flex-1 min-w-0">
                    <h3 className="font-bold truncate">{c.name}</h3>
                    <p className="text-xs text-muted-foreground truncate">{c.ceo ? `${tr("CEO", "الرئيس التنفيذي")}: ${c.ceo.name} · ${c.ceo.email}` : tr("No CEO account", "لا يوجد حساب رئيس تنفيذي")}</p>
                    {(c as any).managers?.length > 0 && <p className="text-xs text-muted-foreground">{tr("HR managers", "مديرو الموارد البشرية")}: {((c as any).managers as Manager[]).map((m) => m.name).join("، ")}</p>}
                  </div>
                  {company?.id === c.id ? <Badge tone="green">{tr("Current", "الحالية")}</Badge> : c.status !== "active" ? <Badge tone="red">{tr("Suspended", "موقوفة")}</Badge> : c.isHome ? <Badge>{tr("Your company", "شركتك")}</Badge> : null}
                </div>
                <p className="text-sm text-muted-foreground">{c.employeeCount ?? 0} {tr("employees", "موظف")} · {c.departmentCount ?? 0} {tr("departments", "قسم")}{(c as any).ownerManaged ? <> · <Badge tone="violet">{tr("Kept by the owner", "بيد المالك")}</Badge></> : null}</p>
                <div className="flex flex-wrap gap-2">
                  {c.status === "active" && company?.id !== c.id && <button className={btnGhost} onClick={() => switchCompany(c.id).catch((e) => toast.error(e.message))}><LogIn className="h-4 w-4" />{tr("Enter", "دخول")}</button>}
                  <button className={btnGhost} onClick={() => setModal({ kind: "rename", id: c.id, name: c.name })}><Pencil className="h-4 w-4" />{tr("Rename", "تغيير الاسم")}</button>
                  <button className={btnGhost} onClick={() => setModal({ kind: "ceo", id: c.id, name: c.name })}><UserCog className="h-4 w-4" />{tr("New HR account", "حساب موارد بشرية جديد")}</button>
                  <button className={btnGhost} onClick={() => setTab("access")}><KeyRound className="h-4 w-4" />{tr("Who manages it", "من يديرها")}</button>
                  {isOwner && !c.isHome && <button className={btnGhost} onClick={() => setPrivate(c.id, !(c as any).ownerManaged)}>{(c as any).ownerManaged ? tr("Show to Super Admin", "إظهارها للمدير العام") : tr("Keep for me only", "إبقاؤها لي فقط")}</button>}
                  {!c.isHome && (c.status === "active"
                    ? <button className={btnGhost} onClick={() => setStatus(c.id, "suspended")}><PauseCircle className="h-4 w-4" />{tr("Suspend", "إيقاف")}</button>
                    : <button className={btnGhost} onClick={() => setStatus(c.id, "active")}><PlayCircle className="h-4 w-4" />{tr("Activate", "تفعيل")}</button>)}
                </div>
              </div>
            ))}
          </div>
        </>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">{tr("Choose which HR people can work inside which company, and how much they can do.", "اختر من يعمل من فريق الموارد البشرية داخل أي شركة، وما الذي يمكنه فعله.")}</p>
          {grants.length === 0 ? <Empty text={tr("No extra access given yet", "لم تُمنح صلاحيات إضافية بعد")} /> : (
            <div className="space-y-3">
              {grants.map((g) => (
                <div key={g.id} className={`${cardCls} flex flex-wrap items-center gap-3`}>
                  <div className="flex-1 min-w-48">
                    <p className="font-semibold">{g.userName} <span className="text-xs font-normal text-muted-foreground">{g.userEmail}</span></p>
                    <p className="text-sm text-muted-foreground">{g.homeCompanyName} → <b>{g.companyName}</b></p>
                    {g.level === "custom" && <p className="text-xs text-muted-foreground mt-1">{(g.modules ?? []).map((m) => { const x = MODULES.find((y) => y[0] === m); return x ? tr(x[1], x[2]) : m; }).join(" · ")}</p>}
                  </div>
                  <Badge tone={g.level === "full" && !g.readOnly ? "violet" : "blue"}>{accessLabel(tr, g.level, g.readOnly)}</Badge>
                  <button className={btnGhost} onClick={() => revoke(g)}><Trash2 className="h-4 w-4" />{tr("Take away", "سحب")}</button>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      {modal?.kind === "company" && <CompanyModal people={people} onClose={() => setModal(null)} onSaved={() => { setModal(null); load(); }} />}
      {modal?.kind === "rename" && <RenameModal id={modal.id} name={modal.name} onClose={() => setModal(null)} onSaved={() => { setModal(null); load(); }} />}
      {modal?.kind === "ceo" && <CeoModal id={modal.id} name={modal.name} onClose={() => setModal(null)} onSaved={() => { setModal(null); load(); }} />}
      {modal?.kind === "grant" && data && <GrantModal people={people} companies={data.companies.filter((c) => c.status === "active")} onClose={() => setModal(null)} onSaved={() => { setModal(null); load(); }} />}
    </div>
  );
}

function CompanyModal({ people, onClose, onSaved }: { people: Person[]; onClose: () => void; onSaved: () => void }) {
  const tr = useTr();
  const [f, setF] = useState({ name: "", ceoName: "", ceoEmail: "", ceoPassword: "", ceoPhone: "" });
  const [picked, setPicked] = useState<number[]>([]);
  const [busy, setBusy] = useState(false);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });
  const toggle = (id: number) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : [...p, id]));
  const wantsNew = !!(f.ceoName || f.ceoEmail || f.ceoPassword);
  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (wantsNew && !(f.ceoName && f.ceoEmail && f.ceoPassword)) return void toast.error(tr("Fill the name, e-mail and password of the new HR account, or leave all three empty.", "املأ الاسم والبريد وكلمة المرور للحساب الجديد، أو اتركها كلها فارغة."));
    setBusy(true);
    try { await api("/group/companies", "POST", { name: f.name, hrUserIds: picked, ...(wantsNew ? { ...f, ceoPhone: f.ceoPhone || undefined } : {}) }); toast.success(tr("Company created", "تم إنشاء الشركة")); onSaved(); }
    catch (err: any) { toast.error(err.message); }
    finally { setBusy(false); }
  }
  return (
    <Modal open title={tr("Add company", "إضافة شركة")} onClose={onClose}>
      <form onSubmit={save} className="space-y-4">
        <Field label={tr("Company name", "اسم الشركة")}><input required className={inputCls} value={f.name} onChange={set("name")} /></Field>
        <p className="text-sm font-semibold pt-2">{tr("Who runs this company?", "من يدير هذه الشركة؟")}</p>
        <p className="text-xs text-muted-foreground -mt-3">{tr("Only the HR managers you tick (and you) will see this company. Leave all unticked to keep it for yourself and decide later.", "فقط مديرو الموارد البشرية الذين تختارهم (وأنت) سيرون هذه الشركة. اترك الكل بدون اختيار لتبقيها لك وتقرر لاحقًا.")}</p>
        <div className="max-h-48 overflow-auto rounded-xl border border-border divide-y divide-border">
          {people.length === 0 ? <p className="p-3 text-sm text-muted-foreground">{tr("No HR managers yet.", "لا يوجد مديرو موارد بشرية بعد.")}</p> : people.map((p) => (
            <label key={p.id} className="flex items-center gap-3 px-3 py-2 text-sm cursor-pointer hover:bg-muted/50">
              <input type="checkbox" checked={picked.includes(p.id)} onChange={() => toggle(p.id)} />
              <span className="flex-1"><b>{p.name}</b> <span className="text-xs text-muted-foreground">{p.email} · {p.companyName}</span></span>
              {!!p.isSuperAdmin && <Badge tone="violet">{tr("Super Admin", "المدير العام")}</Badge>}
            </label>
          ))}
        </div>
        <p className="text-sm font-semibold pt-2">{tr("Or create a new HR account for it (optional)", "أو أنشئ حساب موارد بشرية جديد لها (اختياري)")}</p>
        <Field label={tr("Name", "الاسم")}><input className={inputCls} value={f.ceoName} onChange={set("ceoName")} /></Field>
        <Field label={tr("E-mail", "البريد الإلكتروني")}><input type="email" autoComplete="off" className={inputCls} value={f.ceoEmail} onChange={set("ceoEmail")} /></Field>
        <Field label={tr("Password", "كلمة المرور")} hint={tr("At least 8 characters", "8 أحرف على الأقل")}><input type="password" autoComplete="new-password" minLength={wantsNew ? 8 : undefined} className={inputCls} value={f.ceoPassword} onChange={set("ceoPassword")} /></Field>
        <Field label={tr("Phone (optional)", "الهاتف (اختياري)")}><input className={inputCls} value={f.ceoPhone} onChange={set("ceoPhone")} /></Field>
        <button className={`${btnCls} w-full`} disabled={busy}>{tr("Save", "حفظ")}</button>
      </form>
    </Modal>
  );
}

function RenameModal({ id, name, onClose, onSaved }: { id: number; name: string; onClose: () => void; onSaved: () => void }) {
  const tr = useTr();
  const [v, setV] = useState(name);
  async function save(e: React.FormEvent) {
    e.preventDefault();
    try { await api(`/group/companies/${id}`, "PUT", { name: v }); toast.success(tr("Saved", "تم الحفظ")); onSaved(); } catch (err: any) { toast.error(err.message); }
  }
  return (
    <Modal open title={tr("Rename company", "تغيير اسم الشركة")} onClose={onClose}>
      <form onSubmit={save} className="space-y-4">
        <Field label={tr("Company name", "اسم الشركة")}><input required className={inputCls} value={v} onChange={(e) => setV(e.target.value)} /></Field>
        <button className={`${btnCls} w-full`}>{tr("Save", "حفظ")}</button>
      </form>
    </Modal>
  );
}

function CeoModal({ id, name, onClose, onSaved }: { id: number; name: string; onClose: () => void; onSaved: () => void }) {
  const tr = useTr();
  const [f, setF] = useState({ name: "", email: "", password: "" });
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });
  async function save(e: React.FormEvent) {
    e.preventDefault();
    try { await api(`/group/companies/${id}/ceo`, "POST", f); toast.success(tr("Saved", "تم الحفظ")); onSaved(); } catch (err: any) { toast.error(err.message); }
  }
  return (
    <Modal open title={`${tr("Set a new CEO", "تعيين رئيس تنفيذي جديد")} — ${name}`} onClose={onClose}>
      <form onSubmit={save} className="space-y-4">
        <Field label={tr("CEO name", "اسم الرئيس التنفيذي")}><input required className={inputCls} value={f.name} onChange={set("name")} /></Field>
        <Field label={tr("CEO e-mail", "بريد الرئيس التنفيذي")}><input required type="email" className={inputCls} value={f.email} onChange={set("email")} /></Field>
        <Field label={tr("CEO password", "كلمة مرور الرئيس التنفيذي")}><input required type="password" minLength={8} className={inputCls} value={f.password} onChange={set("password")} /></Field>
        <button className={`${btnCls} w-full`}>{tr("Save", "حفظ")}</button>
      </form>
    </Modal>
  );
}

function GrantModal({ people, companies, onClose, onSaved }: { people: Person[]; companies: GroupInfo["companies"]; onClose: () => void; onSaved: () => void }) {
  const tr = useTr();
  const [personId, setPersonId] = useState<number | "">("");
  const [companyId, setCompanyId] = useState<number | "">("");
  const [custom, setCustom] = useState(false);
  const [readOnly, setReadOnly] = useState(false);
  const [mods, setMods] = useState<Record<string, boolean>>({ dashboard: true });
  const person = people.find((p) => p.id === personId);
  const targets = companies.filter((c) => c.id !== person?.companyId);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!personId || !companyId) {
      toast.error(tr("Choose a person and a company", "اختر شخصًا وشركة"));
      return;
    }
    try {
      await api("/group/access", "POST", { userId: personId, companyId, level: custom ? "custom" : "full", modules: custom ? MODULES.map((m) => m[0]).filter((m) => mods[m]) : undefined, readOnly });
      toast.success(tr("Access saved", "تم حفظ الصلاحية"));
      onSaved();
    } catch (err: any) { toast.error(err.message); }
  }

  return (
    <Modal open wide title={tr("Give access", "منح صلاحية")} onClose={onClose}>
      <form onSubmit={save} className="space-y-4">
        <Field label={tr("Person", "الشخص")}>
          <select className={inputCls} value={personId} onChange={(e) => { setPersonId(e.target.value ? Number(e.target.value) : ""); setCompanyId(""); }}>
            <option value="">{tr("Choose a person", "اختر شخصًا")}</option>
            {people.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.companyName}</option>)}
          </select>
        </Field>
        <Field label={tr("Company", "الشركة")}>
          <select className={inputCls} value={companyId} onChange={(e) => setCompanyId(e.target.value ? Number(e.target.value) : "")}>
            <option value="">{tr("Choose a company", "اختر شركة")}</option>
            {targets.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </Field>
        <div className="flex gap-2">
          {[false, true].map((v) => (
            <button type="button" key={String(v)} onClick={() => setCustom(v)} className={`flex-1 px-4 py-2 rounded-xl text-sm font-medium border ${custom === v ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}>
              {v ? tr("Chosen parts", "أجزاء محددة") : tr("Full control", "تحكم كامل")}
            </button>
          ))}
        </div>
        <p className="text-xs text-muted-foreground">{custom ? tr("Only the parts you switch on below.", "الأجزاء التي تفعّلها أدناه فقط.") : tr("Works like the admin of that company.", "يعمل مثل مدير تلك الشركة.")}</p>
        {custom && (
          <div className="grid grid-cols-2 gap-2">
            {MODULES.map(([k, en, ar]) => (
              <label key={k} className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={!!mods[k]} onChange={(e) => setMods({ ...mods, [k]: e.target.checked })} />{tr(en, ar)}
              </label>
            ))}
          </div>
        )}
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={readOnly} onChange={(e) => setReadOnly(e.target.checked)} />{tr("Read only (can look, cannot change)", "للقراءة فقط (يشاهد ولا يغيّر)")}
        </label>
        <button className={`${btnCls} w-full`}>{tr("Save", "حفظ")}</button>
      </form>
    </Modal>
  );
}
