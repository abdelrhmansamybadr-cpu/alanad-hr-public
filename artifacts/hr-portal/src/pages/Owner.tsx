import { useState } from "react";
import { ShieldCheck, Building2 } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/http";
import { Switch } from "@/components/ui/switch";
import { Badge, Empty, PageHeader, Spinner, btnGhost, cardCls, useTr } from "@/components/kit";
import { camel, useLoad } from "@/lib/premium";
import { useAuth } from "@/contexts/AuthContext";

interface Feature { key: string; titleEn: string; titleAr: string; descEn: string; descAr: string }
interface CompanyRow { id: number; name: string; slug: string; status: string; employeeCount: number; flags: Record<string, boolean> }
interface Overview { mode: "owner" | "super"; features: Feature[]; companies: CompanyRow[] }
interface AuditRow { id: number; companyName: string; featureKey: string; enabled: number | boolean; actorName: string; createdAt: string }

/** The owner's control panel: which company may use which premium feature. Every switch is enforced by the server. */
export default function Owner() {
  const tr = useTr();
  const isAr = tr("a", "b") === "b";
  const { company, refreshCompany } = useAuth();
  const { data, error, loading, reload } = useLoad<Overview>("/owner/features");
  const audit = useLoad<AuditRow[]>("/owner/audit?limit=60");
  const [tab, setTab] = useState<"companies" | "features" | "log">("companies");
  const [busy, setBusy] = useState<string | null>(null);
  const title = (f: Feature) => (isAr ? f.titleAr : f.titleEn);
  const desc = (f: Feature) => (isAr ? f.descAr : f.descEn);

  if (loading && !data) return <Spinner />;
  if (error || !data) return <Empty text={error?.message ?? tr("Not available", "غير متاح")} />;

  const set = async (c: CompanyRow, key: string, on: boolean) => {
    setBusy(`${c.id}:${key}`);
    try {
      await api(`/owner/companies/${c.id}/features`, "PUT", { flags: { [key]: on } });
      await Promise.all([reload(), audit.reload()]);
      if (company?.id === c.id) await refreshCompany();
    } catch (e) { toast.error((e as Error).message); } finally { setBusy(null); }
  };

  const applyAll = async (f: Feature, on: boolean) => {
    if (!window.confirm(on
      ? tr(`Turn on "${title(f)}" in ${data.companies.length} companies?`, `تشغيل «${title(f)}» في ${data.companies.length} شركة؟`)
      : tr(`Turn off "${title(f)}" in ${data.companies.length} companies? It closes at once. Data is kept.`, `إيقاف «${title(f)}» في ${data.companies.length} شركة؟ تُغلق فوراً والبيانات تبقى محفوظة.`))) return;
    try {
      await api("/owner/features/apply", "POST", { key: f.key, enabled: on });
      await Promise.all([reload(), audit.reload(), refreshCompany()]);
      toast.success(tr("Saved", "تم الحفظ"));
    } catch (e) { toast.error((e as Error).message); }
  };

  const tabBtn = (id: typeof tab, label: string) => (
    <button key={id} onClick={() => setTab(id)} className={`px-4 py-2 rounded-xl text-sm font-medium ${tab === id ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:text-foreground"}`}>{label}</button>
  );

  return (
    <div className="space-y-6">
      <PageHeader title={tr("Feature control", "التحكم في الخدمات")} subtitle={data.mode === "owner"
        ? tr("You decide which company can use each feature. Switched off means closed for everybody in that company, on every device. Nothing is deleted.", "أنت تقرر أي شركة تستخدم كل خدمة. الإيقاف يعني إغلاقها للجميع في تلك الشركة وعلى كل الأجهزة. لا يُحذف شيء.")
        : tr("You decide which companies of your group can use each feature. Switched off means closed for everybody there. Nothing is deleted.", "أنت تقرر أي شركات مجموعتك تستخدم كل خدمة. الإيقاف يعني إغلاقها للجميع هناك. لا يُحذف شيء.")}>
        <Badge tone="violet"><ShieldCheck className="h-3.5 w-3.5 me-1" />{data.mode === "owner" ? tr("Owner", "المالك") : tr("Super Admin", "المدير العام")}</Badge>
      </PageHeader>

      <div className="flex gap-2">{tabBtn("companies", tr("Companies", "الشركات"))}{tabBtn("features", tr("Features", "الخدمات"))}{tabBtn("log", tr("Log", "السجل"))}</div>

      {tab === "companies" && (
        data.companies.length === 0 ? <Empty text={tr("No companies to control", "لا توجد شركات للتحكم فيها")} /> :
        <div className="grid gap-4 lg:grid-cols-2">
          {data.companies.map((c) => {
            const on = data.features.filter((f) => c.flags[camel(f.key)]).length;
            return (
              <div key={c.id} className={cardCls}>
                <div className="flex items-center gap-3 mb-4">
                  <div className="h-10 w-10 rounded-xl bg-primary/10 text-primary flex items-center justify-center"><Building2 className="h-5 w-5" /></div>
                  <div className="flex-1">
                    <p className="font-bold">{c.name}</p>
                    <p className="text-xs text-muted-foreground">{tr(`${c.employeeCount} people`, `${c.employeeCount} موظف`)}</p>
                  </div>
                  <Badge tone={on ? "green" : "gray"}>{on}/{data.features.length}</Badge>
                </div>
                <div className="divide-y divide-border">
                  {data.features.map((f) => (
                    <div key={f.key} className="flex items-center gap-3 py-2.5">
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-semibold">{title(f)}</p>
                        <p className="text-xs text-muted-foreground">{desc(f)}</p>
                      </div>
                      <Switch checked={!!c.flags[camel(f.key)]} disabled={busy === `${c.id}:${f.key}`} onCheckedChange={(v) => set(c, f.key, v)} aria-label={title(f)} />
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {tab === "features" && (
        <div className="grid gap-4 lg:grid-cols-2">
          {data.features.map((f) => {
            const on = data.companies.filter((c) => c.flags[camel(f.key)]).length;
            return (
              <div key={f.key} className={cardCls}>
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-bold">{title(f)}</p>
                    <p className="text-sm text-muted-foreground mt-1">{desc(f)}</p>
                  </div>
                  <Badge tone={on === 0 ? "gray" : "green"}>{tr(`${on} of ${data.companies.length} on`, `${on} من ${data.companies.length}`)}</Badge>
                </div>
                <div className="flex gap-2 mt-4">
                  <button className={btnGhost} disabled={on === data.companies.length} onClick={() => applyAll(f, true)}>{tr("Turn on for all", "تشغيل للجميع")}</button>
                  <button className={btnGhost} disabled={on === 0} onClick={() => applyAll(f, false)}>{tr("Turn off for all", "إيقاف للجميع")}</button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {tab === "log" && (
        !audit.data ? <Spinner /> : audit.data.length === 0 ? <Empty text={tr("Nothing was switched yet", "لم يُغيَّر أي مفتاح بعد")} /> :
        <div className={`${cardCls} divide-y divide-border`}>
          {audit.data.map((r) => {
            const f = data.features.find((x) => x.key === r.featureKey);
            const on = r.enabled === true || r.enabled === 1;
            return (
              <div key={r.id} className="flex flex-wrap items-center gap-3 py-2.5 text-sm">
                <Badge tone={on ? "green" : "red"}>{on ? tr("On", "تشغيل") : tr("Off", "إيقاف")}</Badge>
                <span className="font-semibold">{f ? title(f) : r.featureKey}</span>
                <span className="text-muted-foreground">· {r.companyName}</span>
                <span className="text-muted-foreground ms-auto">{r.actorName} · {new Date(r.createdAt.replace(" ", "T") + "Z").toLocaleString(isAr ? "ar" : "en")}</span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
