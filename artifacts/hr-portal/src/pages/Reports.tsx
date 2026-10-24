import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Download, FileSpreadsheet, History } from "lucide-react";
import { toast } from "sonner";
import { api, downloadFile, ymd } from "@/lib/http";
import { Badge, Empty, PageHeader, Spinner, btnCls, cardCls, inputCls, useTr } from "@/components/kit";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";

const ENTITIES = ["", "employee", "attendance", "payroll", "department", "request", "points", "company", "attendance_rule"];

export default function Reports() {
  const tr = useTr();
  const { isRTL } = useLang();
  const { user } = useAuth();
  const [tab, setTab] = useState<"export" | "audit">("export");
  const [month, setMonth] = useState(ymd(new Date()).slice(0, 7));
  const [busy, setBusy] = useState<string | null>(null);
  const year = month.slice(0, 4);
  const last = ymd(new Date(Number(year), Number(month.slice(5)), 0));

  const reports: [string, string, string, string][] = [
    ["attendance", tr("Attendance summary", "ملخص الحضور"), `month=${month}`, `attendance-${month}`],
    ["attendance-daily", tr("Attendance day by day", "الحضور يوماً بيوم"), `from=${month}-01&to=${last}`, `attendance-daily-${month}`],
    ["payroll", tr("Payroll", "الرواتب"), `month=${month}`, `payroll-${month}`],
    ["leaves", tr("Leave requests (year)", "طلبات الإجازة (السنة)"), `year=${year}`, `leaves-${year}`],
    ["employees", tr("Employee list", "قائمة الموظفين"), "", "employees"],
    ["points", tr("Reward points", "نقاط المكافآت"), "", "points"],
  ];

  async function run(id: string, q: string, name: string) {
    setBusy(id);
    try { await downloadFile(`/reports/${id}?${q}${q ? "&" : ""}format=csv`, `${name}.csv`); } catch (e: any) { toast.error(e.message); } finally { setBusy(null); }
  }

  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Reports & activity", "التقارير والنشاط")} subtitle={tr("Download data for Excel, and see who changed what.", "حمّل البيانات لبرنامج Excel وتعرّف على من غيّر ماذا.")} />
      <div className="flex gap-2">
        <button onClick={() => setTab("export")} className={`px-4 py-2 rounded-xl text-sm font-medium ${tab === "export" ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}><FileSpreadsheet className="inline h-4 w-4 me-2" />{tr("Exports", "التصدير")}</button>
        {user?.role === "hr_admin" && <button onClick={() => setTab("audit")} className={`px-4 py-2 rounded-xl text-sm font-medium ${tab === "audit" ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}><History className="inline h-4 w-4 me-2" />{tr("Activity log", "سجل النشاط")}</button>}
      </div>

      {tab === "export" ? (
        <>
          <input type="month" className={inputCls + " max-w-[12rem]"} value={month} onChange={(e) => e.target.value && setMonth(e.target.value)} />
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {reports.map(([id, label, q, name]) => (
              <div key={id} className={cardCls + " flex items-center justify-between gap-3"}>
                <div><div className="font-semibold">{label}</div><div className="text-xs text-muted-foreground">CSV · Excel</div></div>
                <button className={btnCls} disabled={busy !== null} onClick={() => run(id, q, name)}><Download className="h-4 w-4" />{busy === id ? "…" : tr("Download", "تحميل")}</button>
              </div>
            ))}
          </div>
        </>
      ) : <Audit />}
    </div>
  );
}

function Audit() {
  const tr = useTr();
  const [entity, setEntity] = useState("");
  const [q, setQ] = useState("");
  const { data = [], isLoading } = useQuery<any[]>({ queryKey: ["audit", entity, q], queryFn: () => api(`/audit?limit=200${entity ? `&entity=${entity}` : ""}${q ? `&q=${encodeURIComponent(q)}` : ""}`) });
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2 items-center">
        {ENTITIES.map((e) => <button key={e} onClick={() => setEntity(e)} className={`px-3 py-1.5 rounded-full text-xs font-semibold ${entity === e ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>{e === "" ? tr("All", "الكل") : e.replace("_", " ")}</button>)}
        <input className={inputCls + " max-w-[14rem]"} placeholder={tr("Search…", "بحث…")} value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      {isLoading ? <Spinner /> : data.length === 0 ? <Empty text={tr("Nothing recorded yet", "لا شيء مسجل بعد")} /> : (
        <div className="bg-card rounded-2xl border border-border overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-xs uppercase text-muted-foreground"><tr>{[tr("When", "متى"), tr("Who", "من"), tr("Action", "الإجراء"), tr("Details", "التفاصيل")].map((h) => <th key={h} className="px-4 py-3 text-start font-semibold">{h}</th>)}</tr></thead>
            <tbody>
              {data.map((a) => (
                <tr key={a.id} className="border-t border-border align-top">
                  <td className="px-4 py-2.5 whitespace-nowrap text-muted-foreground">{String(a.createdAt).replace("T", " ").slice(0, 16)}</td>
                  <td className="px-4 py-2.5 font-medium">{a.userName || "—"}</td>
                  <td className="px-4 py-2.5"><Badge tone="blue">{a.action}</Badge> <span className="text-muted-foreground">{String(a.entity).replace("_", " ")}{a.entityId ? ` #${a.entityId}` : ""}</span></td>
                  <td className="px-4 py-2.5 text-xs text-muted-foreground max-w-md break-words">{typeof a.details === "string" ? a.details : JSON.stringify(a.details ?? "")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
