import { useState } from "react";
import { inputCls, useTr } from "@/components/kit";
import { ymd } from "@/lib/http";

export const CONTRACT_TYPES: [string, string, string][] = [
  ["permanent", "Permanent (no end date)", "دائم (بدون تاريخ انتهاء)"],
  ["fixed_term", "Fixed term", "محدد المدة"],
  ["probation", "Probation", "فترة تجربة"],
  ["part_time", "Part time", "دوام جزئي"],
  ["temporary", "Temporary", "مؤقت"],
  ["internship", "Internship", "تدريب"],
];
export const MONTH_CHOICES = [1, 3, 6, 12, 24, 36, 48, 60];

/** Contract start + months − 1 day, month ends respected (31 Jan + 1 month = 28/29 Feb). */
export function contractEnd(startIso: string, months: number): string {
  const d = new Date(startIso + "T12:00:00");
  if (isNaN(+d) || !months) return "";
  const day = d.getDate();
  d.setDate(1); d.setMonth(d.getMonth() + months);
  const last = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  d.setDate(Math.min(day, last));
  d.setDate(d.getDate() - 1);
  return ymd(d);
}

export const daysLeft = (endIso: string | null | undefined): number | null => {
  if (!endIso) return null;
  const a = new Date(endIso.slice(0, 10) + "T12:00:00"), t = new Date(); t.setHours(12, 0, 0, 0);
  return Math.round((+a - +t) / 86400000);
};

/** The contract part of the employee form. Fields are named contractType / contractStart / contractMonths / contractEnd. */
export function ContractFields({ initial }: { initial?: { type?: string | null; start?: string | null; months?: number | null; end?: string | null } }) {
  const tr = useTr();
  const [type, setType] = useState(initial?.type ?? "");
  const [start, setStart] = useState((initial?.start ?? "").slice(0, 10));
  const [months, setMonths] = useState<string>(initial?.months ? String(initial.months) : "");
  const [end, setEnd] = useState((initial?.end ?? "").slice(0, 10));
  const open = type === "permanent";
  const recompute = (s: string, m: string) => { if (s && m) setEnd(contractEnd(s, Number(m))); };

  return (
    <div className="rounded-xl border border-border p-4 space-y-3 bg-muted/20">
      <p className="text-sm font-semibold">{tr("Contract", "العقد")}</p>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs text-muted-foreground mb-1">{tr("Type", "النوع")}</label>
          <select name="contractType" className={inputCls} value={type} onChange={(e) => {
            const v = e.target.value; setType(v);
            if (v === "permanent") { setEnd(""); setMonths(""); } else if (v && !start) { const s = ymd(new Date()); setStart(s); }
          }}>
            <option value="">{tr("Not set", "غير محدد")}</option>
            {CONTRACT_TYPES.map(([k, en, ar]) => <option key={k} value={k}>{tr(en, ar)}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs text-muted-foreground mb-1">{tr("Contract starts", "بداية العقد")}</label>
          <input type="date" name="contractStart" className={inputCls} value={start} onChange={(e) => { setStart(e.target.value); recompute(e.target.value, months); }} />
        </div>
      </div>
      {type && !open && (
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs text-muted-foreground mb-1">{tr("For how long", "المدة")}</label>
            <select name="contractMonths" className={inputCls} value={months} onChange={(e) => { setMonths(e.target.value); recompute(start, e.target.value); }}>
              <option value="">{tr("Choose the end date myself", "أحدد تاريخ الانتهاء بنفسي")}</option>
              {MONTH_CHOICES.map((m) => <option key={m} value={m}>{m < 12 || m % 12 ? `${m} ${tr(m === 1 ? "month" : "months", m === 1 ? "شهر" : "أشهر")}` : `${m / 12} ${tr(m === 12 ? "year" : "years", m === 12 ? "سنة" : "سنوات")}`}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">{tr("Contract ends", "نهاية العقد")}</label>
            <input type="date" name="contractEnd" className={inputCls} value={end} min={start || undefined} onChange={(e) => { setEnd(e.target.value); setMonths(""); }} />
          </div>
        </div>
      )}
      {type && !open && !end && <p className="text-xs text-amber-700">{tr("Pick the duration or the end date so HR gets reminded before it ends.", "اختر المدة أو تاريخ الانتهاء ليصلك تذكير قبل انتهاء العقد.")}</p>}
    </div>
  );
}

/** Read the contract fields out of a form (empty text becomes null so an edit can clear them). */
export function contractFromForm(fd: FormData) {
  const v = (k: string) => { const x = String(fd.get(k) ?? ""); return x === "" ? null : x; };
  const m = v("contractMonths");
  return { contractType: v("contractType"), contractStart: v("contractStart"), contractMonths: m ? Number(m) : null, contractEnd: v("contractEnd") };
}

/** A small label for the employee list: when the contract ends. */
export function ContractChip({ type, end }: { type?: string | null; end?: string | null }) {
  const tr = useTr();
  if (!type) return null;
  if (type === "permanent" || !end) return <span className="text-[11px] text-muted-foreground">{type === "permanent" ? tr("Permanent contract", "عقد دائم") : tr("No end date", "بدون تاريخ انتهاء")}</span>;
  const d = daysLeft(end);
  const cls = d === null ? "" : d < 0 ? "bg-red-50 text-red-700 border-red-200" : d <= 30 ? "bg-amber-50 text-amber-700 border-amber-200" : "bg-muted text-muted-foreground border-border";
  const text = d === null ? end : d < 0 ? tr(`Contract ended ${-d} d ago`, `انتهى العقد منذ ${-d} يوم`) : d === 0 ? tr("Contract ends today", "ينتهي العقد اليوم") : tr(`Contract ends in ${d} d`, `ينتهي العقد بعد ${d} يوم`);
  return <span className={`inline-flex items-center mt-1 px-2 py-0.5 rounded-full text-[11px] border ${cls}`} title={end}>{text}</span>;
}
