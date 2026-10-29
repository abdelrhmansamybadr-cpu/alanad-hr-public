import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { api } from "@/lib/http";
import { inputCls, useTr } from "@/components/kit";

/** HR: how this person records attendance (company rule / another place / no place check), block them, and see who tried away from the workplace. */
export function AttendanceAccess({ e }: { e: any }) {
  const tr = useTr();
  const qc = useQueryClient();
  const [mode, setMode] = useState<string>(e.attendanceMode ?? "company");
  const [rule, setRule] = useState<string>(e.attendanceRuleId ? String(e.attendanceRuleId) : "");
  const [blocked, setBlocked] = useState<boolean>(!!e.attendanceBlocked);
  const [reason, setReason] = useState<string>(e.attendanceBlockReason ?? "");
  const [busy, setBusy] = useState(false);
  const rules = useQuery<any[]>({ queryKey: ["attendance-rules"], queryFn: async () => { const r: any = await api("/attendance-rules"); return Array.isArray(r) ? r : (r?.data ?? []); } });
  const attempts = useQuery<any[]>({ queryKey: ["att-attempts", e.id], queryFn: async () => { const r: any = await api(`/employees/${e.id}/attendance-attempts`); return Array.isArray(r) ? r : (r?.data ?? []); } });
  useEffect(() => { setMode(e.attendanceMode ?? "company"); setRule(e.attendanceRuleId ? String(e.attendanceRuleId) : ""); setBlocked(!!e.attendanceBlocked); setReason(e.attendanceBlockReason ?? ""); }, [e.id]);

  const save = async () => {
    setBusy(true);
    try {
      await api(`/employees/${e.id}/attendance-access`, "PUT", { attendanceMode: mode, attendanceRuleId: mode === "rule" ? Number(rule) : null, attendanceBlocked: blocked, attendanceBlockReason: blocked ? reason : "" });
      toast.success(tr("Attendance access saved", "تم حفظ إعدادات الحضور"));
      qc.invalidateQueries({ queryKey: ["/employees"] }); qc.invalidateQueries();
    } catch (err: any) { toast.error(err?.message ?? "Error"); }
    setBusy(false);
  };

  const lab = "block text-xs text-muted-foreground mb-1";
  return (
    <div className="rounded-xl border border-border p-4 space-y-3 bg-muted/20">
      <p className="text-sm font-semibold">{tr("Attendance", "الحضور")}</p>
      <div>
        <label className={lab}>{tr("How this person records attendance", "طريقة تسجيل الحضور لهذا الموظف")}</label>
        <select className={inputCls} value={mode} onChange={(x) => setMode(x.target.value)}>
          <option value="company">{tr("Same as the company (settings page)", "مثل باقي الشركة (من صفحة الإعدادات)")}</option>
          <option value="rule">{tr("Another place / method (exception)", "مكان أو طريقة أخرى (استثناء)")}</option>
          <option value="free">{tr("Anywhere, no place check (exception)", "من أي مكان بدون فحص الموقع (استثناء)")}</option>
        </select>
      </div>
      {mode === "rule" && (
        <div>
          <label className={lab}>{tr("Attendance rule", "قاعدة الحضور")}</label>
          <select className={inputCls} value={rule} onChange={(x) => setRule(x.target.value)}>
            <option value="">—</option>
            {(rules.data ?? []).map((r: any) => <option key={r.id} value={r.id}>{r.name}</option>)}
          </select>
        </div>
      )}
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={blocked} onChange={(x) => setBlocked(x.target.checked)} />
        <span className="font-medium text-red-700">{tr("Block this person from recording attendance", "منع هذا الموظف من تسجيل الحضور")}</span>
      </label>
      {blocked && <input className={inputCls} placeholder={tr("Reason (shown to the employee)", "السبب (يظهر للموظف)")} value={reason} onChange={(x) => setReason(x.target.value)} />}
      <button type="button" disabled={busy || (mode === "rule" && !rule)} onClick={save} className="px-4 py-2 rounded-lg bg-primary text-primary-foreground text-sm font-semibold disabled:opacity-50">
        {tr("Save attendance access", "حفظ إعدادات الحضور")}
      </button>
      {(attempts.data ?? []).length > 0 && (
        <div className="pt-2 border-t border-border">
          <p className="text-xs font-semibold text-amber-800 mb-1">{tr("Tried to record attendance away from the workplace", "حاول تسجيل الحضور بعيداً عن مقر العمل")}</p>
          <ul className="text-xs text-muted-foreground space-y-0.5 max-h-28 overflow-auto">
            {(attempts.data ?? []).map((a: any) => <li key={a.id}>{String(a.createdAt ?? a.created_at).slice(0, 16)} · {a.distanceM ?? a.distance_m ? `${a.distanceM ?? a.distance_m} m` : ""} · {a.message}</li>)}
          </ul>
        </div>
      )}
    </div>
  );
}
