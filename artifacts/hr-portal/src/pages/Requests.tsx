import { useEffect, useState } from "react";
import { Check, X, ClipboardList } from "lucide-react";
import { toast } from "sonner";
import { useLang } from "@/contexts/LanguageContext";

interface RequestItem {
  id: number;
  employeeName: string;
  type: string;
  title: string;
  description?: string | null;
  amount?: number | null;
  status: string;
  reviewNote?: string | null;
  headStatus?: string | null;
  createdAt: string;
  payload?: any;
}

const TYPES: Record<string, [string, string]> = {
  expense: ["Expense", "مصروفات"],
  certificate: ["Certificate", "شهادة"],
  attendance_correction: ["Attendance correction", "تصحيح حضور"],
  equipment: ["Equipment", "معدات"],
  other: ["Other", "أخرى"],
  profile_change: ["Information change", "تعديل بيانات"],
};

const FIELD: Record<string, [string, string]> = {
  first_name: ["First name", "الاسم الأول"], last_name: ["Last name", "اسم العائلة"], phone: ["Phone", "الهاتف"], address: ["Address", "العنوان"],
  birth_date: ["Date of birth", "تاريخ الميلاد"], gender: ["Gender", "النوع"], emergency_name: ["Emergency contact", "جهة الطوارئ"], emergency_phone: ["Emergency phone", "هاتف الطوارئ"],
};

const STATUS_STYLE: Record<string, string> = {
  pending: "bg-amber-100 text-amber-700",
  approved: "bg-emerald-100 text-emerald-700",
  rejected: "bg-red-100 text-red-700",
  cancelled: "bg-muted text-muted-foreground",
};

async function api(path: string, method = "GET", body?: unknown) {
  const r = await fetch(`/api${path}`, {
    method,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${localStorage.getItem("hr-token") ?? ""}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.error || "Request failed");
  return data;
}

export default function Requests() {
  const { isRTL } = useLang();
  const tr = (en: string, ar: string) => (isRTL ? ar : en);
  const [status, setStatus] = useState("pending");
  const [items, setItems] = useState<RequestItem[]>([]);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    api(`/requests?status=${status}`)
      .then((d) => setItems(Array.isArray(d) ? d : []))
      .catch((e) => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, [status]);

  async function review(r: RequestItem, next: "approved" | "rejected") {
    const skip = r.headStatus === "pending";   // the team head has not decided yet: HR may go past him only with a written reason
    const note = window.prompt(skip
      ? tr("The team head has not decided yet. Write the reason for deciding without him:", "رئيس الفريق لم يقرر بعد. اكتب سبب القرار دونه:")
      : next === "approved" ? tr("Note (optional)", "ملاحظة (اختياري)") : tr("Reason for rejecting (optional)", "سبب الرفض (اختياري)"), "");
    if (note === null) return;
    if (skip && note.trim().length < 3) { toast.error(tr("Write the reason first", "اكتب السبب أولاً")); return; }
    try {
      await api(`/requests/${r.id}`, "PUT", { status: next, reviewNote: note, ...(skip ? { skipHead: true } : {}) });
      toast.success(next === "approved" ? tr("Approved", "تمت الموافقة") : tr("Rejected", "تم الرفض"));
      load();
    } catch (e: any) {
      toast.error(e.message);
    }
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <div>
        <h1 className="text-2xl font-bold">{tr("Employee requests", "طلبات الموظفين")}</h1>
        <p className="text-muted-foreground text-sm">{tr("Expenses, certificates, attendance corrections and equipment.", "المصروفات والشهادات وتصحيح الحضور والمعدات.")}</p>
      </div>
      <div className="flex gap-2">
        {["pending", "approved", "rejected"].map((s) => (
          <button
            key={s}
            onClick={() => setStatus(s)}
            className={`px-4 py-2 rounded-xl text-sm font-medium capitalize ${status === s ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}
          >
            {s === "pending" ? tr("Pending", "معلقة") : s === "approved" ? tr("Approved", "موافق عليها") : tr("Rejected", "مرفوضة")}
          </button>
        ))}
      </div>
      {loading ? (
        <div className="text-muted-foreground text-sm">…</div>
      ) : items.length === 0 ? (
        <div className="bg-card border border-border rounded-2xl p-10 text-center text-muted-foreground">
          <ClipboardList className="h-10 w-10 mx-auto mb-3 opacity-40" />
          {tr("Nothing here", "لا يوجد شيء هنا")}
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((r) => (
            <div key={r.id} className="bg-card border border-border rounded-2xl p-5 shadow-sm">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="font-semibold">{r.title}</div>
                  <div className="text-xs text-muted-foreground mt-0.5">
                    {r.employeeName} · {(TYPES[r.type] ?? [r.type, r.type])[isRTL ? 1 : 0]}
                    {r.amount ? ` · ${r.amount}` : ""}
                  </div>
                  {r.type === "profile_change" && r.payload?.changes && (
                    <div className="mt-3 space-y-2">
                      {Object.entries(r.payload.changes as Record<string, { from: string; to: string }>).map(([k, v]) => (
                        <div key={k} className="rounded-xl bg-muted/50 px-3 py-2 text-sm">
                          <div className="text-xs font-semibold text-muted-foreground">{(FIELD[k] ?? [k, k])[isRTL ? 1 : 0]}</div>
                          <div className="line-through text-red-600/80">{v.from || "—"}</div>
                          <div className="font-semibold text-emerald-700">{v.to || "—"}</div>
                        </div>
                      ))}
                    </div>
                  )}
                  {r.type === "attendance_correction" && r.payload && (
                    <div className="mt-3 rounded-xl bg-muted/50 px-3 py-2 text-sm space-y-0.5">
                      <div><b>{tr("Day", "اليوم")}:</b> {r.payload.date}</div>
                      <div><b>{tr("Arrived → left", "الحضور ← الانصراف")}:</b> {r.payload.checkIn || "—"} → {r.payload.checkOut || "—"}</div>
                      {r.payload.reason && <div><b>{tr("Reason", "السبب")}:</b> {r.payload.reason}</div>}
                    </div>
                  )}
                  {r.description && r.type !== "profile_change" && <p className="text-sm mt-2 whitespace-pre-wrap">{r.description}</p>}
                  {r.reviewNote && <p className="text-xs text-muted-foreground mt-2">“{r.reviewNote}”</p>}
                  {r.headStatus && r.status === "pending" && (
                    <p className={`text-xs font-semibold mt-2 ${r.headStatus === "pending" ? "text-amber-700" : "text-sky-700"}`}>
                      {r.headStatus === "pending" ? tr("Waiting for the team head's decision", "في انتظار قرار رئيس الفريق") : tr("Approved by the team head. Final decision is yours.", "وافق رئيس الفريق. القرار النهائي لك.")}
                    </p>
                  )}
                </div>
                <span className={`px-2.5 py-1 rounded-full text-xs font-semibold ${STATUS_STYLE[r.status] ?? "bg-muted"}`}>{r.status}</span>
              </div>
              {r.status === "pending" && (
                <div className="flex gap-2 mt-4">
                  <button onClick={() => review(r, "approved")} className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-emerald-600 text-white text-sm">
                    <Check className="h-4 w-4" />
                    {r.headStatus === "pending" ? tr("Approve without head", "موافقة دون الرئيس") : tr("Approve", "موافقة")}
                  </button>
                  <button onClick={() => review(r, "rejected")} className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-600 text-white text-sm">
                    <X className="h-4 w-4" />
                    {tr("Reject", "رفض")}
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
