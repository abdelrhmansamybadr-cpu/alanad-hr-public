import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { BedDouble, Moon, Palmtree, X } from "lucide-react";
import { Link } from "wouter";
import { api } from "@/lib/http";
import { cardCls, useTr } from "@/components/kit";
import { useLang } from "@/contexts/LanguageContext";

interface Person { employeeId: number; name: string; detail: string; position?: string | null }
interface Signal { key: "no_leave" | "overtime" | "rough_patch"; employees: Person[] }

/** Quiet signals that someone may need a friendly conversation. Not scores. Hidden when there is nothing to show. */
export function WellbeingPanel() {
  const tr = useTr();
  const { isRTL } = useLang();
  const [open, setOpen] = useState<Signal | null>(null);
  const { data } = useQuery<{ total: number; signals: Signal[] }>({ queryKey: ["wellbeing"], queryFn: () => api("/stats/wellbeing"), staleTime: 5 * 60_000 });
  const shown = (data?.signals ?? []).filter((s) => s.employees.length > 0);
  if (!shown.length) return null;

  const meta = {
    no_leave: { Icon: Palmtree, title: tr("No leave taken in over a year", "لم يأخذوا إجازة منذ أكثر من سنة") },
    overtime: { Icon: Moon, title: tr("Regularly working beyond the shift", "يعملون باستمرار بعد انتهاء الوردية") },
    rough_patch: { Icon: BedDouble, title: tr("Many late or missed days this month", "أيام تأخر أو غياب كثيرة هذا الشهر") },
  } as const;

  return (
    <div className={cardCls} dir={isRTL ? "rtl" : "ltr"}>
      <h3 className="font-bold text-lg">{tr("Worth a conversation", "يستحق حديثاً ودّياً")}</h3>
      <p className="text-xs text-muted-foreground mb-3">{tr("Quiet signals, not scores. A friendly check-in is usually all it takes.", "إشارات هادئة وليست درجات. غالباً يكفي سؤال لطيف عن الحال.")}</p>
      <div className="grid sm:grid-cols-3 gap-3">
        {shown.map((s) => {
          const { Icon, title } = meta[s.key];
          return (
            <button key={s.key} onClick={() => setOpen(s)} className="text-start rounded-xl border border-border p-3 hover:border-primary/50 transition">
              <div className="flex items-center justify-between"><Icon className="h-5 w-5 text-amber-600" /><span className="text-2xl font-extrabold text-amber-600">{s.employees.length}</span></div>
              <div className="text-sm font-medium mt-1.5 leading-snug">{title}</div>
            </button>
          );
        })}
      </div>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50" onClick={() => setOpen(null)}>
          <div className="bg-card w-full max-w-md max-h-[80vh] overflow-y-auto rounded-2xl border border-border shadow-xl" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between p-4 border-b border-border sticky top-0 bg-card"><h4 className="font-semibold">{meta[open.key].title}</h4><button onClick={() => setOpen(null)} aria-label="close"><X className="h-5 w-5" /></button></div>
            <ul className="divide-y divide-border">
              {open.employees.map((p) => (
                <li key={p.employeeId}><Link href="/employees"><span className="flex items-center justify-between gap-3 px-4 py-3 text-sm cursor-pointer hover:bg-muted/40"><span className="min-w-0"><span className="block font-medium truncate">{p.name}</span><span className="block text-xs text-muted-foreground truncate">{p.position || ""}</span></span><span className="text-xs text-muted-foreground shrink-0">{p.detail}</span></span></Link></li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </div>
  );
}
