import { Link } from "wouter";
import { Trophy, Flame, Footprints, ClipboardCheck } from "lucide-react";
import { cardCls, useTr } from "@/components/kit";
import { useLang } from "@/contexts/LanguageContext";

/** Today at a glance: how the workday is going, worked out automatically by the server. */
export function TodayPanel({ stats }: { stats?: any }) {
  const tr = useTr();
  const { isRTL } = useLang();
  if (!stats) return null;
  const cells: [string, number, string][] = [
    [tr("Present", "حاضر"), stats.presentToday ?? 0, "text-emerald-600"],
    [tr("Late", "متأخر"), stats.lateToday ?? 0, "text-amber-600"],
    [tr("Half day", "نصف يوم"), stats.halfDayToday ?? 0, "text-orange-600"],
    [tr("Absent", "غائب"), stats.absentToday ?? 0, "text-red-600"],
    [tr("Not in yet", "لم يحضر بعد"), stats.notInYet ?? 0, "text-muted-foreground"],
    [tr("On leave", "إجازة"), stats.onLeave ?? 0, "text-blue-600"],
  ];
  const top: any[] = stats.topPerformers ?? [];
  const corrections = stats.pendingCorrections ?? 0;
  const away = stats.outsideNow ?? 0;

  return (
    <div className="grid lg:grid-cols-3 gap-5" dir={isRTL ? "rtl" : "ltr"}>
      <div className={cardCls + " lg:col-span-2"}>
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-bold text-lg">{tr("Today at a glance", "نظرة سريعة على اليوم")}</h3>
          <Link href="/attendance"><span className="text-sm text-primary cursor-pointer hover:underline">{tr("Open attendance", "فتح الحضور")}</span></Link>
        </div>
        <div className="grid grid-cols-3 sm:grid-cols-6 gap-3 text-center">
          {cells.map(([l, v, c]) => (
            <div key={l} className="rounded-xl bg-muted/40 py-3"><div className={`text-2xl font-extrabold ${c}`}>{v}</div><div className="text-[11px] text-muted-foreground">{l}</div></div>
          ))}
        </div>
        <div className="flex flex-wrap gap-2 mt-4">
          {away > 0 && <Link href="/attendance"><span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-red-100 text-red-700 text-xs font-semibold cursor-pointer"><Footprints className="h-3.5 w-3.5" />{away} {tr("away from the workplace now", "خارج مكان العمل الآن")}</span></Link>}
          {corrections > 0 && <Link href="/requests"><span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-amber-100 text-amber-700 text-xs font-semibold cursor-pointer"><ClipboardCheck className="h-3.5 w-3.5" />{corrections} {tr("attendance / information requests to review", "طلبات حضور/بيانات للمراجعة")}</span></Link>}
        </div>
      </div>

      <div className="rounded-2xl p-5 text-white relative overflow-hidden" style={{ background: "linear-gradient(135deg,#1E1B4B,#312E81 55%,#4C1D95)" }}>
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-bold flex items-center gap-2"><Trophy className="h-5 w-5 text-yellow-300" />{tr("Top performers", "الأفضل أداءً")}</h3>
          <Link href="/rewards"><span className="text-xs text-white/70 cursor-pointer hover:underline">{tr("View all", "عرض الكل")}</span></Link>
        </div>
        {top.length === 0 ? <p className="text-sm text-white/70">{tr("Rankings appear after the first full working days.", "يظهر الترتيب بعد أول أيام عمل كاملة.")}</p> : (
          <ul className="space-y-2.5">
            {top.map((p) => (
              <li key={p.employeeId} className="flex items-center gap-3">
                <span className="w-5 font-extrabold text-yellow-300">{p.rank}</span>
                <span className="h-8 w-8 rounded-full bg-white/15 flex items-center justify-center text-xs font-bold">{String(p.name).split(" ").map((x: string) => x[0]).slice(0, 2).join("")}</span>
                <span className="flex-1 min-w-0"><span className="block text-sm font-semibold truncate">{p.name}</span><span className="block text-[11px] text-white/60">{tr("Level", "المستوى")} {p.level} · {p.levelName}</span></span>
                <span className="inline-flex items-center gap-1 text-sm font-bold"><Flame className="h-4 w-4 text-orange-400" />{p.streak}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
