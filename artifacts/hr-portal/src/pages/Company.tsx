import { useEffect, useState } from "react";
import { Building2, MapPin, Palmtree, PartyPopper, Plus, Trash2, Save, Upload, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";

const bad = (m: string): void => { toast.error(m); };
const token = () => localStorage.getItem("hr-token") ?? "";

async function api<T = any>(path: string, method = "GET", body?: unknown): Promise<T> {
  const r = await fetch(`/api${path}`, {
    method,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token()}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.error || "Request failed");
  return data as T;
}

const MODULES = ["employees", "departments", "leaves", "attendance", "shifts", "payroll", "recruitment", "talent_pool", "reviews", "announcements", "documents", "requests"];
const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
const ZONES = ["Africa/Cairo", "Asia/Riyadh", "Asia/Dubai", "Asia/Kuwait", "Asia/Qatar", "Asia/Bahrain", "Asia/Muscat", "Asia/Amman", "Asia/Beirut", "Africa/Casablanca", "Africa/Tunis", "Africa/Algiers", "Europe/London", "Europe/Paris", "Europe/Istanbul", "America/New_York", "UTC"];
const CURRENCIES = ["EGP", "SAR", "AED", "KWD", "QAR", "BHD", "OMR", "JOD", "USD", "EUR", "GBP"];
const SWATCHES = ["#00617A", "#6366F1", "#8B5CF6", "#EC4899", "#EF4444", "#F97316", "#F59E0B", "#10B981", "#14B8A6", "#0EA5E9", "#3B82F6", "#64748B"];

const input = "w-full px-3 py-2 border border-border rounded-xl bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30";
const card = "bg-card border border-border rounded-2xl p-5 shadow-sm";
const primaryBtn = "inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-primary text-primary-foreground text-sm font-medium hover:opacity-90 disabled:opacity-50";

function Swatches({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex flex-wrap gap-2">
      {SWATCHES.map((c) => (
        <button
          key={c}
          type="button"
          onClick={() => onChange(c)}
          className={`h-8 w-8 rounded-full border-2 ${value.toLowerCase() === c.toLowerCase() ? "border-foreground" : "border-transparent"}`}
          style={{ background: c }}
          aria-label={c}
        />
      ))}
    </div>
  );
}

// ------------------------------------------------------------------ General

function General() {
  const { company, refreshCompany } = useAuth();
  const { isRTL } = useLang();
  const tr = (en: string, ar: string) => (isRTL ? ar : en);
  const [name, setName] = useState(company?.name ?? "");
  const [primary, setPrimary] = useState(company?.primaryColor ?? "#00617A");
  const [accent, setAccent] = useState(company?.accentColor ?? "#C88453");
  const [weekend, setWeekend] = useState<string[]>((company?.weekendDays ?? "fri,sat").split(",").filter(Boolean));
  const [zone, setZone] = useState(company?.timezone ?? "Africa/Cairo");
  const [currency, setCurrency] = useState(company?.currency ?? "EGP");
  const [grace, setGrace] = useState(company?.lateGraceMinutes ?? 15);
  const [modules, setModules] = useState<string[]>(company?.modules ?? MODULES);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!company) return;
    setName(company.name);
    setPrimary(company.primaryColor);
    setAccent(company.accentColor);
  }, [company?.id]);

  const toggle = (list: string[], set: (v: string[]) => void, k: string) => set(list.includes(k) ? list.filter((x) => x !== k) : [...list, k]);

  async function save() {
    setBusy(true);
    try {
      await api("/company", "PUT", {
        name: name.trim(),
        primaryColor: primary,
        accentColor: accent,
        weekendDays: DAYS.filter((d) => weekend.includes(d)),
        timezone: zone,
        currency,
        lateGraceMinutes: grace,
        modules: modules.length === MODULES.length ? null : MODULES.filter((m) => modules.includes(m)),
      });
      await refreshCompany();
      toast.success(tr("Company settings saved", "تم حفظ إعدادات الشركة"));
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function uploadLogo(file: File) {
    const fd = new FormData();
    fd.append("file", file);
    const r = await fetch("/api/company/logo", { method: "POST", headers: { Authorization: `Bearer ${token()}` }, body: fd });
    if (!r.ok) return bad((await r.json().catch(() => ({}))).error || "Upload failed");
    await refreshCompany();
    toast.success(tr("Logo updated", "تم تحديث الشعار"));
  }

  return (
    <div className="space-y-5">
      <div className={card}>
        <h3 className="font-semibold mb-4">{tr("Identity", "الهوية")}</h3>
        <div className="flex items-center gap-4">
          <div className="h-20 w-20 rounded-2xl bg-primary/10 flex items-center justify-center overflow-hidden text-primary">
            {company?.logoUrl ? <img src={company.logoUrl} alt="" className="h-full w-full object-cover" /> : <Building2 className="h-8 w-8" />}
          </div>
          <div className="flex-1 space-y-2">
            <input className={input} value={name} onChange={(e) => setName(e.target.value)} placeholder={tr("Company name", "اسم الشركة")} />
            <label className="inline-flex items-center gap-2 text-sm text-primary cursor-pointer">
              <Upload className="h-4 w-4" />
              {tr("Upload logo", "رفع الشعار")}
              <input type="file" accept="image/*" className="hidden" onChange={(e) => e.target.files?.[0] && uploadLogo(e.target.files[0])} />
            </label>
          </div>
        </div>
      </div>

      <div className={card}>
        <h3 className="font-semibold mb-1">{tr("Brand colors", "ألوان الهوية")}</h3>
        <p className="text-sm text-muted-foreground mb-4">{tr("Applied to the mobile app for all your employees.", "تظهر في تطبيق الجوال لجميع موظفيك.")}</p>
        <div className="grid sm:grid-cols-2 gap-5">
          <div>
            <div className="text-sm font-medium mb-2">{tr("Main color", "اللون الأساسي")}</div>
            <Swatches value={primary} onChange={setPrimary} />
          </div>
          <div>
            <div className="text-sm font-medium mb-2">{tr("Accent color", "اللون الثانوي")}</div>
            <Swatches value={accent} onChange={setAccent} />
          </div>
        </div>
        <div className="mt-4 h-14 rounded-xl flex items-center justify-center text-white font-bold" style={{ background: `linear-gradient(90deg, ${primary}, ${accent})` }}>
          {name || company?.name}
        </div>
      </div>

      <div className={card}>
        <h3 className="font-semibold mb-4">{tr("Work week & regional", "أسبوع العمل والإعدادات الإقليمية")}</h3>
        <div className="text-sm font-medium mb-2">{tr("Weekend days", "أيام الإجازة الأسبوعية")}</div>
        <div className="flex flex-wrap gap-2 mb-5">
          {DAYS.map((d) => (
            <button
              key={d}
              type="button"
              onClick={() => toggle(weekend, setWeekend, d)}
              className={`px-3 py-1.5 rounded-full text-xs font-semibold uppercase ${weekend.includes(d) ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}
            >
              {d}
            </button>
          ))}
        </div>
        <div className="grid sm:grid-cols-3 gap-4">
          <label className="text-sm">
            <span className="block mb-1 font-medium">{tr("Time zone", "المنطقة الزمنية")}</span>
            <select className={input} value={zone} onChange={(e) => setZone(e.target.value)}>
              {ZONES.map((z) => <option key={z}>{z}</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className="block mb-1 font-medium">{tr("Currency", "العملة")}</span>
            <select className={input} value={currency} onChange={(e) => setCurrency(e.target.value)}>
              {CURRENCIES.map((c) => <option key={c}>{c}</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className="block mb-1 font-medium">{tr("Late grace (minutes)", "مهلة التأخير (دقائق)")}</span>
            <input type="number" min={0} max={240} className={input} value={grace} onChange={(e) => setGrace(Math.max(0, Math.min(240, Number(e.target.value) || 0)))} />
          </label>
        </div>
      </div>

      <div className={card}>
        <h3 className="font-semibold mb-1">{tr("Features", "الميزات")}</h3>
        <p className="text-sm text-muted-foreground mb-4">{tr("Turn off what your company does not use.", "أوقف ما لا تستخدمه شركتك.")}</p>
        <div className="grid sm:grid-cols-3 gap-2">
          {MODULES.map((m) => (
            <label key={m} className="flex items-center gap-2 text-sm capitalize">
              <input type="checkbox" checked={modules.includes(m)} onChange={() => toggle(modules, setModules, m)} />
              {m.replace("_", " ")}
            </label>
          ))}
        </div>
      </div>

      <button className={primaryBtn} onClick={save} disabled={busy}>
        <Save className="h-4 w-4" />
        {tr("Save changes", "حفظ التغييرات")}
      </button>
    </div>
  );
}

// ------------------------------------------------------------------ Attendance rules

interface Rule {
  id: number;
  name: string;
  isActive: boolean;
  locationEnabled: boolean;
  locationLat: number | null;
  locationLng: number | null;
  locationRadiusKm: number | null;
  wifiEnabled: boolean;
  wifiSsid: string | null;
  wifiBssid?: string | null;
  matchMode?: string;
}

function Rules() {
  const { isRTL } = useLang();
  const tr = (en: string, ar: string) => (isRTL ? ar : en);
  const [rules, setRules] = useState<Rule[]>([]);
  const [draft, setDraft] = useState<Partial<Rule> | null>(null);

  const load = () => api<Rule[]>("/attendance-rules").then(setRules).catch((e) => toast.error(e.message));
  useEffect(() => { load(); }, []);

  async function save() {
    if (!draft?.name?.trim()) return bad(tr("Name is required", "الاسم مطلوب"));
    const body = {
      name: draft.name.trim(),
      isActive: draft.isActive ?? true,
      locationEnabled: !!draft.locationEnabled,
      locationLat: draft.locationEnabled ? Number(draft.locationLat) : null,
      locationLng: draft.locationEnabled ? Number(draft.locationLng) : null,
      locationRadiusKm: draft.locationEnabled ? (Number(draft.locationRadiusKm) || 0.2) : null,
      wifiEnabled: !!draft.wifiEnabled,
      wifiSsid: draft.wifiEnabled ? draft.wifiSsid ?? "" : null,
      wifiBssid: draft.wifiEnabled ? draft.wifiBssid ?? "" : null,
      matchMode: draft.matchMode === "all" ? "all" : "any",
    };
    if (body.locationEnabled && (!isFinite(body.locationLat as number) || !isFinite(body.locationLng as number))) {
      return bad(tr("Enter the office latitude and longitude", "أدخل خط العرض وخط الطول للمكتب"));
    }
    try {
      draft.id ? await api(`/attendance-rules/${draft.id}`, "PUT", body) : await api("/attendance-rules", "POST", body);
      setDraft(null);
      load();
      toast.success(tr("Saved", "تم الحفظ"));
    } catch (e: any) {
      toast.error(e.message);
    }
  }

  function useHere() {
    navigator.geolocation?.getCurrentPosition(
      (p) => setDraft((d) => ({ ...d, locationLat: +p.coords.latitude.toFixed(6), locationLng: +p.coords.longitude.toFixed(6) })),
      () => toast.error(tr("Could not get your location", "تعذر تحديد موقعك")),
    );
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        {tr("Limit where employees can check in. Add several places (branches) — being inside any one of them is enough. With no active rule they can check in from anywhere.", "حدّد من أين يمكن للموظفين تسجيل الحضور. أضف عدة أماكن (فروع) ويكفي التواجد في أحدها. بدون قاعدة مفعّلة يمكنهم التسجيل من أي مكان.")}
      </p>
      {rules.map((r) => (
        <div key={r.id} className={`${card} flex items-center justify-between`}>
          <div className="flex items-center gap-3">
            <MapPin className={`h-5 w-5 ${r.isActive ? "text-emerald-500" : "text-muted-foreground"}`} />
            <div>
              <div className="font-medium">{r.name}</div>
              <div className="text-xs text-muted-foreground">
                {[r.locationEnabled && `${Math.round((r.locationRadiusKm ?? 0) * 1000)} m`, r.wifiEnabled && `Wi-Fi ${r.wifiSsid}${r.wifiBssid ? " (" + r.wifiBssid + ")" : ""}`, r.locationEnabled && r.wifiEnabled && (r.matchMode === "all" ? tr("both required", "الاثنان معاً") : tr("either one", "أحدهما")), !r.locationEnabled && !r.wifiEnabled && tr("Anywhere", "أي مكان")].filter(Boolean).join(" · ")}
              </div>
            </div>
          </div>
          <div className="flex gap-2">
            <button className="text-sm text-primary" onClick={() => setDraft(r)}>{tr("Edit", "تعديل")}</button>
            <button
              className="text-destructive"
              onClick={async () => {
                if (!confirm(tr("Delete this rule?", "حذف هذه القاعدة؟"))) return;
                await api(`/attendance-rules/${r.id}`, "DELETE").catch((e) => toast.error(e.message));
                load();
              }}
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        </div>
      ))}
      {!draft && (
        <button className={primaryBtn} onClick={() => setDraft({ isActive: true, locationRadiusKm: 0.2 })}>
          <Plus className="h-4 w-4" />
          {tr("Add rule", "إضافة قاعدة")}
        </button>
      )}
      {draft && (
        <div className={`${card} space-y-3`}>
          <input className={input} placeholder={tr("Rule name", "اسم القاعدة")} value={draft.name ?? ""} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={draft.isActive ?? true} onChange={(e) => setDraft({ ...draft, isActive: e.target.checked })} />{tr("Active", "مفعّلة")}</label>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!draft.locationEnabled} onChange={(e) => setDraft({ ...draft, locationEnabled: e.target.checked })} />{tr("Require office location", "اشتراط موقع المكتب")}</label>
          {draft.locationEnabled && (
            <div className="grid sm:grid-cols-3 gap-3">
              <input className={input} placeholder={tr("Latitude", "خط العرض")} value={draft.locationLat ?? ""} onChange={(e) => setDraft({ ...draft, locationLat: e.target.value as any })} />
              <input className={input} placeholder={tr("Longitude", "خط الطول")} value={draft.locationLng ?? ""} onChange={(e) => setDraft({ ...draft, locationLng: e.target.value as any })} />
              <input className={input} placeholder={tr("Radius (m)", "النطاق (م)")} value={draft.locationRadiusKm != null ? Math.round(Number(draft.locationRadiusKm) * 1000) : ""} onChange={(e) => setDraft({ ...draft, locationRadiusKm: (Number(e.target.value) || 0) / 1000 })} />
              <button type="button" className="text-sm text-primary text-start" onClick={useHere}>{tr("Use my current location", "استخدم موقعي الحالي")}</button>
            </div>
          )}
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!draft.wifiEnabled} onChange={(e) => setDraft({ ...draft, wifiEnabled: e.target.checked })} />{tr("Require office Wi-Fi", "اشتراط شبكة واي فاي المكتب")}</label>
          {draft.wifiEnabled && (
            <div className="grid sm:grid-cols-2 gap-3">
              <input className={input} placeholder={tr("Wi-Fi name (SSID)", "اسم الواي فاي (SSID)")} value={draft.wifiSsid ?? ""} onChange={(e) => setDraft({ ...draft, wifiSsid: e.target.value })} />
              <input className={input} placeholder={tr("Router ID / BSSID (optional, stricter)", "معرّف الراوتر / BSSID (اختياري، أشد)")} value={draft.wifiBssid ?? ""} onChange={(e) => setDraft({ ...draft, wifiBssid: e.target.value })} />
            </div>
          )}
          {draft.locationEnabled && draft.wifiEnabled && (
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={draft.matchMode === "all"} onChange={(e) => setDraft({ ...draft, matchMode: e.target.checked ? "all" : "any" })} />{tr("Require BOTH the location and the Wi-Fi (otherwise either one is enough)", "اشتراط الموقع والواي فاي معاً (وإلا يكفي أحدهما)")}</label>
          )}
          <div className="flex gap-2">
            <button className={primaryBtn} onClick={save}>{tr("Save", "حفظ")}</button>
            <button className="px-4 py-2 text-sm" onClick={() => setDraft(null)}>{tr("Cancel", "إلغاء")}</button>
          </div>
        </div>
      )}
    </div>
  );
}

// ------------------------------------------------------------------ Leave types

interface LeaveType { id: number; code: string; name: string; daysPerYear: number; paid: boolean; color: string; isActive: boolean }

function LeaveTypes() {
  const { isRTL } = useLang();
  const tr = (en: string, ar: string) => (isRTL ? ar : en);
  const [items, setItems] = useState<LeaveType[]>([]);
  const [draft, setDraft] = useState<Partial<LeaveType> | null>(null);
  const load = () => api<LeaveType[]>("/leave-types?all=1").then(setItems).catch((e) => toast.error(e.message));
  useEffect(() => { load(); }, []);

  async function save() {
    if (!draft?.name?.trim()) return bad(tr("Name is required", "الاسم مطلوب"));
    const body = { name: draft.name.trim(), daysPerYear: Number(draft.daysPerYear) || 0, paid: draft.paid ?? true, color: draft.color ?? "#00617A", isActive: draft.isActive ?? true };
    try {
      draft.id ? await api(`/leave-types/${draft.id}`, "PUT", body) : await api("/leave-types", "POST", body);
      setDraft(null);
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">{tr("Each type has its own yearly balance for every employee. 0 days means unlimited.", "لكل نوع رصيد سنوي مستقل لكل موظف. 0 تعني غير محدود.")}</p>
      {items.map((t) => (
        <div key={t.id} className={`${card} flex items-center justify-between ${t.isActive ? "" : "opacity-60"}`}>
          <div className="flex items-center gap-3">
            <span className="h-3 w-3 rounded-full" style={{ background: t.color }} />
            <div>
              <div className="font-medium">{t.name}</div>
              <div className="text-xs text-muted-foreground">{t.daysPerYear ? `${t.daysPerYear} ${tr("days / year", "يوم / سنة")}` : tr("Unlimited", "غير محدود")} · {t.paid ? tr("Paid", "مدفوعة") : tr("Unpaid", "غير مدفوعة")}</div>
            </div>
          </div>
          <button className="text-sm text-primary" onClick={() => setDraft(t)}>{tr("Edit", "تعديل")}</button>
        </div>
      ))}
      {!draft && <button className={primaryBtn} onClick={() => setDraft({ paid: true, color: "#00617A", daysPerYear: 0, isActive: true })}><Plus className="h-4 w-4" />{tr("Add leave type", "إضافة نوع إجازة")}</button>}
      {draft && (
        <div className={`${card} space-y-3`}>
          <input className={input} placeholder={tr("Name", "الاسم")} value={draft.name ?? ""} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          <input type="number" min={0} className={input} placeholder={tr("Days per year", "عدد الأيام سنوياً")} value={draft.daysPerYear ?? 0} onChange={(e) => setDraft({ ...draft, daysPerYear: Number(e.target.value) })} />
          <Swatches value={draft.color ?? "#00617A"} onChange={(c) => setDraft({ ...draft, color: c })} />
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={draft.paid ?? true} onChange={(e) => setDraft({ ...draft, paid: e.target.checked })} />{tr("Paid leave", "إجازة مدفوعة")}</label>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={draft.isActive ?? true} onChange={(e) => setDraft({ ...draft, isActive: e.target.checked })} />{tr("Active", "مفعّل")}</label>
          <div className="flex gap-2">
            <button className={primaryBtn} onClick={save}>{tr("Save", "حفظ")}</button>
            <button className="px-4 py-2 text-sm" onClick={() => setDraft(null)}>{tr("Cancel", "إلغاء")}</button>
          </div>
        </div>
      )}
    </div>
  );
}

// ------------------------------------------------------------------ Holidays

interface Holiday { id: number; name: string; date: string }

function Holidays() {
  const { isRTL } = useLang();
  const tr = (en: string, ar: string) => (isRTL ? ar : en);
  const [year, setYear] = useState(new Date().getFullYear());
  const [items, setItems] = useState<Holiday[]>([]);
  const [name, setName] = useState("");
  const [date, setDate] = useState("");
  const load = () => api<Holiday[]>(`/holidays?year=${year}`).then(setItems).catch((e) => toast.error(e.message));
  useEffect(() => { load(); }, [year]);

  async function add() {
    if (!name.trim() || !date) return bad(tr("Enter a name and date", "أدخل الاسم والتاريخ"));
    try {
      await api("/holidays", "POST", { name: name.trim(), date });
      setName("");
      setDate("");
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <button className="px-3 py-1 border border-border rounded-lg" onClick={() => setYear(year - 1)}>‹</button>
        <span className="font-semibold">{year}</span>
        <button className="px-3 py-1 border border-border rounded-lg" onClick={() => setYear(year + 1)}>›</button>
      </div>
      <div className={`${card} flex flex-wrap gap-3`}>
        <input className={`${input} flex-1 min-w-[10rem]`} placeholder={tr("Holiday name", "اسم الإجازة")} value={name} onChange={(e) => setName(e.target.value)} />
        <input type="date" className={`${input} w-auto`} value={date} onChange={(e) => setDate(e.target.value)} />
        <button className={primaryBtn} onClick={add}><Plus className="h-4 w-4" />{tr("Add", "إضافة")}</button>
      </div>
      {items.length === 0 && <p className="text-sm text-muted-foreground">{tr("No holidays for this year yet.", "لا توجد إجازات رسمية لهذه السنة.")}</p>}
      {items.map((h) => (
        <div key={h.id} className={`${card} flex items-center justify-between`}>
          <div>
            <div className="font-medium">{h.name}</div>
            <div className="text-xs text-muted-foreground">{h.date}</div>
          </div>
          <button className="text-destructive" onClick={async () => { await api(`/holidays/${h.id}`, "DELETE").catch((e) => toast.error(e.message)); load(); }}>
            <Trash2 className="h-4 w-4" />
          </button>
        </div>
      ))}
    </div>
  );
}

// ------------------------------------------------------------------ page

export default function Company() {
  const { isRTL } = useLang();
  const { user } = useAuth();
  const tr = (en: string, ar: string) => (isRTL ? ar : en);
  const initialTab = (new URLSearchParams(window.location.search).get("tab") as any) || "general";
  const [tab, setTab] = useState<"general" | "rules" | "automation" | "leave" | "holidays">(initialTab);
  const isAdmin = user?.role === "hr_admin";

  const tabs = [
    { id: "general", label: tr("General & brand", "عام والهوية"), icon: Building2, admin: true },
    { id: "rules", label: tr("Attendance rules", "قواعد الحضور"), icon: MapPin, admin: true },
    { id: "automation", label: tr("Automation", "الأتمتة"), icon: Sparkles, admin: true },
    { id: "leave", label: tr("Leave types", "أنواع الإجازات"), icon: Palmtree, admin: true },
    { id: "holidays", label: tr("Public holidays", "الإجازات الرسمية"), icon: PartyPopper, admin: false },
  ] as const;
  const visible = tabs.filter((t) => isAdmin || !t.admin);
  const active = visible.some((t) => t.id === tab) ? tab : visible[0].id;

  return (
    <div className="max-w-4xl mx-auto space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <div>
        <h1 className="text-2xl font-bold">{tr("Company settings", "إعدادات الشركة")}</h1>
        <p className="text-muted-foreground text-sm">{tr("Branding, work week, attendance rules, leave types and holidays.", "الهوية وأسبوع العمل وقواعد الحضور وأنواع الإجازات والعطلات.")}</p>
      </div>
      <div className="flex flex-wrap gap-2">
        {visible.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium ${active === t.id ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:text-foreground"}`}
          >
            <t.icon className="h-4 w-4" />
            {t.label}
          </button>
        ))}
      </div>
      {active === "general" && <General />}
      {active === "rules" && <Rules />}
      {active === "automation" && <Automation />}
      {active === "leave" && <LeaveTypes />}
      {active === "holidays" && <Holidays />}
    </div>
  );
}


// ------------------------------------------------------------------ Automation

type Cfg = Record<string, any>;
const btnGhostLocal = "inline-flex items-center gap-2 px-4 py-2 rounded-xl border border-border text-sm font-medium hover:bg-muted";

function Num({ label, hint, value, onChange, min = 0, max = 100000, step = 1, suffix }: { label: string; hint?: string; value: number; onChange: (v: number) => void; min?: number; max?: number; step?: number; suffix?: string }) {
  return (
    <label className="flex items-center justify-between gap-4 py-2">
      <span className="text-sm"><span className="font-medium">{label}</span>{hint && <span className="block text-xs text-muted-foreground">{hint}</span>}</span>
      <span className="flex items-center gap-1.5 shrink-0">
        <input type="number" min={min} max={max} step={step} className={input + " !w-24 text-end"} value={value} onChange={(e) => onChange(Math.max(min, Math.min(max, Number(e.target.value) || 0)))} />
        {suffix && <span className="text-xs text-muted-foreground w-6">{suffix}</span>}
      </span>
    </label>
  );
}
function Money({ label, hint, value, onChange }: { label: string; hint?: string; value: number; onChange: (v: number) => void }) {
  return (
    <label className="flex items-center justify-between gap-4 py-2">
      <span className="text-sm"><span className="font-medium">{label}</span>{hint && <span className="block text-xs text-muted-foreground">{hint}</span>}</span>
      <input type="number" min={0} step="any" className={input + " !w-32 text-end"} value={value || ""} placeholder="0" onChange={(e) => onChange(Math.max(0, Number(e.target.value) || 0))} />
    </label>
  );
}
/** Tax steps, one per line: "5000 0", "10000 10", "- 20" (monthly amount up to, then the rate in %; "-" = everything above). */
function Brackets({ value, onChange, label, hint }: { value: string[]; onChange: (v: string[]) => void; label: string; hint: string }) {
  const toText = (v: string[]) => v.map((b) => { const [u, r] = b.split("|"); return `${u === "" ? "-" : u} ${r ?? 0}`; }).join("\n");
  const [text, setText] = useState(toText(value));
  function change(t: string) {
    setText(t);
    onChange(t.split("\n").filter((l) => /^\s*(-|\*|\d+(\.\d+)?)\s*[ :|]\s*\d+(\.\d+)?\s*$/.test(l)).map((l) => { const [u, r] = l.trim().split(/\s*[ :|]\s*/); return `${u === "-" || u === "*" ? "" : u}|${r}`; }));
  }
  return (
    <label className="block py-2 text-sm"><span className="font-medium">{label}</span><span className="block text-xs text-muted-foreground whitespace-pre-line">{hint}</span>
      <textarea className={input + " mt-1 font-mono"} rows={4} value={text} onChange={(e) => change(e.target.value)} />
    </label>
  );
}
function Sw({ label, hint, value, onChange }: { label: string; hint?: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="flex items-center justify-between gap-4 py-2 cursor-pointer">
      <span className="text-sm"><span className="font-medium">{label}</span>{hint && <span className="block text-xs text-muted-foreground">{hint}</span>}</span>
      <input type="checkbox" className="h-5 w-5" checked={value} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}
function Sel({ label, value, options, onChange }: { label: string; value: string; options: [string, string][]; onChange: (v: string) => void }) {
  return (
    <label className="flex items-center justify-between gap-4 py-2">
      <span className="text-sm font-medium">{label}</span>
      <select className={input + " !w-auto"} value={value} onChange={(e) => onChange(e.target.value)}>{options.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
    </label>
  );
}
function Group({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return <div className={card}><h3 className="font-semibold">{title}</h3>{hint && <p className="text-xs text-muted-foreground mb-2">{hint}</p>}<div className="divide-y divide-border/50">{children}</div></div>;
}

function Automation() {
  const { company, refreshCompany } = useAuth();
  const { isRTL } = useLang();
  const tr = (en: string, ar: string) => (isRTL ? ar : en);
  const [sub, setSub] = useState<"attendance" | "rewards" | "payroll">("attendance");
  const [att, setAtt] = useState<Cfg>({ ...((company as any)?.attendancePolicy ?? {}) });
  const [pts, setPts] = useState<Cfg>({ ...((company as any)?.pointsConfig ?? {}) });
  const [pay, setPay] = useState<Cfg>({ ...((company as any)?.payrollPolicy ?? {}) });
  const [busy, setBusy] = useState(false);
  const upA = (k: string, v: any) => setAtt((o) => ({ ...o, [k]: v }));
  const upP = (k: string, v: any) => setPts((o) => ({ ...o, [k]: v }));
  const upY = (k: string, v: any) => setPay((o) => ({ ...o, [k]: v }));

  async function save() {
    setBusy(true);
    try {
      const key = { attendance: "attendancePolicy", rewards: "pointsConfig", payroll: "payrollPolicy" }[sub];
      await api("/company", "PUT", { [key]: { attendance: att, rewards: pts, payroll: pay }[sub] });
      await refreshCompany();
      toast.success(tr("Rules saved", "تم حفظ القواعد"));
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }
  async function testEmail() {
    try {
      const r: any = await api("/company/test-email", "POST", {});
      r.emailed ? toast.success(tr(`Test e-mail sent to ${r.to}`, `تم إرسال رسالة تجريبية إلى ${r.to}`)) : toast.error(tr("The server could not send e-mail. Invitations can still be shared as a code.", "تعذر على الخادم إرسال البريد. يمكن مشاركة الدعوات كرمز."));
    } catch (e: any) { toast.error(e.message); }
  }
  async function recalc() {
    if (!confirm(tr("Rebuild every employee's automatic points from attendance with the current rules? Manual points and excused days stay.", "إعادة بناء النقاط التلقائية لكل موظف من الحضور بالقواعد الحالية؟ النقاط اليدوية والأيام المعفاة تبقى."))) return;
    try { await api("/points/recalculate", "POST", {}); toast.success(tr("Points recalculated", "تمت إعادة حساب النقاط")); } catch (e: any) { toast.error(e.message); }
  }
  const n = (o: Cfg, k: string, d = 0) => (typeof o[k] === "number" ? o[k] : d);
  const b = (o: Cfg, k: string, d = false) => (typeof o[k] === "boolean" ? o[k] : d);
  const s = (o: Cfg, k: string, d = "") => (typeof o[k] === "string" ? o[k] : d);
  const colours: [string, string][] = [["none", tr("None", "بدون")], ["red", tr("Red", "أحمر")], ["black", tr("Black", "أسود")]];

  return (
    <div className="space-y-5">
      <div className="flex gap-2">
        {(["attendance", "rewards", "payroll"] as const).map((k) => (
          <button key={k} onClick={() => setSub(k)} className={`px-4 py-2 rounded-xl text-sm font-medium ${sub === k ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>{{ attendance: tr("Attendance", "الحضور"), rewards: tr("Rewards", "المكافآت"), payroll: tr("Payroll", "الرواتب") }[k]}</button>
        ))}
      </div>

      {sub === "attendance" && (
        <div className="grid lg:grid-cols-2 gap-5">
          <Group title={tr("Company hours", "ساعات الشركة")} hint={tr("Used for employees with no shift.", "تُستخدم للموظفين بدون وردية.")}>
            <div className="grid grid-cols-2 gap-3 py-2"><input type="time" className={input} value={s(att, "defaultStart", "09:00")} onChange={(e) => upA("defaultStart", e.target.value)} /><input type="time" className={input} value={s(att, "defaultEnd", "17:00")} onChange={(e) => upA("defaultEnd", e.target.value)} /></div>
          </Group>
          <Group title={tr("Late arrival", "التأخير عن الحضور")} hint={tr("The grace period before “late” is in General.", "مهلة «التأخير» في تبويب عام.")}>
            <Num label={tr("Half day if later than", "نصف يوم إذا تأخر أكثر من")} hint={tr("0 = off", "0 = إيقاف")} value={n(att, "halfDayLateMinutes", 120)} onChange={(v) => upA("halfDayLateMinutes", v)} max={480} step={15} suffix="m" />
            <Num label={tr("Absent if later than", "غياب إذا تأخر أكثر من")} hint={tr("0 = off", "0 = إيقاف")} value={n(att, "absentLateMinutes", 0)} onChange={(v) => upA("absentLateMinutes", v)} max={600} step={15} suffix="m" />
          </Group>
          <Group title={tr("Leaving and hours", "الانصراف وعدد الساعات")}>
            <Num label={tr("Early-leave allowance", "مهلة الانصراف المبكر")} value={n(att, "earlyLeaveGraceMinutes", 10)} onChange={(v) => upA("earlyLeaveGraceMinutes", v)} max={120} suffix="m" />
            <Num label={tr("Half day if leaving earlier than", "نصف يوم إذا انصرف قبل")} hint={tr("0 = off", "0 = إيقاف")} value={n(att, "halfDayEarlyMinutes", 120)} onChange={(v) => upA("halfDayEarlyMinutes", v)} max={480} step={15} suffix="m" />
            <Num label={tr("Half day if worked less than", "نصف يوم إذا عمل أقل من")} hint={tr("% of the shift (0 = off)", "% من الوردية (0 = إيقاف)")} value={n(att, "halfDayMinHoursPct", 50)} onChange={(v) => upA("halfDayMinHoursPct", v)} max={100} suffix="%" />
            <Num label={tr("Absent if worked less than", "غياب إذا عمل أقل من")} hint={tr("% of the shift (0 = off)", "% من الوردية (0 = إيقاف)")} value={n(att, "absentMinHoursPct", 0)} onChange={(v) => upA("absentMinHoursPct", v)} max={100} suffix="%" />
            <Num label={tr("Overtime starts after", "يبدأ الإضافي بعد")} value={n(att, "overtimeAfterMinutes", 30)} onChange={(v) => upA("overtimeAfterMinutes", v)} max={240} suffix="m" />
          </Group>
          <Group title={tr("Location tracking", "تتبع الموقع")} hint={tr("While checked in, the app checks the employee is still at the workplace and counts the time away.", "أثناء الحضور يتحقق التطبيق أن الموظف في مكان العمل ويحتسب وقت غيابه.")}>
            <Sw label={tr("Check location while checked in", "فحص الموقع أثناء الحضور")} value={b(att, "trackLocation", true)} onChange={(v) => upA("trackLocation", v)} />
            <Num label={tr("Check every", "الفحص كل")} value={n(att, "pingIntervalMinutes", 5)} onChange={(v) => upA("pingIntervalMinutes", v)} min={1} max={30} suffix="m" />
            <Num label={tr("Half day after being away", "نصف يوم بعد الغياب عن العمل")} hint={tr("total minutes outside (0 = off)", "مجموع الدقائق خارج النطاق (0 = إيقاف)")} value={n(att, "outZoneHalfDayMinutes", 120)} onChange={(v) => upA("outZoneHalfDayMinutes", v)} max={480} step={15} suffix="m" />
            <Sw label={tr("Allow check-out away from work", "السماح بالانصراف بعيداً عن العمل")} value={b(att, "allowCheckoutOutside", true)} onChange={(v) => upA("allowCheckoutOutside", v)} />
          </Group>
          <Group title={tr("Trust and offline", "الثقة والعمل بدون اتصال")} hint={tr("Protect attendance from fake locations and shared phones, and let people check in when the signal drops.", "احمِ الحضور من المواقع المزيّفة والهواتف المشتركة، واسمح بتسجيل الحضور عند ضعف الإشارة.")}>
            <Sw label={tr("Block fake locations", "منع المواقع المزيّفة")} hint={tr("Refuse check-in while the phone reports a mock-location app. HR is notified.", "يُرفض الحضور إذا أبلغ الهاتف عن موقع وهمي، ويُنبَّه المسؤول.")} value={b(att, "blockMockLocation", true)} onChange={(v) => upA("blockMockLocation", v)} />
            <Sw label={tr("Block a phone used by two people", "منع هاتف يستخدمه شخصان")} hint={tr("Off: allowed but flagged. On: the second person cannot check in from that phone the same day.", "متوقف: يُسمح به مع تنبيه. مفعّل: لا يستطيع الشخص الثاني تسجيل الحضور من نفس الهاتف في اليوم ذاته.")} value={b(att, "blockSharedDevice", false)} onChange={(v) => upA("blockSharedDevice", v)} />
            <Num label={tr("Offline check-in window", "مهلة الحضور بدون اتصال")} hint={tr("hours; recorded at the time it really happened (0 = off)", "ساعات؛ يُسجَّل بالوقت الذي حدث فيه فعلاً (0 = إيقاف)")} value={n(att, "offlineMaxHours", 12)} onChange={(v) => upA("offlineMaxHours", v)} max={72} suffix="h" />
            <Sw label={tr("Check-in and check-out reminders", "تذكير بالحضور والانصراف")} value={b(att, "reminders", true)} onChange={(v) => upA("reminders", v)} />
          </Group>
          <Group title={tr("Annual leave by years of service", "الإجازة السنوية حسب سنوات الخدمة")} hint={tr("Egypt: 15 days after 6 months, 21 after 1 year, 30 after 10 years of service or from age 50 (Labour Law 12/2003). Confirm the figures with your adviser.", "مصر: 15 يوماً بعد 6 أشهر، 21 بعد سنة، 30 بعد 10 سنوات خدمة أو من سن 50 (قانون العمل 12 لسنة 2003). تأكد من الأرقام مع مستشارك.")}>
            <Sel label={tr("Entitlement", "الاستحقاق")} value={s(att, "leavePreset", "none")} onChange={(v) => upA("leavePreset", v)} options={[["none", tr("Manual (days set per leave type)", "يدوي (الأيام في نوع الإجازة)")], ["egypt", tr("Egypt", "مصر")]]} />
          </Group>
          <Group title={tr("Forgotten check-out", "نسيان تسجيل الانصراف")}>
            <Sel label={tr("When nobody checks out", "عندما لا يسجل أحد انصرافه")} value={s(att, "missedCheckout", "flag")} onChange={(v) => upA("missedCheckout", v)} options={[["flag", tr("Just flag it", "تنبيه فقط")], ["half_day", tr("Half day", "نصف يوم")], ["absent", tr("Absent", "غياب")]]} />
            <Num label={tr("Close the day after", "إغلاق اليوم بعد")} hint={tr("hours after the shift ends", "ساعات بعد نهاية الوردية")} value={n(att, "autoCloseAfterHours", 4)} onChange={(v) => upA("autoCloseAfterHours", v)} min={1} max={24} suffix="h" />
          </Group>
        </div>
      )}

      {sub === "rewards" && (
        <div className="grid lg:grid-cols-2 gap-5">
          <Group title={tr("Reward points", "نقاط المكافآت")} hint={tr("Green for an on-time day, red for a half day, black for an absence.", "أخضر ليوم في الموعد، أحمر لنصف يوم، أسود للغياب.")}>
            <Sw label={tr("Reward points are on", "نقاط المكافآت مفعّلة")} value={b(pts, "enabled", true)} onChange={(v) => upP("enabled", v)} />
            <Sw label={tr("Show the leaderboard to employees", "إظهار الترتيب للموظفين")} value={b(pts, "showLeaderboard", true)} onChange={(v) => upP("showLeaderboard", v)} />
          </Group>
          <Group title={tr("Which colour each day earns", "اللون الذي يكسبه كل يوم")} hint={tr("“None” gives no point but still breaks the green streak.", "«بدون» لا تمنح نقطة لكنها تقطع سلسلة الأخضر.")}>
            <Sel label={tr("Late day", "يوم متأخر")} value={s(pts, "lateColor", "none")} onChange={(v) => upP("lateColor", v)} options={colours.slice(0, 2)} />
            <Sel label={tr("Half day", "نصف يوم")} value={s(pts, "halfDayColor", "red")} onChange={(v) => upP("halfDayColor", v)} options={colours.slice(0, 2)} />
            <Sel label={tr("Absent day", "يوم غياب")} value={s(pts, "absentColor", "black")} onChange={(v) => upP("absentColor", v)} options={colours} />
            <Sel label={tr("Forgot to check out", "نسيان الانصراف")} value={s(pts, "missedCheckoutColor", "none")} onChange={(v) => upP("missedCheckoutColor", v)} options={colours.slice(0, 2)} />
          </Group>
          <Group title={tr("Kudos", "كلمات الشكر")} hint={tr("Recognition from colleagues can earn a green point.", "تقدير الزملاء يمكن أن يمنح نقطة خضراء.")}>
            <Num label={tr("Green point every N kudos", "نقطة خضراء كل N كلمة شكر")} hint={tr("0 = off", "0 = إيقاف")} value={n(pts, "kudosGreenEvery", 5)} onChange={(v) => upP("kudosGreenEvery", v)} max={50} />
          </Group>
          <Group title={tr("Green cancels penalties", "الأخضر يلغي العقوبات")}>
            <Num label={tr("Greens that remove 1 red", "عدد الخضراء لإزالة حمراء")} value={n(pts, "redCost", 2)} onChange={(v) => upP("redCost", v)} min={1} max={30} />
            <Num label={tr("Greens that remove 1 black", "عدد الخضراء لإزالة سوداء")} value={n(pts, "blackCost", 5)} onChange={(v) => upP("blackCost", v)} min={1} max={60} />
            <Sel label={tr("Spend greens first on", "اصرف الخضراء أولاً على")} value={s(pts, "cancelOrder", "black_first")} onChange={(v) => upP("cancelOrder", v)} options={[["black_first", tr("Black first", "السوداء أولاً")], ["red_first", tr("Red first", "الحمراء أولاً")]]} />
          </Group>
          <Group title={tr("Levels", "المستويات")} hint={tr("Every full streak of green days raises the employee one level.", "كل سلسلة كاملة من الأيام الخضراء ترفع الموظف مستوى.")}>
            <Num label={tr("Green days in a row per level", "أيام خضراء متتالية لكل مستوى")} value={n(pts, "streakDays", 30)} onChange={(v) => upP("streakDays", v)} min={3} max={365} />
            <label className="block py-2 text-sm"><span className="font-medium">{tr("Level names (lowest first, comma separated)", "أسماء المستويات (الأدنى أولاً، مفصولة بفواصل)")}</span>
              <input className={input + " mt-1"} value={(Array.isArray(pts.levels) ? pts.levels : []).join(", ")} onChange={(e) => upP("levels", e.target.value.split(",").map((x) => x.trim()).filter(Boolean))} />
            </label>
            <div className="pt-3"><button className={btnGhostLocal} onClick={recalc}>{tr("Recalculate points", "إعادة حساب النقاط")}</button></div>
          </Group>
        </div>
      )}

      {sub === "payroll" && (
        <div className="grid lg:grid-cols-2 gap-5">
          <Group title={tr("Payslips from attendance", "قسائم الراتب من الحضور")} hint={tr("“Generate” in Payroll fills deductions and overtime from each employee's attendance.", "زر «إنشاء» في الرواتب يملأ الخصومات والإضافي من الحضور.")}>
            <Sw label={tr("Use attendance when generating", "استخدم الحضور عند الإنشاء")} value={b(pay, "useAttendance", true)} onChange={(v) => upY("useAttendance", v)} />
            <Sel label={tr("Daily rate = salary divided by", "الأجر اليومي = الراتب ÷")} value={s(pay, "dayDivisor", "working_days")} onChange={(v) => upY("dayDivisor", v)} options={[["working_days", tr("Working days", "أيام العمل")], ["30", tr("30 days", "30 يوماً")]]} />
            <Num label={tr("Hours in a normal day", "ساعات اليوم العادي")} value={n(pay, "shiftHours", 8)} onChange={(v) => upY("shiftHours", v)} min={1} max={16} step={0.5} />
          </Group>
          <Group title={tr("Deductions", "الخصومات")}>
            <Sw label={tr("Deduct absent days", "خصم أيام الغياب")} value={b(pay, "deductAbsent", true)} onChange={(v) => upY("deductAbsent", v)} />
            <Sw label={tr("Deduct unpaid leave", "خصم الإجازة غير المدفوعة")} value={b(pay, "deductUnpaidLeave", true)} onChange={(v) => upY("deductUnpaidLeave", v)} />
            <Num label={tr("Half day deduction", "خصم نصف اليوم")} hint={tr("fraction of a day's pay", "كسر من أجر اليوم")} value={n(pay, "halfDayFraction", 0.5)} onChange={(v) => upY("halfDayFraction", v)} max={1} step={0.25} />
            <Sel label={tr("Late minutes", "دقائق التأخير")} value={s(pay, "lateDeduction", "none")} onChange={(v) => upY("lateDeduction", v)} options={[["none", tr("No deduction", "بدون خصم")], ["hourly", tr("By the hour", "بالساعة")]]} />
          </Group>
          <Group title={tr("Social insurance", "التأمينات الاجتماعية")} hint={tr("The employee's share, taken from the pay. Leave at 0 if you do not use it.", "حصة الموظف وتُخصم من الراتب. اتركها 0 إذا لم تستخدمها.")}>
            <Num label={tr("Employee share", "حصة الموظف")} value={n(pay, "insurancePct", 0)} onChange={(v) => upY("insurancePct", v)} max={30} step={0.5} suffix="%" />
            <Money label={tr("Monthly salary limit", "حد الراتب الشهري")} hint={tr("Insurance is worked out on this much at most. Empty = the whole salary.", "تُحسب التأمينات على هذا المبلغ كحد أقصى. فارغ = كامل الراتب.")} value={n(pay, "insuranceCap", 0)} onChange={(v) => upY("insuranceCap", v)} />
          </Group>
          <Group title={tr("Income tax", "ضريبة الدخل")} hint={tr("Taken from the monthly pay after insurance. Tax rules differ by country and year, so enter the figures your accountant gives you.", "تُخصم من الراتب الشهري بعد التأمينات. تختلف قواعد الضريبة حسب البلد والسنة، فأدخل الأرقام التي يعطيك إياها محاسبك.")}>
            <Sel label={tr("Method", "الطريقة")} value={s(pay, "taxMode", "none")} onChange={(v) => upY("taxMode", v)} options={[["none", tr("Off", "متوقفة")], ["flat", tr("Flat %", "نسبة ثابتة")], ["brackets", tr("Steps", "شرائح")]]} />
            {s(pay, "taxMode", "none") !== "none" && <Money label={tr("Tax-free amount per month", "مبلغ معفى شهرياً")} value={n(pay, "taxMonthlyExemption", 0)} onChange={(v) => upY("taxMonthlyExemption", v)} />}
            {s(pay, "taxMode", "none") === "flat" && <Num label={tr("Tax rate", "نسبة الضريبة")} value={n(pay, "taxFlatPct", 0)} onChange={(v) => upY("taxFlatPct", v)} max={50} step={0.5} suffix="%" />}
            {s(pay, "taxMode", "none") === "brackets" && <Brackets label={tr("Steps", "الشرائح")} hint={tr("One step per line: the monthly amount up to, then the rate in %. Use - for everything above. Example:\n5000 0\n10000 10\n- 20", "شريحة في كل سطر: المبلغ الشهري حتى، ثم النسبة %. استخدم - لكل ما فوق ذلك. مثال:\n5000 0\n10000 10\n- 20")} value={Array.isArray(pay.taxBrackets) ? pay.taxBrackets : []} onChange={(v) => upY("taxBrackets", v)} />}
          </Group>
          <Group title={tr("Additions", "الإضافات")}>
            <Sw label={tr("Pay overtime", "دفع الإضافي")} value={b(pay, "overtimeEnabled", true)} onChange={(v) => upY("overtimeEnabled", v)} />
            <Num label={tr("Overtime rate", "معدل الإضافي")} value={n(pay, "overtimeMultiplier", 1.5)} onChange={(v) => upY("overtimeMultiplier", v)} min={1} max={4} step={0.25} suffix="×" />
            <Num label={tr("Perfect attendance bonus", "مكافأة الحضور الكامل")} hint={tr("paid when no absence, late or half day in the month (0 = off)", "تُدفع عند عدم وجود غياب أو تأخير أو نصف يوم في الشهر (0 = إيقاف)")} value={n(pay, "perfectAttendanceBonus", 0)} onChange={(v) => upY("perfectAttendanceBonus", v)} step={50} />
          </Group>
        </div>
      )}

      <div className="flex flex-wrap gap-3">
        <button className={primaryBtn} onClick={save} disabled={busy}><Save className="h-4 w-4" />{tr("Save these rules", "حفظ هذه القواعد")}</button>
        <button className={btnGhostLocal} onClick={testEmail}>{tr("Send me a test e-mail", "أرسل لي رسالة تجريبية")}</button>
      </div>
    </div>
  );
}
