import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, CheckCircle2, Info, XCircle } from "lucide-react";
import { api } from "@/lib/http";
import { whyText } from "@/lib/whyStrings";
import { useLang } from "@/contexts/LanguageContext";
import { Spinner, useTr } from "@/components/kit";

interface Reason { code: string; text: string; params: Record<string, unknown>; tone: "info" | "good" | "warn" | "bad" }
interface Explain { date: string; status: string; reasons: Reason[] }

const ICON = { good: [CheckCircle2, "text-emerald-600"], warn: [AlertTriangle, "text-amber-600"], bad: [XCircle, "text-red-600"], info: [Info, "text-muted-foreground"] } as const;

/** Why one employee's day has the status it has, in plain words with the exact numbers from the company rules. */
export function ExplainPanel({ date, employeeId }: { date: string; employeeId: number }) {
  const { isRTL } = useLang();
  const tr = useTr();
  const lang = isRTL ? "ar" : "en";
  const { data, isLoading, error } = useQuery<Explain>({ queryKey: ["explain", employeeId, date], queryFn: () => api(`/attendance/explain?date=${date}&employeeId=${employeeId}`) });
  if (isLoading) return <Spinner />;
  if (error || !data) return null;

  const text = (r: Reason) => {
    const p: Record<string, unknown> = { ...r.params };
    if (r.code === "result") p.status = tr(String(p.status).replace("_", " "), String(p.status));
    if (r.code === "missed_checkout") p.action = whyText(lang, `action.${p.action}`, {}, String(p.action));
    return whyText(lang, r.code, p, r.text);
  };

  return (
    <div className="rounded-xl border border-border bg-muted/30 p-3">
      <div className="text-xs font-semibold uppercase text-muted-foreground mb-2">{tr("Why this status", "سبب هذه الحالة")}</div>
      <ul className="space-y-1.5">
        {data.reasons.map((r, i) => {
          const [Icon, color] = ICON[r.tone] ?? ICON.info;
          const last = r.code === "result";
          return <li key={i} className="flex gap-2 text-sm leading-snug"><Icon className={`h-4 w-4 mt-0.5 shrink-0 ${color}`} /><span className={last ? "font-bold" : ""}>{text(r)}</span></li>;
        })}
      </ul>
    </div>
  );
}
