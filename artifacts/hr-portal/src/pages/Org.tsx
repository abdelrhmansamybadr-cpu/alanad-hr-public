import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronDown, ChevronRight, Star } from "lucide-react";
import { api } from "@/lib/http";
import { Badge, Empty, PageHeader, Spinner, cardCls, useTr } from "@/components/kit";
import { useLang } from "@/contexts/LanguageContext";

interface Person { id: number; firstName: string; lastName: string; position?: string | null; reports?: Person[] }
interface OrgData { departments: { id: number; name: string; head: Person | null; members: Person[] }[]; unassigned: Person[]; tree: Person[] }

const ini = (p: Person) => `${p.firstName[0] ?? ""}${p.lastName[0] ?? ""}`.toUpperCase();

function PersonRow({ p, head }: { p: Person; head?: boolean }) {
  return (
    <div className="flex items-center gap-3 py-1.5">
      <div className={`h-9 w-9 rounded-full flex items-center justify-center text-xs font-bold ${head ? "bg-amber-100 text-amber-700 ring-2 ring-amber-300" : "bg-primary/10 text-primary"}`}>{ini(p)}</div>
      <div className="flex-1 min-w-0"><div className="text-sm font-medium truncate">{p.firstName} {p.lastName}</div><div className="text-xs text-muted-foreground truncate">{p.position || "—"}</div></div>
      {head && <Badge tone="amber"><Star className="h-3 w-3 me-1" />head</Badge>}
    </div>
  );
}

function Node({ p, depth }: { p: Person; depth: number }) {
  const [open, setOpen] = useState(depth < 1);
  const kids = p.reports ?? [];
  return (
    <div style={{ marginInlineStart: Math.min(depth, 6) * 22 }}>
      <div className={cardCls + " !p-3 mb-2 flex items-center gap-2"}>
        {kids.length > 0 ? <button onClick={() => setOpen(!open)} className="p-1 rounded hover:bg-muted">{open ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4 rtl:rotate-180" />}</button> : <span className="w-6" />}
        <div className="flex-1"><PersonRow p={p} /></div>
        {kids.length > 0 && <Badge tone="blue">{kids.length}</Badge>}
      </div>
      {open && kids.map((k) => <Node key={k.id} p={k} depth={depth + 1} />)}
    </div>
  );
}

export default function Org() {
  const tr = useTr();
  const { isRTL } = useLang();
  const [tab, setTab] = useState<"dept" | "lines">("dept");
  const { data, isLoading } = useQuery<OrgData>({ queryKey: ["org"], queryFn: () => api("/org") });
  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Organisation chart", "الهيكل التنظيمي")} subtitle={tr("Departments with their heads, and who reports to whom.", "الأقسام ورؤساؤها ومن يتبع من.")} />
      <div className="flex gap-2">
        {(["dept", "lines"] as const).map((k) => <button key={k} onClick={() => setTab(k)} className={`px-4 py-2 rounded-xl text-sm font-medium ${tab === k ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>{k === "dept" ? tr("By department", "حسب القسم") : tr("Reporting lines", "خطوط التقارير")}</button>)}
      </div>
      {isLoading || !data ? <Spinner /> : tab === "dept" ? (
        data.departments.length === 0 && data.unassigned.length === 0 ? <Empty text={tr("No departments yet.", "لا توجد أقسام بعد.")} /> : (
          <div className="grid md:grid-cols-2 gap-5">
            {data.departments.map((d) => (
              <div key={d.id} className={cardCls}>
                <h3 className="font-bold text-lg mb-2">{d.name} <span className="text-sm font-normal text-muted-foreground">· {d.members.length}</span></h3>
                {d.head ? <PersonRow p={d.head} head /> : <p className="text-sm text-muted-foreground">{tr("No head assigned", "لم يُعيَّن رئيس")}</p>}
                <div className="border-t border-border mt-2 pt-2 divide-y divide-border/40">{d.members.filter((m) => m.id !== d.head?.id).map((m) => <PersonRow key={m.id} p={m} />)}</div>
              </div>
            ))}
            {data.unassigned.length > 0 && <div className={cardCls}><h3 className="font-bold text-lg mb-2">{tr("Not in a department", "بدون قسم")}</h3>{data.unassigned.map((m) => <PersonRow key={m.id} p={m} />)}</div>}
          </div>
        )
      ) : data.tree.length === 0 ? <Empty text={tr("No people yet.", "لا يوجد أشخاص بعد.")} /> : <div>{data.tree.map((r) => <Node key={r.id} p={r} depth={0} />)}</div>}
    </div>
  );
}
