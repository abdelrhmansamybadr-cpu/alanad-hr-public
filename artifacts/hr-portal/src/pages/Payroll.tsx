import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { CheckCircle, Clock, Download, HandCoins, Plus, Printer, Sparkles, Trash2, Wallet } from "lucide-react";
import { toast } from "sonner";
import { api, downloadFile, money, ymd } from "@/lib/http";
import { Badge, Empty, Field, Modal, PageHeader, Spinner, STATUS_TONE, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";

interface Payslip {
  id: number;
  employeeId: number;
  employeeName: string;
  position?: string | null;
  departmentName?: string | null;
  month: string;
  baseSalary: number;
  bonus: number;
  deductions: number;
  netPay: number;
  status: string;
  paidAt?: string | null;
  breakdown?: { lines: { key: string; label: string; qty: number; amount: number }[]; stats: Record<string, number> } | null;
}

export default function Payroll() {
  const tr = useTr();
  const { isRTL } = useLang();
  const { company } = useAuth();
  const currency = company?.currency ?? "EGP";
  const qc = useQueryClient();
  const [month, setMonth] = useState(ymd(new Date()).slice(0, 7));
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<Payslip | null>(null);
  const [adding, setAdding] = useState(false);
  const [loans, setLoans] = useState(false);

  const { data: rows = [], isLoading } = useQuery<Payslip[]>({ queryKey: ["payroll", month], queryFn: () => api(`/payroll?month=${month}`) });
  const refresh = () => { qc.invalidateQueries({ queryKey: ["payroll"] }); qc.invalidateQueries({ queryKey: ["/api/payroll"] }); };

  const total = rows.reduce((s, r) => s + Number(r.netPay), 0);
  const paid = rows.filter((r) => r.status === "paid").length;
  const pending = rows.filter((r) => r.status === "pending").length;
  const deductions = rows.reduce((s, r) => s + Number(r.deductions), 0);
  const bonus = rows.reduce((s, r) => s + Number(r.bonus), 0);

  async function generate() {
    setBusy(true);
    try {
      const r: any = await api("/payroll/generate", "POST", { month, recalculate: true });
      const n = (r.created ?? 0) + (r.updated ?? 0);
      toast.success(n === 0 ? tr("Nothing new to create for this month", "لا جديد لإنشائه لهذا الشهر") : tr(`${n} payslips built from attendance`, `تم بناء ${n} قسيمة من الحضور`));
      refresh();
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }
  async function payAll() {
    if (!confirm(tr(`Mark ${pending} payslips as paid?`, `تحديد ${pending} قسيمة كمدفوعة؟`))) return;
    try { await api("/payroll/pay-all", "PUT", { month }); toast.success(tr("Marked as paid", "تم التحديد كمدفوعة")); refresh(); } catch (e: any) { toast.error(e.message); }
  }

  return (
    <div className="space-y-6" dir={isRTL ? "rtl" : "ltr"}>
      <PageHeader title={tr("Payroll", "الرواتب")} subtitle={tr("Payslips are built from attendance: absences and half days are deducted, overtime is added.", "تُبنى القسائم من الحضور: تُخصم أيام الغياب وأنصاف الأيام ويُضاف الإضافي.")}>
        <input type="month" className={inputCls + " !w-auto"} value={month} onChange={(e) => e.target.value && setMonth(e.target.value)} />
        <button className={btnGhost} onClick={() => downloadFile(`/reports/payroll?month=${month}&format=csv`, `payroll-${month}.csv`).catch((e) => toast.error(e.message))}><Download className="h-4 w-4" />CSV</button>
        <button className={btnGhost} onClick={() => setLoans(true)}><HandCoins className="h-4 w-4" />{tr("Loans", "السلف")}</button>
        <button className={btnGhost} onClick={() => setAdding(true)}><Plus className="h-4 w-4" />{tr("Add payslip", "إضافة قسيمة")}</button>
        <button className={btnCls} disabled={busy} onClick={generate}><Sparkles className="h-4 w-4" />{tr("Generate from attendance", "إنشاء من الحضور")}</button>
      </PageHeader>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <div className={cardCls + " col-span-2 lg:col-span-1 text-white"} style={{ background: "linear-gradient(135deg,#00617A,#7C3AED)" }}>
          <div className="text-sm opacity-80">{tr("Total net", "إجمالي الصافي")}</div>
          <div className="text-3xl font-extrabold mt-1">{money(total, currency)}</div>
          <div className="text-xs opacity-80 mt-2">{paid} {tr("paid", "مدفوعة")} · {pending} {tr("pending", "معلقة")}</div>
        </div>
        <div className={cardCls}><div className="text-sm text-muted-foreground">{tr("Deductions", "الخصومات")}</div><div className="text-2xl font-bold text-red-600 mt-1">−{money(deductions, currency)}</div></div>
        <div className={cardCls}><div className="text-sm text-muted-foreground">{tr("Bonus & overtime", "المكافآت والإضافي")}</div><div className="text-2xl font-bold text-emerald-600 mt-1">+{money(bonus, currency)}</div></div>
        <div className={cardCls + " flex items-center"}>{pending > 0 ? <button className={btnCls + " w-full"} onClick={payAll}><Wallet className="h-4 w-4" />{tr("Pay all pending", "دفع كل المعلق")}</button> : <span className="text-sm text-muted-foreground">{tr("Nothing pending", "لا شيء معلق")}</span>}</div>
      </div>

      {isLoading ? <Spinner /> : rows.length === 0 ? <Empty text={tr("No payslips this month. Tap “Generate from attendance”.", "لا توجد قسائم لهذا الشهر. اضغط «إنشاء من الحضور».")} /> : (
        <div className="bg-card rounded-2xl border border-border overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-xs uppercase text-muted-foreground"><tr>{[tr("Employee", "الموظف"), tr("Base", "الأساسي"), tr("Bonus", "مكافأة"), tr("Deductions", "خصومات"), tr("Net", "الصافي"), tr("Status", "الحالة"), ""].map((h, i) => <th key={i} className="px-4 py-3 text-start font-semibold">{h}</th>)}</tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-t border-border hover:bg-muted/30 cursor-pointer" onClick={() => setOpen(r)}>
                  <td className="px-4 py-3"><div className="font-medium">{r.employeeName}</div><div className="text-xs text-muted-foreground">{r.departmentName || r.position || ""}</div></td>
                  <td className="px-4 py-3 tabular-nums">{money(r.baseSalary, currency)}</td>
                  <td className="px-4 py-3 tabular-nums text-emerald-600">{Number(r.bonus) > 0 ? "+" + money(r.bonus, currency) : "—"}</td>
                  <td className="px-4 py-3 tabular-nums text-red-600">{Number(r.deductions) > 0 ? "−" + money(r.deductions, currency) : "—"}</td>
                  <td className="px-4 py-3 tabular-nums font-bold">{money(r.netPay, currency)}</td>
                  <td className="px-4 py-3"><Badge tone={STATUS_TONE[r.status] ?? "gray"}>{r.status === "paid" ? <CheckCircle className="h-3 w-3 me-1" /> : <Clock className="h-3 w-3 me-1" />}{r.status === "paid" ? tr("Paid", "مدفوعة") : tr("Pending", "معلقة")}</Badge></td>
                  <td className="px-4 py-3 text-end text-xs text-primary">{tr("Details", "التفاصيل")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {open && <Detail slip={open} currency={currency} onClose={() => setOpen(null)} onChanged={() => { refresh(); setOpen(null); }} />}
      {adding && <AddModal month={month} onClose={() => setAdding(false)} onSaved={refresh} />}
      {loans && <LoansModal currency={currency} onClose={() => setLoans(false)} />}
    </div>
  );
}

function Detail({ slip, currency, onClose, onChanged }: { slip: Payslip; currency: string; onClose: () => void; onChanged: () => void }) {
  const tr = useTr();
  const { isRTL } = useLang();
  const [bonus, setBonus] = useState(String(slip.bonus));
  const [ded, setDed] = useState(String(slip.deductions));
  const lines = slip.breakdown?.lines ?? [];
  const st = slip.breakdown?.stats ?? {};
  const labels: Record<string, string> = { absent: tr("Absent days", "أيام الغياب"), unpaid_leave: tr("Unpaid leave days", "إجازة غير مدفوعة"), half_day: tr("Half days", "أنصاف الأيام"), late: tr("Late minutes", "دقائق التأخير"), overtime: tr("Overtime hours", "ساعات الإضافي"), perfect: tr("Perfect attendance bonus", "مكافأة الحضور الكامل"), insurance: tr("Social insurance", "التأمينات الاجتماعية"), tax: tr("Income tax", "ضريبة الدخل") };
  const lineLabel = (l: { key: string; label: string }) => labels[l.key] ?? (l.key.startsWith("loan_") ? `${tr("Loan", "سلفة")}: ${l.label.replace(/^Loan:\s*/, "")}` : l.label);
  const showQty = (k: string) => !["perfect", "insurance", "tax"].includes(k) && !k.startsWith("loan_");

  async function save() {
    try { await api(`/payroll/${slip.id}`, "PUT", { bonus: Number(bonus) || 0, deductions: Number(ded) || 0 }); toast.success(tr("Saved", "تم الحفظ")); onChanged(); } catch (e: any) { toast.error(e.message); }
  }
  async function print() {
    try {
      const r: any = await api(`/payroll/${slip.id}/link?lang=${isRTL ? "ar" : "en"}`);
      window.open(r.url, "_blank", "noopener");
    } catch (e: any) { toast.error(e.message); }
  }
  async function pay() { try { await api(`/payroll/${slip.id}`, "PUT", { status: "paid" }); toast.success(tr("Marked as paid", "تم التحديد كمدفوعة")); onChanged(); } catch (e: any) { toast.error(e.message); } }
  async function del() { if (!confirm(tr("Delete this payslip?", "حذف هذه القسيمة؟"))) return; try { await api(`/payroll/${slip.id}`, "DELETE"); onChanged(); } catch (e: any) { toast.error(e.message); } }

  return (
    <Modal open title={`${slip.employeeName} · ${slip.month}`} onClose={onClose}>
      <div className="space-y-4">
        <div className="space-y-1.5 text-sm">
          <div className="flex justify-between"><span className="text-muted-foreground">{tr("Base salary", "الراتب الأساسي")}</span><b>{money(slip.baseSalary, currency)}</b></div>
          {lines.map((l) => (
            <div key={l.key} className="flex justify-between"><span className="text-muted-foreground">{lineLabel(l)}{showQty(l.key) ? ` (${Number.isInteger(l.qty) ? l.qty : l.qty.toFixed(1)})` : ""}</span><span className={l.amount >= 0 ? "text-emerald-600 font-semibold" : "text-red-600 font-semibold"}>{l.amount >= 0 ? "+" : "−"}{money(Math.abs(l.amount), currency)}</span></div>
          ))}
          <div className="flex justify-between border-t border-border pt-2 text-base"><span className="font-semibold">{tr("Net pay", "الصافي")}</span><b className="text-primary">{money(slip.netPay, currency)}</b></div>
          {lines.length > 0 && <p className="text-xs text-muted-foreground">{tr(`${st.workingDays ?? 0} working days · ${st.absentDays ?? 0} absent · ${st.halfDays ?? 0} half days · daily rate ${money(st.dailyRate ?? 0, currency)}`, `${st.workingDays ?? 0} يوم عمل · ${st.absentDays ?? 0} غياب · ${st.halfDays ?? 0} نصف يوم · الأجر اليومي ${money(st.dailyRate ?? 0, currency)}`)}</p>}
        </div>
        {slip.status === "pending" && (
          <div className="grid grid-cols-2 gap-3 pt-2 border-t border-border">
            <Field label={tr("Bonus (edit)", "مكافأة (تعديل)")}><input type="number" className={inputCls} value={bonus} onChange={(e) => setBonus(e.target.value)} /></Field>
            <Field label={tr("Deductions (edit)", "خصومات (تعديل)")}><input type="number" className={inputCls} value={ded} onChange={(e) => setDed(e.target.value)} /></Field>
          </div>
        )}
        <div className="flex items-center justify-between pt-2">
          <button className="text-sm text-red-600 inline-flex items-center gap-1" onClick={del}><Trash2 className="h-4 w-4" />{tr("Delete", "حذف")}</button>
          <div className="flex gap-2">
            <button className={btnGhost} onClick={print}><Printer className="h-4 w-4" />{tr("Print / PDF", "طباعة / PDF")}</button>
            {slip.status === "pending" && <button className={btnGhost} onClick={save}>{tr("Save changes", "حفظ التعديل")}</button>}
            {slip.status === "pending" && <button className={btnCls} onClick={pay}>{tr("Mark as paid", "تحديد كمدفوعة")}</button>}
          </div>
        </div>
      </div>
    </Modal>
  );
}

function AddModal({ month, onClose, onSaved }: { month: string; onClose: () => void; onSaved: () => void }) {
  const tr = useTr();
  const { data: emps = [] } = useQuery<any[]>({ queryKey: ["employees-all"], queryFn: () => api("/employees") });
  const [f, setF] = useState({ employeeId: "", baseSalary: "", bonus: "0", deductions: "0" });
  async function save() {
    if (!f.employeeId) return void toast.error(tr("Choose an employee", "اختر موظفاً"));
    try {
      await api("/payroll", "POST", { employeeId: Number(f.employeeId), month, baseSalary: Number(f.baseSalary) || 0, bonus: Number(f.bonus) || 0, deductions: Number(f.deductions) || 0 });
      toast.success(tr("Payslip added", "تمت إضافة القسيمة"));
      onSaved();
      onClose();
    } catch (e: any) { toast.error(e.message); }
  }
  return (
    <Modal open title={tr("Add a payslip", "إضافة قسيمة") + ` · ${month}`} onClose={onClose}>
      <div className="space-y-4">
        <Field label={tr("Employee", "الموظف")}>
          <select className={inputCls} value={f.employeeId} onChange={(e) => { const emp = emps.find((x) => String(x.id) === e.target.value); setF({ ...f, employeeId: e.target.value, baseSalary: emp?.salary ? String(emp.salary) : f.baseSalary }); }}>
            <option value="">—</option>
            {emps.filter((e) => e.status !== "inactive").map((e) => <option key={e.id} value={e.id}>{e.firstName} {e.lastName}</option>)}
          </select>
        </Field>
        <div className="grid grid-cols-3 gap-3">
          <Field label={tr("Base", "الأساسي")}><input type="number" className={inputCls} value={f.baseSalary} onChange={(e) => setF({ ...f, baseSalary: e.target.value })} /></Field>
          <Field label={tr("Bonus", "مكافأة")}><input type="number" className={inputCls} value={f.bonus} onChange={(e) => setF({ ...f, bonus: e.target.value })} /></Field>
          <Field label={tr("Deductions", "خصومات")}><input type="number" className={inputCls} value={f.deductions} onChange={(e) => setF({ ...f, deductions: e.target.value })} /></Field>
        </div>
        <div className="flex justify-end gap-2"><button className={btnGhost} onClick={onClose}>{tr("Cancel", "إلغاء")}</button><button className={btnCls} onClick={save}>{tr("Add", "إضافة")}</button></div>
      </div>
    </Modal>
  );
}

interface Loan { id: number; employeeId: number; employeeName: string; title: string; amount: number; installment: number; startMonth: string; status: "active" | "done" | "cancelled"; paid: number; remaining: number }

function LoansModal({ currency, onClose }: { currency: string; onClose: () => void }) {
  const tr = useTr();
  const qc = useQueryClient();
  const { data: loans = [], isLoading } = useQuery<Loan[]>({ queryKey: ["loans"], queryFn: () => api("/payroll/loans") });
  const { data: emps = [] } = useQuery<any[]>({ queryKey: ["employees-all"], queryFn: () => api("/employees") });
  const [f, setF] = useState({ employeeId: "", title: "", amount: "", installment: "", startMonth: ymd(new Date()).slice(0, 7) });
  const reload = () => qc.invalidateQueries({ queryKey: ["loans"] });
  async function add() {
    if (!f.employeeId || !f.title.trim() || !Number(f.amount) || !Number(f.installment)) return void toast.error(tr("Fill in every field", "املأ كل الحقول"));
    try {
      await api("/payroll/loans", "POST", { employeeId: Number(f.employeeId), title: f.title.trim(), amount: Number(f.amount), installment: Number(f.installment), startMonth: f.startMonth });
      setF({ ...f, title: "", amount: "", installment: "" });
      toast.success(tr("Loan added. It is taken from the pay in monthly instalments.", "تمت إضافة السلفة وستُخصم من الراتب بأقساط شهرية."));
      reload();
    } catch (e: any) { toast.error(e.message); }
  }
  async function stop(l: Loan) {
    if (!confirm(tr("Stop this loan? What was already repaid stays.", "إيقاف هذه السلفة؟ ما سُدّد سابقاً يبقى كما هو."))) return;
    try { await api(`/payroll/loans/${l.id}`, "PUT", { status: "cancelled" }); reload(); } catch (e: any) { toast.error(e.message); }
  }
  const tone: Record<string, string> = { active: "blue", done: "green", cancelled: "gray" };
  const label: Record<string, string> = { active: tr("Active", "جارية"), done: tr("Repaid", "مسدّدة"), cancelled: tr("Stopped", "موقوفة") };
  return (
    <Modal open title={tr("Loans and advances", "السلف والقروض")} onClose={onClose} wide>
      <div className="space-y-4">
        <div className="rounded-xl border border-border p-3 space-y-3">
          <div className="text-sm font-semibold">{tr("New loan", "سلفة جديدة")}</div>
          <div className="grid sm:grid-cols-2 gap-3">
            <select className={inputCls} value={f.employeeId} onChange={(e) => setF({ ...f, employeeId: e.target.value })}>
              <option value="">{tr("Employee…", "الموظف…")}</option>
              {emps.filter((e) => e.status !== "inactive").map((e) => <option key={e.id} value={e.id}>{e.firstName} {e.lastName}</option>)}
            </select>
            <input className={inputCls} placeholder={tr("What is it for?", "لأي غرض؟")} value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} />
            <input type="number" min="0" className={inputCls} placeholder={tr("Amount", "المبلغ")} value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} />
            <input type="number" min="0" className={inputCls} placeholder={tr("Monthly instalment", "القسط الشهري")} value={f.installment} onChange={(e) => setF({ ...f, installment: e.target.value })} />
            <input type="month" className={inputCls} value={f.startMonth} onChange={(e) => setF({ ...f, startMonth: e.target.value })} title={tr("First deducted in", "أول خصم في")} />
            <button className={btnCls} onClick={add}><Plus className="h-4 w-4" />{tr("Add loan", "إضافة سلفة")}</button>
          </div>
        </div>
        {isLoading ? <Spinner /> : loans.length === 0 ? <p className="text-sm text-muted-foreground text-center py-4">{tr("No loans yet.", "لا توجد سلف بعد.")}</p> : (
          <ul className="space-y-2">
            {loans.map((l) => {
              const pct = l.amount > 0 ? Math.min(100, Math.round((l.paid / l.amount) * 100)) : 0;
              return (
                <li key={l.id} className="rounded-xl border border-border p-3">
                  <div className="flex items-center justify-between gap-2">
                    <div className="min-w-0"><div className="font-semibold truncate">{l.title}</div><div className="text-xs text-muted-foreground">{l.employeeName}</div></div>
                    <div className="flex items-center gap-2"><Badge tone={tone[l.status]}>{label[l.status]}</Badge>{l.status === "active" && <button className="text-xs text-red-600 hover:underline" onClick={() => stop(l)}>{tr("Stop", "إيقاف")}</button>}</div>
                  </div>
                  <div className="mt-2 h-2 rounded-full bg-muted overflow-hidden"><div className="h-full bg-primary rounded-full" style={{ width: `${pct}%` }} /></div>
                  <div className="mt-1.5 flex justify-between text-xs text-muted-foreground"><span>{tr("Repaid", "سُدّد")} {money(l.paid, currency)} / {money(l.amount, currency)}</span><span>{money(l.installment, currency)} {tr("/ month", "/ شهر")}</span></div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </Modal>
  );
}
