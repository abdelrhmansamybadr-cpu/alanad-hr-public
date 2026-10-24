import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Flag, Heart, Lightbulb, Handshake, HeartHandshake, ThumbsUp, Trash2, Trophy } from "lucide-react";
import { api } from "@/lib/http";
import { Badge, Empty, PageHeader, Spinner, cardCls, useTr } from "@/components/kit";
import { useLang } from "@/contexts/LanguageContext";

interface Kudo { id: number; badge: string; message: string; createdAt: string; fromName: string; toName: string }
interface Top { employeeId: number; name: string; kudos: number }

const BADGES: Record<string, { en: string; ar: string; tone: string; Icon: any }> = {
  thanks: { en: "Thank you", ar: "شكراً", tone: "red", Icon: Heart },
  great_job: { en: "Great job", ar: "عمل رائع", tone: "green", Icon: ThumbsUp },
  teamwork: { en: "Teamwork", ar: "روح الفريق", tone: "blue", Icon: Handshake },
  creative: { en: "Creative", ar: "إبداع", tone: "amber", Icon: Lightbulb },
  helpful: { en: "Helpful", ar: "مساعدة", tone: "violet", Icon: HeartHandshake },
  leader: { en: "Leadership", ar: "قيادة", tone: "orange", Icon: Flag },
};

export default function Kudos() {
  const tr = useTr();
  const { isRTL } = useLang();
  const qc = useQueryClient();
  const { data, isLoading } = useQuery<Kudo[]>({ queryKey: ["kudos"], queryFn: () => api("/kudos?limit=100") });
  const { data: top } = useQuery<Top[]>({ queryKey: ["kudos-top"], queryFn: () => api("/kudos/top") });
  const del = useMutation({
    mutationFn: (id: number) => api(`/kudos/${id}`, "DELETE"),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["kudos"] }); qc.invalidateQueries({ queryKey: ["kudos-top"] }); },
  });

  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Kudos", "كلمات الشكر")} subtitle={tr("Colleagues thank each other from the app. HR can remove anything inappropriate.", "يشكر الزملاء بعضهم من التطبيق. يمكن للموارد البشرية حذف أي رسالة غير مناسبة.")} />
      <div className="grid lg:grid-cols-3 gap-5">
        <div className="lg:col-span-2 space-y-3">
          {isLoading ? <Spinner /> : !data?.length ? <Empty text={tr("No kudos yet.", "لا توجد رسائل شكر بعد.")} /> : data.map((k) => {
            const b = BADGES[k.badge] ?? BADGES.thanks;
            return (
              <div key={k.id} className={cardCls + " flex gap-3"}>
                <div className="h-10 w-10 shrink-0 rounded-xl bg-muted flex items-center justify-center"><b.Icon className="h-5 w-5" /></div>
                <div className="flex-1 min-w-0">
                  <div className="text-sm"><span className="font-semibold">{k.fromName}</span> <span className="text-muted-foreground">→</span> <span className="font-semibold">{k.toName}</span></div>
                  <p className="mt-1 text-sm leading-relaxed">{k.message}</p>
                  <div className="mt-2 flex items-center gap-2 text-xs text-muted-foreground"><Badge tone={b.tone}>{isRTL ? b.ar : b.en}</Badge>{new Date(k.createdAt.replace(" ", "T") + "Z").toLocaleDateString()}</div>
                </div>
                <button onClick={() => { if (confirm(tr("Delete this kudos?", "حذف رسالة الشكر؟"))) del.mutate(k.id); }} className="text-muted-foreground hover:text-red-600 self-start" aria-label="delete"><Trash2 className="h-4 w-4" /></button>
              </div>
            );
          })}
        </div>
        <div className={cardCls + " self-start"}>
          <h3 className="font-bold flex items-center gap-2 mb-3"><Trophy className="h-5 w-5 text-amber-500" />{tr("Most appreciated · 30 days", "الأكثر تقديراً · 30 يوماً")}</h3>
          {!top?.length ? <p className="text-sm text-muted-foreground">{tr("Nothing yet.", "لا شيء بعد.")}</p> : (
            <ol className="space-y-2">
              {top.map((t, i) => (
                <li key={t.employeeId} className="flex items-center gap-3 text-sm"><span className="w-5 font-extrabold text-amber-500">{i + 1}</span><span className="flex-1 truncate font-medium">{t.name}</span><Badge tone="red">{t.kudos}</Badge></li>
              ))}
            </ol>
          )}
        </div>
      </div>
    </div>
  );
}
