import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Trophy, Flame, Settings2 } from "lucide-react";
import { Link } from "wouter";
import { api } from "@/lib/http";
import { Empty, Orb, PageHeader, Spinner, btnGhost, cardCls, useTr } from "@/components/kit";
import { EmployeeHub } from "@/components/EmployeeHub";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";

interface Item {
  rank: number; employeeId: number; name: string; position?: string | null; departmentName?: string | null;
  level: number; levelName: string; streak: number; green: number; red: number; black: number; score: number;
}

const MEDALS = ["#F59E0B", "#94A3B8", "#D97706"];

export default function Rewards() {
  const tr = useTr();
  const { isRTL } = useLang();
  const { user } = useAuth();
  const { data, isLoading } = useQuery<{ enabled: boolean; items: Item[] }>({ queryKey: ["leaderboard"], queryFn: () => api("/points/leaderboard") });
  const [hub, setHub] = useState<Item | null>(null);
  const items = data?.items ?? [];
  const top = items.slice(0, 3);

  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Rewards & levels", "المكافآت والمستويات")} subtitle={tr("Green for an on-time day, red for a half day, black for an absence. Greens cancel penalties and every streak of green days raises a level.", "أخضر ليوم في الموعد، أحمر لنصف يوم، أسود للغياب. الأخضر يلغي العقوبات وكل سلسلة أيام خضراء ترفع مستوى.")}>
        {user?.role === "hr_admin" && <Link href="/company?tab=automation"><span className={btnGhost + " cursor-pointer"}><Settings2 className="h-4 w-4" />{tr("Rules", "القواعد")}</span></Link>}
      </PageHeader>

      {isLoading ? <Spinner /> : !data?.enabled ? <Empty text={tr("Reward points are turned off. Turn them on in Company settings → Automation.", "نقاط المكافآت متوقفة. فعّلها من إعدادات الشركة ← الأتمتة.")} /> : items.length === 0 ? <Empty text={tr("No ranking yet — points appear after the first full working days of employees with an app account.", "لا يوجد ترتيب بعد — تظهر النقاط بعد أول أيام عمل كاملة للموظفين أصحاب حساب التطبيق.")} /> : (
        <>
          <div className="rounded-3xl p-6 text-white relative overflow-hidden" style={{ background: "linear-gradient(135deg,#0F0A2E,#241A63 55%,#4C1D95)" }}>
            <div className="flex items-end justify-center gap-4 sm:gap-10">
              {[1, 0, 2].filter((i) => top[i]).map((i) => {
                const it = top[i];
                const h = [150, 190, 120][i];
                return (
                  <button key={it.employeeId} onClick={() => setHub(it)} className="text-center w-28 sm:w-36">
                    {i === 0 && <Trophy className="mx-auto text-yellow-300 h-7 w-7 mb-1" />}
                    <div className="mx-auto h-16 w-16 rounded-full flex items-center justify-center text-xl font-bold bg-white/15" style={{ boxShadow: `0 0 0 3px ${MEDALS[i]}, 0 0 24px ${MEDALS[i]}99` }}>{it.name.split(" ").map((p) => p[0]).slice(0, 2).join("")}</div>
                    <div className="mt-2 font-bold truncate">{it.name}</div>
                    <div className="text-xs text-white/70">{tr("Level", "المستوى")} {it.level} · {it.levelName}</div>
                    <div className="mt-2 rounded-t-xl flex items-center justify-center text-4xl font-black" style={{ height: h, background: `linear-gradient(${MEDALS[i]}ee,${MEDALS[i]}55)` }}>{it.rank}</div>
                  </button>
                );
              })}
            </div>
          </div>

          <div className="bg-card rounded-2xl border border-border overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/40 text-xs uppercase text-muted-foreground"><tr>{["#", tr("Employee", "الموظف"), tr("Level", "المستوى"), tr("Streak", "السلسلة"), tr("Green", "أخضر"), tr("Red", "أحمر"), tr("Black", "أسود"), tr("Score", "الدرجة")].map((h) => <th key={h} className="px-4 py-3 text-start font-semibold">{h}</th>)}</tr></thead>
              <tbody>
                {items.map((it) => (
                  <tr key={it.employeeId} className="border-t border-border hover:bg-muted/30 cursor-pointer" onClick={() => setHub(it)}>
                    <td className="px-4 py-3 font-extrabold" style={{ color: it.rank <= 3 ? MEDALS[it.rank - 1] : undefined }}>{it.rank}</td>
                    <td className="px-4 py-3"><div className="font-medium">{it.name}</div><div className="text-xs text-muted-foreground">{it.departmentName || it.position || ""}</div></td>
                    <td className="px-4 py-3">{it.level} · {it.levelName}</td>
                    <td className="px-4 py-3"><span className="inline-flex items-center gap-1 font-semibold"><Flame className="h-4 w-4 text-orange-500" />{it.streak}</span></td>
                    <td className="px-4 py-3"><span className="inline-flex items-center gap-1.5"><Orb kind="green" size={16} />{it.green}</span></td>
                    <td className="px-4 py-3"><span className="inline-flex items-center gap-1.5"><Orb kind="red" size={16} />{it.red}</span></td>
                    <td className="px-4 py-3"><span className="inline-flex items-center gap-1.5"><Orb kind="black" size={16} />{it.black}</span></td>
                    <td className="px-4 py-3 font-bold">{it.score}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className={cardCls + " text-xs text-muted-foreground"}>{tr("Tap a row to give a point by hand, or excuse a day.", "اضغط على صف لمنح نقطة يدوياً أو إعفاء يوم.")}</p>
        </>
      )}

      {hub && <EmployeeHub initialTab="rewards" employee={{ id: hub.employeeId, firstName: hub.name.split(" ")[0], lastName: hub.name.split(" ").slice(1).join(" "), status: "active" }} onClose={() => setHub(null)} />}
    </div>
  );
}
