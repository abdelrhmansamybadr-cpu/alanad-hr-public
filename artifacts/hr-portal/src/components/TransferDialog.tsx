import { useEffect, useState } from "react";
import { toast } from "sonner";
import { api } from "@/lib/http";
import { Modal, Spinner, btnCls, btnGhost, inputCls, useTr } from "@/components/kit";

interface Company { id: number; name: string }
interface Dept { id: number; name: string }

/**
 * Move an employee or a department to another company of the group. The person is created in the new company (same details,
 * same login) and the old record is closed as "Transferred"; a department moves as a whole, with or without its people.
 */
export function TransferDialog({ kind, id, name, onClose, onMoved }: { kind: "employee" | "department"; id: number; name: string; onClose: () => void; onMoved: () => void }) {
  const tr = useTr();
  const [targets, setTargets] = useState<Company[] | null>(null);
  const [target, setTarget] = useState<number | null>(null);
  const [depts, setDepts] = useState<Dept[]>([]);
  const [dept, setDept] = useState<string>("");
  const [people, setPeople] = useState(true);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api<Company[]>(`/group/transfer-targets?kind=${kind}`).then(setTargets).catch((e) => { toast.error(e.message); onClose(); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind]);

  async function pick(cid: number) {
    setTarget(cid); setDept(""); setDepts([]);
    if (kind === "employee") api<Dept[]>(`/group/transfer-departments?company_id=${cid}`).then(setDepts).catch(() => {});
  }

  async function move() {
    const t = targets?.find((x) => x.id === target);
    if (!t) return;
    if (!confirm(tr(`Move ${name} to ${t.name}? This cannot be undone easily.`, `نقل ${name} إلى ${t.name}؟ لا يمكن التراجع بسهولة.`))) return;
    setBusy(true);
    try {
      await api("/group/transfer", "POST", { kind, id, targetCompanyId: target, ...(kind === "employee" && dept ? { departmentId: Number(dept) } : {}), ...(kind === "department" ? { moveMembers: people } : {}) });
      toast.success(tr(`Moved to ${t.name}`, `تم النقل إلى ${t.name}`));
      onMoved();
      onClose();
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }

  return (
    <Modal open title={`${tr("Move to another company", "نقل إلى شركة أخرى")} — ${name}`} onClose={onClose}>
      {targets === null ? <Spinner /> : (
        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">
            {kind === "employee"
              ? tr("The person is created in the company you choose with the same details and the same login. Their history (attendance, payroll…) stays here and this record is closed as “Transferred”.", "يُنشأ الشخص في الشركة التي تختارها بنفس البيانات ونفس حساب الدخول. يبقى سجله السابق (الحضور والرواتب…) هنا ويُغلق هذا السجل بحالة «منقول».")
              : tr("The department moves to the company you choose.", "ينتقل القسم إلى الشركة التي تختارها.")}
          </p>
          {targets.length === 0 ? <p className="text-sm text-muted-foreground">{tr("You do not have full access to another company, so you cannot move anything. Ask the Super Admin.", "ليس لديك صلاحية كاملة على شركة أخرى، لذلك لا يمكنك النقل. اطلب من المشرف العام.")}</p> : (
            <>
              <div className="space-y-1">
                {targets.map((c) => (
                  <label key={c.id} className="flex items-center gap-3 px-3 py-2 rounded-xl border border-border hover:bg-muted cursor-pointer text-sm">
                    <input type="radio" name="target" checked={target === c.id} onChange={() => pick(c.id)} />
                    <span className="font-medium">{c.name}</span>
                  </label>
                ))}
              </div>
              {kind === "employee" && target && depts.length > 0 && (
                <select className={inputCls} value={dept} onChange={(e) => setDept(e.target.value)}>
                  <option value="">{tr("No department (set it later)", "بدون قسم (يُحدد لاحقاً)")}</option>
                  {depts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                </select>
              )}
              {kind === "department" && (
                <label className="flex items-start gap-2 text-sm">
                  <input type="checkbox" className="mt-1" checked={people} onChange={(e) => setPeople(e.target.checked)} />
                  <span><b>{tr("Move its people too", "انقل أشخاصه أيضاً")}</b><br /><span className="text-xs text-muted-foreground">{tr("Each person is moved to the new company (with their login). If off, they stay here without a department.", "ينتقل كل شخص إلى الشركة الجديدة (مع حساب دخوله). إن أُلغي الخيار يبقون هنا بدون قسم.")}</span></span>
                </label>
              )}
            </>
          )}
          <div className="flex justify-end gap-2">
            <button className={btnGhost} onClick={onClose}>{tr("Cancel", "إلغاء")}</button>
            {targets.length > 0 && <button className={btnCls} disabled={busy || !target} onClick={move}>{tr("Move", "نقل")}</button>}
          </div>
        </div>
      )}
    </Modal>
  );
}
