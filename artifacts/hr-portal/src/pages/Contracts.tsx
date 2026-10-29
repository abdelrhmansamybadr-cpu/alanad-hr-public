import { useState, useEffect } from "react";
import { Link } from "wouter";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Bell, RefreshCw, Award } from "lucide-react";
import { api } from "@/lib/http";
import { Badge, Empty, Modal, PageHeader, Spinner, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { CONTRACT_TYPES, daysLeft } from "@/components/Contract";

type Settings = { remindDays: number[]; notifyHr: boolean; notifyManager: boolean; notifyEmployee: boolean; emailHr: boolean; remindExpired: boolean };
const DAY_CHOICES = [90, 60, 45, 30, 21, 14, 7, 3, 1, 0];

export default function Contracts() {
  const tr = useTr();
  const qc = useQueryClient();
  const [range, setRange] = useState(90);
  const [renew, setRenew] = useState<any | null>(null);
  const [months, setMonths] = useState("12");
  const [endDate, setEndDate] = useState("");
  const [busy, setBusy] = useState(false);
  const [s, setS] = useState<Settings | null>(null);
  const [savingS, setSavingS] = useState(false);

  const list = useQuery<{ items: any[]; counts: { expired: number; soon: number; upcoming: number } }>({
    queryKey: ["contracts", "expiring", range], queryFn: () => api(`/contracts/expiring?days=${range}`),
  });
  const settings = useQuery<Settings>({ queryKey: ["contracts", "settings"], queryFn: () => api("/contracts/settings") });
  useEffect(() => { if (settings.data && !s) setS(settings.data); }, [settings.data]); // eslint-disable-line

  async function saveSettings() {
    if (!s) return;
    setSavingS(true);
    try { await api("/contracts/settings", "PUT", s); toast.success(tr("Alarm settings saved", "تم حفظ إعدادات التنبيه")); qc.invalidateQueries({ queryKey: ["contracts"] }); }
    catch (e: any) { toast.error(e.message); } finally { setSavingS(false); }
  }

  async function doRenew() {
    if (!renew) return;
    setBusy(true);
    try {
      await api(`/contracts/${renew.id}/renew`, "POST", endDate ? { endDate } : { months: Number(months) });
      toast.success(tr("Contract renewed", "تم تجديد العقد"));
      setRenew(null); setEndDate("");
      qc.invalidateQueries({ queryKey: ["contracts"] }); qc.invalidateQueries({ queryKey: ["employees-all"] });
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }

  const items = list.data?.items ?? [];
  const c = list.data?.counts;
  const toggleDay = (d: number) => s && setS({ ...s, remindDays: s.remindDays.includes(d) ? s.remindDays.filter((x) => x !== d) : [...s.remindDays, d].sort((a, b) => b - a) });
  const typeName = (k: string) => { const t = CONTRACT_TYPES.find((x) => x[0] === k); return t ? tr(t[1], t[2]) : "—"; };

  return (
    <div className="space-y-6">
      <PageHeader title={tr("Contracts", "العقود")} subtitle={tr("See whose contract is ending and decide when the system reminds you.", "تابع العقود التي تنتهي، وحدّد متى ينبهك النظام.")} />

      <div className="grid sm:grid-cols-3 gap-4">
        {[[tr("Already ended", "منتهية"), c?.expired ?? 0, "text-red-600"], [tr("Ending within 30 days", "تنتهي خلال 30 يومًا"), c?.soon ?? 0, "text-amber-600"], [tr("Ending within 90 days", "تنتهي خلال 90 يومًا"), c?.upcoming ?? 0, "text-foreground"]].map(([l, n, cls], i) => (
          <div key={i} className={cardCls}><p className="text-sm text-muted-foreground">{l}</p><p className={`text-3xl font-bold mt-1 ${cls}`}>{n as number}</p></div>
        ))}
      </div>

      <div className={cardCls + " !p-0 overflow-x-auto"}>
        <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-3 border-b border-border">
          <span className="font-semibold">{tr("Contracts that end soon", "العقود التي تنتهي قريبًا")}</span>
          <select className={inputCls + " !w-auto"} value={range} onChange={(e) => setRange(Number(e.target.value))}>
            {[30, 60, 90, 180, 365].map((d) => <option key={d} value={d}>{tr(`Next ${d} days`, `خلال ${d} يومًا`)}</option>)}
          </select>
        </div>
        {list.isLoading ? <Spinner /> : items.length === 0 ? <Empty text={tr("No contract ends in this period.", "لا توجد عقود تنتهي في هذه الفترة.")} /> : (
          <table className="w-full text-sm">
            <thead><tr className="text-xs text-muted-foreground border-b border-border"><th className="px-5 py-2 text-start">{tr("Employee", "الموظف")}</th><th className="px-5 py-2 text-start">{tr("Contract", "العقد")}</th><th className="px-5 py-2 text-start">{tr("Ends", "ينتهي")}</th><th className="px-5 py-2" /></tr></thead>
            <tbody className="divide-y divide-border">
              {items.map((e) => { const d = daysLeft(e.contractEnd); return (
                <tr key={e.id}>
                  <td className="px-5 py-3"><b>{e.firstName} {e.lastName}</b><div className="text-xs text-muted-foreground">{e.position}{e.departmentName ? ` · ${e.departmentName}` : ""}</div></td>
                  <td className="px-5 py-3">{typeName(e.contractType)}<div className="text-xs text-muted-foreground">{String(e.contractStart ?? "").slice(0, 10)} → {String(e.contractEnd).slice(0, 10)}</div></td>
                  <td className="px-5 py-3">{d !== null && d < 0 ? <Badge tone="red">{tr(`Ended ${-d} d ago`, `انتهى منذ ${-d} يوم`)}</Badge> : <Badge tone={d !== null && d <= 30 ? "amber" : "gray"}>{d === 0 ? tr("Today", "اليوم") : tr(`In ${d} d`, `بعد ${d} يوم`)}</Badge>}</td>
                  <td className="px-5 py-3"><div className="flex justify-end gap-2">
                    <button className={btnGhost} onClick={() => { setRenew(e); setMonths("12"); setEndDate(""); }}><RefreshCw className="h-4 w-4" />{tr("Renew", "تجديد")}</button>
                    <Link href={`/certificates?employee=${e.id}`} className={btnGhost}><Award className="h-4 w-4" />{tr("Leaving certificate", "شهادة مغادرة")}</Link>
                  </div></td>
                </tr>
              ); })}
            </tbody>
          </table>
        )}
      </div>

      <div className={cardCls + " space-y-4"}>
        <div className="flex items-center gap-2 font-semibold"><Bell className="h-4 w-4" />{tr("Reminder settings", "إعدادات التذكير")}</div>
        {!s ? <Spinner /> : (
          <>
            <div>
              <p className="text-sm font-medium mb-2">{tr("Remind me this many days before a contract ends:", "ذكّرني قبل انتهاء العقد بهذا العدد من الأيام:")}</p>
              <div className="flex flex-wrap gap-2">
                {DAY_CHOICES.map((d) => (
                  <button key={d} type="button" onClick={() => toggleDay(d)} className={`px-3 py-1.5 rounded-full border text-sm ${s.remindDays.includes(d) ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}>{d === 0 ? tr("On the day", "يوم الانتهاء") : d}</button>
                ))}
              </div>
            </div>
            <div className="grid sm:grid-cols-2 gap-2 text-sm">
              {([["notifyHr", tr("Tell HR in the app", "نبّه الموارد البشرية في التطبيق")], ["notifyManager", tr("Tell the direct manager", "نبّه المدير المباشر")], ["notifyEmployee", tr("Tell the employee", "نبّه الموظف")], ["emailHr", tr("Also e-mail the HR team", "وأرسل بريدًا لفريق الموارد البشرية")], ["remindExpired", tr("Keep reminding weekly after it ended", "كرّر التذكير أسبوعيًا بعد الانتهاء")]] as [keyof Settings, string][]).map(([k, l]) => (
                <label key={k} className="flex items-center gap-2"><input type="checkbox" checked={!!s[k]} onChange={(e) => setS({ ...s, [k]: e.target.checked } as Settings)} />{l}</label>
              ))}
            </div>
            <button className={btnCls} disabled={savingS} onClick={saveSettings}>{savingS ? tr("Saving…", "جارٍ الحفظ…") : tr("Save settings", "حفظ الإعدادات")}</button>
          </>
        )}
      </div>

      <Modal open={!!renew} title={renew ? tr(`Renew the contract of ${renew.firstName} ${renew.lastName}`, `تجديد عقد ${renew.firstName} ${renew.lastName}`) : ""} onClose={() => setRenew(null)}>
        <div className="space-y-4 text-sm">
          <p className="text-muted-foreground">{tr("Current end date:", "تاريخ الانتهاء الحالي:")} <b>{String(renew?.contractEnd ?? "").slice(0, 10)}</b></p>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">{tr("Extend by", "تمديد لمدة")}</label>
            <select className={inputCls} value={months} onChange={(e) => { setMonths(e.target.value); setEndDate(""); }}>
              {[3, 6, 12, 24, 36].map((m) => <option key={m} value={m}>{m} {tr("months", "أشهر")}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">{tr("…or set the new end date", "…أو حدّد تاريخ الانتهاء الجديد")}</label>
            <input type="date" className={inputCls} value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="flex justify-end gap-2"><button className={btnGhost} onClick={() => setRenew(null)}>{tr("Cancel", "إلغاء")}</button><button className={btnCls} disabled={busy} onClick={doRenew}>{tr("Renew", "تجديد")}</button></div>
        </div>
      </Modal>
    </div>
  );
}
