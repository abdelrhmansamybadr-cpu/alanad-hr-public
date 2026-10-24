import { useState } from "react";
import { ShieldAlert, UserSearch, Headset, ArrowUpCircle } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/http";
import { Badge, Empty, Modal, PageHeader, Spinner, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { FeatureOff, isOff, useLoad, useOwnerMe } from "@/lib/premium";

interface Complaint {
  id: number; subject: string; body: string; kind: string; severity: string; status: string;
  authorName: string; targetName?: string | null; targetPosition?: string | null; companyName?: string;
  createdAt: string; escalatedAt?: string | null;
  events?: { id: number; actorName: string; actorRole: string; action: string; note?: string | null; createdAt: string }[];
  myRole?: string; canComment?: boolean; canRespond?: boolean; canEscalate?: boolean;
}

const STATUS_TONE: Record<string, string> = { open: "amber", in_review: "blue", escalated: "violet", resolved: "green", dismissed: "gray" };
const SEV_TONE: Record<string, string> = { high: "red", normal: "amber", low: "gray" };

/** Complaints from team heads: HR answers or solves them, or sends them up to the owner (who sees the same thread). */
export default function Complaints() {
  const tr = useTr();
  const ownerMe = useOwnerMe();
  const [tab, setTab] = useState<"company" | "owner">("company");
  const list = useLoad<Complaint[]>(tab === "owner" ? "/complaints/owner" : "/complaints");
  const [open, setOpen] = useState<number | null>(null);
  const [filter, setFilter] = useState("all");

  const statusLabel = (s: string) => ({
    open: tr("Open", "مفتوحة"), in_review: tr("In review", "قيد المراجعة"), escalated: tr("With the owner", "عند المالك"),
    resolved: tr("Resolved", "تم حلها"), dismissed: tr("Dismissed", "مرفوضة"),
  } as Record<string, string>)[s] ?? s;

  if (list.error && isOff(list.error) && tab === "company" && !ownerMe.canManage) return <FeatureOff />;
  const items = (list.data ?? []).filter((c) => filter === "all" || (filter === "closed" ? ["resolved", "dismissed"].includes(c.status) : c.status === filter));

  return (
    <div className="space-y-6">
      <PageHeader title={tr("Complaints", "الشكاوى")} subtitle={tr("Team heads report problems here. Answer them, solve them, or send them up to the owner.", "رؤساء الفرق يبلغون عن المشاكل هنا. أجب عنها أو احلّها أو ارفعها للمالك.")}>
        <ShieldAlert className="h-6 w-6 text-primary" />
      </PageHeader>

      <div className="flex flex-wrap gap-2">
        {ownerMe.canManage && (
          <>
            <button onClick={() => setTab("company")} className={`px-4 py-2 rounded-xl text-sm font-medium ${tab === "company" ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>{tr("This company", "هذه الشركة")}</button>
            <button onClick={() => setTab("owner")} className={`px-4 py-2 rounded-xl text-sm font-medium ${tab === "owner" ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>{tr("Sent to me", "المرفوعة إليّ")}</button>
            <span className="w-px bg-border mx-1" />
          </>
        )}
        {[["all", tr("All", "الكل")], ["open", tr("Open", "مفتوحة")], ["in_review", tr("In review", "قيد المراجعة")], ["escalated", tr("With the owner", "عند المالك")], ["closed", tr("Closed", "مغلقة")]].map(([k, l]) => (
          <button key={k} onClick={() => setFilter(k)} className={`px-3 py-2 rounded-xl text-sm ${filter === k ? "bg-foreground/10 font-semibold" : "text-muted-foreground"}`}>{l}</button>
        ))}
      </div>

      {list.loading && !list.data ? <Spinner /> : list.error && !list.data ? <Empty text={list.error.message} /> : items.length === 0 ? <Empty text={tr("No complaints", "لا توجد شكاوى")} /> : (
        <div className="space-y-3">
          {items.map((c) => (
            <button key={c.id} onClick={() => setOpen(c.id)} className={`${cardCls} w-full text-start hover:border-primary/40 transition-colors`}>
              <div className="flex items-start gap-3">
                <div className="h-10 w-10 rounded-xl bg-primary/10 text-primary flex items-center justify-center shrink-0">{c.kind === "member" ? <UserSearch className="h-5 w-5" /> : <Headset className="h-5 w-5" />}</div>
                <div className="flex-1 min-w-0">
                  <p className="font-bold">{c.subject}</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {[tab === "owner" ? c.companyName : "", c.authorName, c.kind === "member" ? tr(`About ${c.targetName}`, `بخصوص ${c.targetName}`) : tr("To HR", "إلى الموارد البشرية")].filter(Boolean).join(" · ")}
                  </p>
                </div>
                <div className="flex gap-1.5"><Badge tone={SEV_TONE[c.severity] ?? "gray"}>{c.severity === "high" ? tr("Serious", "خطيرة") : c.severity === "low" ? tr("Minor", "بسيطة") : tr("Normal", "عادية")}</Badge><Badge tone={STATUS_TONE[c.status] ?? "gray"}>{statusLabel(c.status)}</Badge></div>
              </div>
            </button>
          ))}
        </div>
      )}

      {open !== null && <Detail id={open} statusLabel={statusLabel} onClose={() => { setOpen(null); list.reload(); }} />}
    </div>
  );
}

function Detail({ id, statusLabel, onClose }: { id: number; statusLabel: (s: string) => string; onClose: () => void }) {
  const tr = useTr();
  const d = useLoad<Complaint>(`/complaints/${id}`);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const c = d.data;

  const act = async (action: string, status?: string) => {
    setBusy(true);
    try {
      await api(`/complaints/${id}`, "PUT", { action, note, ...(status ? { status } : {}) });
      setNote("");
      await d.reload();
      toast.success(tr("Saved", "تم الحفظ"));
    } catch (e) { toast.error((e as Error).message); } finally { setBusy(false); }
  };

  const roleLabel = (r: string) => (r === "owner" ? tr("Owner", "المالك") : r === "hr" ? tr("HR", "الموارد البشرية") : tr("Team head", "رئيس الفريق"));
  const actionLabel = (a: string) => ({
    filed: tr("Filed the complaint", "قدّم الشكوى"), comment: tr("Wrote", "كتب"), in_review: tr("Started looking into it", "بدأ مراجعتها"),
    resolved: tr("Resolved it", "حلّها"), dismissed: tr("Dismissed it", "رفضها"), escalated: tr("Sent it to the owner", "رفعها للمالك"),
  } as Record<string, string>)[a] ?? a;
  const closed = c ? ["resolved", "dismissed"].includes(c.status) : false;

  return (
    <Modal open title={c?.subject ?? tr("Complaint", "الشكوى")} onClose={onClose} wide>
      {!c ? <Spinner /> : (
        <div className="space-y-4">
          <div className="flex flex-wrap gap-2">
            <Badge tone={STATUS_TONE[c.status] ?? "gray"}>{statusLabel(c.status)}</Badge>
            <Badge tone={SEV_TONE[c.severity] ?? "gray"}>{c.severity}</Badge>
            {c.companyName && <Badge tone="gray">{c.companyName}</Badge>}
          </div>
          <div className="text-sm text-muted-foreground">
            {tr("Filed by", "قدّمها")} <b className="text-foreground">{c.authorName}</b>
            {c.kind === "member" ? <> · {tr("about", "بخصوص")} <b className="text-foreground">{c.targetName}</b>{c.targetPosition ? ` (${c.targetPosition})` : ""}</> : <> · {tr("to HR", "إلى الموارد البشرية")}</>}
          </div>
          <p className="whitespace-pre-wrap text-sm leading-relaxed bg-muted/40 rounded-xl p-4">{c.body}</p>

          <div className="space-y-2">
            {(c.events ?? []).map((e) => (
              <div key={e.id} className="rounded-xl border border-border p-3 text-sm">
                <div className="flex items-center gap-2"><Badge tone={e.actorRole === "owner" ? "violet" : e.actorRole === "hr" ? "blue" : "gray"}>{roleLabel(e.actorRole)}</Badge><b>{e.actorName}</b><span className="text-xs text-muted-foreground ms-auto">{new Date(e.createdAt.replace(" ", "T") + "Z").toLocaleString()}</span></div>
                <div className="text-xs font-semibold text-primary mt-1">{actionLabel(e.action)}</div>
                {e.note && <p className="mt-1 whitespace-pre-wrap">{e.note}</p>}
              </div>
            ))}
          </div>

          {(c.canComment || c.canRespond || c.canEscalate) && (
            <div className="space-y-3 pt-2 border-t border-border">
              <textarea className={inputCls} rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder={tr("Your note…", "ملاحظتك…")} />
              <div className="flex flex-wrap gap-2">
                {c.canComment && <button disabled={busy || !note.trim()} className={btnGhost} onClick={() => act("comment")}>{tr("Add note", "إضافة ملاحظة")}</button>}
                {c.canRespond && !closed && <button disabled={busy} className={btnGhost} onClick={() => act("respond", "in_review")}>{tr("Mark in review", "قيد المراجعة")}</button>}
                {c.canRespond && !closed && <button disabled={busy} className={btnGhost} onClick={() => act("respond", "dismissed")}>{tr("Dismiss", "رفض الشكوى")}</button>}
                {c.canRespond && !closed && <button disabled={busy} className={btnCls} onClick={() => act("respond", "resolved")}>{tr("Resolve", "تم الحل")}</button>}
                {c.canEscalate && <button disabled={busy} className={`${btnGhost} inline-flex items-center gap-1.5`} onClick={() => act("escalate")}><ArrowUpCircle className="h-4 w-4" />{tr("Send to the owner", "رفعها للمالك")}</button>}
              </div>
              <p className="text-xs text-muted-foreground">{tr("Resolving, dismissing and sending to the owner need a written note. Everything stays on the thread.", "الحل والرفض والرفع للمالك تحتاج ملاحظة مكتوبة. كل شيء يبقى مسجلاً في السجل.")}</p>
            </div>
          )}
        </div>
      )}
    </Modal>
  );
}
