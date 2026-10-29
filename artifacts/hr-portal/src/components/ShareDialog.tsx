import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Building2 } from "lucide-react";
import { api } from "@/lib/http";
import { Modal, Spinner, btnCls, btnGhost, useTr } from "@/components/kit";

interface Target { id: number; name: string; shared: boolean }

/**
 * "Share with other companies" for one employee or department. The HR of the owning company ticks the companies of the group
 * that may also see it (employee: basic details, read-only; department: their HR can put their own people in it).
 */
export function ShareDialog({ kind, id, name, onClose, onSaved }: { kind: "employee" | "department"; id: number; name: string; onClose: () => void; onSaved?: () => void }) {
  const tr = useTr();
  const [companies, setCompanies] = useState<Target[] | null>(null);
  const [on, setOn] = useState<number[]>([]);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api<{ companies: Target[] }>(`/group/shares?kind=${kind}&id=${id}`)
      .then((d) => { setCompanies(d.companies); setOn(d.companies.filter((c) => c.shared).map((c) => c.id)); })
      .catch((e) => { toast.error(e.message); onClose(); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind, id]);

  async function save() {
    setBusy(true);
    try {
      await api("/group/shares", "PUT", { kind, id, companyIds: on });
      toast.success(tr("Saved", "تم الحفظ"));
      onSaved?.();
      onClose();
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }

  return (
    <Modal open title={`${tr("Share with other companies", "مشاركة مع شركات أخرى")} — ${name}`} onClose={onClose}>
      {companies === null ? <Spinner /> : (
        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">
            {kind === "employee"
              ? tr("This person will also appear (basic details only, read-only) in the companies you tick.", "سيظهر هذا الشخص أيضاً (البيانات الأساسية فقط، للعرض فقط) في الشركات التي تحددها.")
              : tr("The companies you tick will see this department and can put their own people in it. Only your company can change it.", "الشركات التي تحددها سترى هذا القسم ويمكنها إضافة موظفيها إليه. شركتك فقط تستطيع تعديله.")}
          </p>
          {companies.length === 0 ? <p className="text-sm text-muted-foreground">{tr("There are no other companies in your group.", "لا توجد شركات أخرى في مجموعتك.")}</p> : (
            <div className="space-y-1">
              {companies.map((c) => (
                <label key={c.id} className="flex items-center gap-3 px-3 py-2 rounded-xl border border-border hover:bg-muted cursor-pointer text-sm">
                  <input type="checkbox" checked={on.includes(c.id)} onChange={() => setOn(on.includes(c.id) ? on.filter((x) => x !== c.id) : [...on, c.id])} />
                  <Building2 className="h-4 w-4 text-muted-foreground" />
                  <span className="font-medium">{c.name}</span>
                </label>
              ))}
            </div>
          )}
          <div className="flex justify-end gap-2">
            <button className={btnGhost} onClick={onClose}>{tr("Cancel", "إلغاء")}</button>
            {companies.length > 0 && <button className={btnCls} disabled={busy} onClick={save}>{tr("Save", "حفظ")}</button>}
          </div>
        </div>
      )}
    </Modal>
  );
}
