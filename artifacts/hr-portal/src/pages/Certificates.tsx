import { useEffect, useMemo, useRef, useState } from "react";
import { useSearch } from "wouter";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Plus, Pencil, Trash2, Copy, Eye, FileDown, Mail, XCircle, Power, Sparkles } from "lucide-react";
import { api, downloadFile } from "@/lib/http";
import { Badge, Empty, Modal, PageHeader, Spinner, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { CertDesigner } from "@/components/CertDesigner";
import { CertIssue, openProtected, type Emp } from "@/components/CertIssue";
import { type Template, emptyLayout, loadImages, parseTemplate, renderCertificate, sampleValues, templatePayload } from "@/lib/certRender";

type Tab = "issue" | "designs" | "history";

/** A small picture of a design (drawn with sample data). */
function Thumb({ t }: { t: Template }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    let on = true;
    loadImages(t).then((imgs) => {
      if (!on) return;
      const { canvas } = renderCertificate(t, sampleValues(t.lang), imgs, 0.5);
      const c = ref.current;
      if (c) { c.width = canvas.width; c.height = canvas.height; c.getContext("2d")!.drawImage(canvas, 0, 0); }
    });
    return () => { on = false; };
  }, [t]);
  return <div className="w-full rounded-lg overflow-hidden border border-border bg-muted/30" style={{ aspectRatio: `${t.width} / ${t.height}` }}><canvas ref={ref} className="w-full h-full" /></div>;
}

const blank = (lang: "ar" | "en"): Template => ({ name: "", kind: "custom", lang, width: 1123, height: 794, bgColor: "#ffffff", bgAssetId: null, layout: emptyLayout() });

export default function Certificates() {
  const tr = useTr();
  const qc = useQueryClient();
  const search = useSearch();
  const preset = Number(new URLSearchParams(search).get("employee")) || null;
  const [tab, setTab] = useState<Tab>("issue");
  const [editing, setEditing] = useState<Template | null>(null);
  const [saving, setSaving] = useState(false);
  const [sampleOpen, setSampleOpen] = useState(false);

  const emps = useQuery<Emp[]>({ queryKey: ["employees-all"], queryFn: () => api("/employees") });
  const tpls = useQuery<any[]>({ queryKey: ["certs", "templates"], queryFn: () => api("/certificates/templates") });
  const hist = useQuery<any[]>({ queryKey: ["certs", "history"], queryFn: () => api("/certificates"), enabled: tab === "history" });
  const clos = useQuery<any[]>({ queryKey: ["certs", "closures"], queryFn: () => api("/certificates/closures"), enabled: tab === "history" });
  const samples = useQuery<any[]>({ queryKey: ["certs", "samples"], queryFn: () => api("/certificates/samples"), enabled: sampleOpen, staleTime: Infinity });

  const templates = useMemo(() => (tpls.data ?? []).map(parseTemplate), [tpls.data]);
  const refresh = () => qc.invalidateQueries({ queryKey: ["certs"] });
  const previewVals = useMemo(() => (editing ? sampleValues(editing.lang) : sampleValues("en")), [editing?.lang]); // eslint-disable-line

  async function save() {
    if (!editing) return undefined;
    if (!editing.name.trim()) { toast.error(tr("Give the design a name", "اكتب اسمًا للتصميم")); return undefined; }
    setSaving(true);
    try {
      if (editing.id) await api(`/certificates/templates/${editing.id}`, "PUT", templatePayload(editing));
      else await api("/certificates/templates", "POST", templatePayload(editing));
      toast.success(tr("Design saved", "تم حفظ التصميم"));
      setEditing(null); refresh();
    } catch (e: any) { toast.error(e.message); } finally { setSaving(false); }
  }

  async function removeTemplate(t: Template) {
    if (!confirm(tr(`Delete the design "${t.name}"? Certificates already issued are not affected.`, `حذف التصميم «${t.name}»؟ الشهادات الصادرة لا تتأثر.`))) return;
    try { await api(`/certificates/templates/${t.id}`, "DELETE"); refresh(); } catch (e: any) { toast.error(e.message); }
  }

  async function resend(c: any) {
    const to = prompt(tr("Send to which e-mail?", "إرسال إلى أي بريد؟"), c.emailedTo || "");
    if (!to) return;
    try {
      const r = await api<any>(`/certificates/${c.id}/resend`, "POST", { emailTo: to });
      r.emailed ? toast.success(tr("Sent to ", "تم الإرسال إلى ") + r.to) : toast.error(tr("The e-mail could not be sent", "تعذر إرسال البريد"));
      refresh();
    } catch (e: any) { toast.error(e.message); }
  }

  async function planClosing(c: any) {
    const days = prompt(tr("Close the account after how many days? (0 = now)", "إغلاق الحساب بعد كم يوم؟ (0 = الآن)"), "7");
    if (days === null) return;
    const n = Math.max(0, Math.floor(Number(days) || 0));
    try {
      await api("/certificates/closures", "POST", { employeeId: c.employeeId, certificateId: c.id, leaveDate: c.leaveDate || undefined, mode: n === 0 ? "now" : "in", days: n });
      toast.success(n === 0 ? tr("Account closed", "تم إغلاق الحساب") : tr("Closing planned", "تمت جدولة الإغلاق")); refresh(); qc.invalidateQueries({ queryKey: ["employees-all"] });
    } catch (e: any) { toast.error(e.message); }
  }

  async function closureAction(id: number, now: boolean) {
    try {
      if (now) { if (!confirm(tr("Close this account now?", "إغلاق هذا الحساب الآن؟"))) return; await api(`/certificates/closures/${id}/close-now`, "POST"); }
      else await api(`/certificates/closures/${id}`, "DELETE");
      refresh(); qc.invalidateQueries({ queryKey: ["employees-all"] });
    } catch (e: any) { toast.error(e.message); }
  }

  // --------------------------------------------------------------- the designer takes the whole page
  if (editing) {
    return (
      <div className="space-y-5">
        <PageHeader title={editing.id ? tr("Edit design", "تعديل التصميم") : tr("New design", "تصميم جديد")} subtitle={tr("Place the texts, upload your own certificate picture, add a logo or signature.", "ضع النصوص، وارفع صورة شهادتك، وأضف شعارًا أو توقيعًا.")}>
          <button className={btnGhost} onClick={() => setEditing(null)}>{tr("Cancel", "إلغاء")}</button>
          <button className={btnCls} disabled={saving} onClick={save}>{saving ? tr("Saving…", "جارٍ الحفظ…") : tr("Save design", "حفظ التصميم")}</button>
        </PageHeader>
        <CertDesigner value={editing} onChange={setEditing} values={previewVals} />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader title={tr("Certificates", "الشهادات")} subtitle={tr("Create a leaving certificate, e-mail it to the employee and close the account when the time comes.", "أنشئ شهادة المغادرة وأرسلها للموظف بالبريد ثم أغلق حسابه في الوقت المناسب.")} />

      <div className="flex gap-2 border-b border-border">
        {([["issue", tr("Create certificate", "إنشاء شهادة")], ["designs", tr("Designs", "التصاميم")], ["history", tr("History & accounts", "السجل والحسابات")]] as [Tab, string][]).map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)} className={`px-4 py-2 text-sm font-medium -mb-px border-b-2 ${tab === k ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground"}`}>{l}</button>
        ))}
      </div>

      {tab === "issue" && (tpls.isLoading || emps.isLoading ? <Spinner /> : <CertIssue employees={emps.data ?? []} templates={templates} presetEmployee={preset} onIssued={refresh} />)}

      {tab === "designs" && (
        <div className="space-y-4">
          <div className="flex flex-wrap gap-2">
            <button className={btnCls} onClick={() => setEditing(blank("ar"))}><Plus className="h-4 w-4" />{tr("New blank design", "تصميم فارغ جديد")}</button>
            <button className={btnGhost} onClick={() => setSampleOpen(true)}><Sparkles className="h-4 w-4" />{tr("Start from a sample", "البدء من نموذج جاهز")}</button>
          </div>
          {tpls.isLoading ? <Spinner /> : templates.length === 0 ? <Empty text={tr("No designs yet. Start from a sample, or upload your own certificate picture with an empty place for the name.", "لا توجد تصاميم بعد. ابدأ من نموذج، أو ارفع صورة شهادتك بها مكان فارغ للاسم.")} /> : (
            <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-5">
              {templates.map((t) => (
                <div key={t.id} className={cardCls + " space-y-3"}>
                  <Thumb t={t} />
                  <div className="flex items-center justify-between gap-2">
                    <div className="min-w-0"><p className="font-semibold truncate">{t.name}</p><Badge tone="gray">{t.lang === "ar" ? "العربية" : "English"}</Badge></div>
                    <div className="flex gap-1">
                      <button className="p-2 rounded-lg hover:bg-muted" title={tr("Edit", "تعديل")} onClick={() => setEditing(t)}><Pencil className="h-4 w-4" /></button>
                      <button className="p-2 rounded-lg hover:bg-muted" title={tr("Duplicate", "نسخ")} onClick={() => setEditing({ ...t, id: undefined, name: t.name + " (2)" })}><Copy className="h-4 w-4" /></button>
                      <button className="p-2 rounded-lg hover:bg-destructive/10 text-destructive" title={tr("Delete", "حذف")} onClick={() => removeTemplate(t)}><Trash2 className="h-4 w-4" /></button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
          <Modal open={sampleOpen} title={tr("Choose a sample", "اختر نموذجًا")} onClose={() => setSampleOpen(false)} wide>
            {samples.isLoading ? <Spinner /> : (
              <div className="grid sm:grid-cols-2 gap-4">
                {(samples.data ?? []).map((s, i) => { const t = parseTemplate(s); return (
                  <button key={i} className="text-start space-y-2 p-2 rounded-xl border border-border hover:border-primary" onClick={() => { setSampleOpen(false); setEditing(t); }}>
                    <Thumb t={t} /><p className="font-medium text-sm">{t.name}</p>
                  </button>
                ); })}
              </div>
            )}
          </Modal>
        </div>
      )}

      {tab === "history" && (
        <div className="space-y-6">
          <div className={cardCls + " !p-0 overflow-hidden"}>
            <div className="px-5 py-3 border-b border-border font-semibold">{tr("Account closings", "إغلاق الحسابات")}</div>
            {clos.isLoading ? <Spinner /> : (clos.data ?? []).length === 0 ? <p className="p-5 text-sm text-muted-foreground">{tr("Nothing planned. When you create a certificate you can choose when the account closes.", "لا شيء مجدول. عند إنشاء شهادة يمكنك اختيار موعد إغلاق الحساب.")}</p> : (
              <div className="divide-y divide-border">
                {(clos.data ?? []).map((c) => (
                  <div key={c.id} className="flex flex-wrap items-center justify-between gap-3 px-5 py-3 text-sm">
                    <div><b>{c.employeeName}</b> <span className="text-muted-foreground">— {String(c.closeAt).slice(0, 16).replace("T", " ")}</span></div>
                    {c.status === "pending" ? (
                      <div className="flex items-center gap-2"><Badge tone="amber">{tr("Planned", "مجدول")}</Badge>
                        <button className={btnGhost} onClick={() => closureAction(c.id, true)}><Power className="h-4 w-4" />{tr("Close now", "إغلاق الآن")}</button>
                        <button className={btnGhost} onClick={() => closureAction(c.id, false)}><XCircle className="h-4 w-4" />{tr("Cancel", "إلغاء")}</button></div>
                    ) : <Badge tone="gray">{tr("Closed", "تم الإغلاق")}</Badge>}
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className={cardCls + " !p-0 overflow-x-auto"}>
            <div className="px-5 py-3 border-b border-border font-semibold">{tr("Issued certificates", "الشهادات الصادرة")}</div>
            {hist.isLoading ? <Spinner /> : (hist.data ?? []).length === 0 ? <p className="p-5 text-sm text-muted-foreground">{tr("No certificates yet.", "لا توجد شهادات بعد.")}</p> : (
              <table className="w-full text-sm">
                <thead><tr className="text-start text-xs text-muted-foreground border-b border-border"><th className="px-5 py-2 text-start">{tr("No.", "الرقم")}</th><th className="px-5 py-2 text-start">{tr("Employee", "الموظف")}</th><th className="px-5 py-2 text-start">{tr("Certificate", "الشهادة")}</th><th className="px-5 py-2 text-start">{tr("Sent to", "أُرسلت إلى")}</th><th className="px-5 py-2" /></tr></thead>
                <tbody className="divide-y divide-border">
                  {(hist.data ?? []).map((c) => (
                    <tr key={c.id}>
                      <td className="px-5 py-3 font-mono text-xs">{c.serial}</td>
                      <td className="px-5 py-3">{c.employeeName}{c.employeeStatus === "inactive" && <> <Badge tone="gray">{tr("left", "غادر")}</Badge></>}</td>
                      <td className="px-5 py-3">{c.title}<div className="text-xs text-muted-foreground">{String(c.issuedAt).slice(0, 10)}</div></td>
                      <td className="px-5 py-3 text-xs">{c.emailedTo || <span className="text-muted-foreground">—</span>}</td>
                      <td className="px-5 py-3"><div className="flex justify-end gap-1">
                        <button className="p-2 rounded-lg hover:bg-muted" title={tr("View", "عرض")} onClick={() => openProtected(`/certificates/${c.id}/file?type=pdf`).catch((e) => toast.error(e.message))}><Eye className="h-4 w-4" /></button>
                        <button className="p-2 rounded-lg hover:bg-muted" title={tr("Download", "تحميل")} onClick={() => downloadFile(`/certificates/${c.id}/file?type=pdf&download=1`, `${c.serial}.pdf`).catch((e) => toast.error(e.message))}><FileDown className="h-4 w-4" /></button>
                        <button className="p-2 rounded-lg hover:bg-muted" title={tr("Send again", "إرسال مرة أخرى")} onClick={() => resend(c)}><Mail className="h-4 w-4" /></button>
                        {c.employeeStatus !== "inactive" && <button className="p-2 rounded-lg hover:bg-muted" title={tr("Plan closing the account", "جدولة إغلاق الحساب")} onClick={() => planClosing(c)}><Power className="h-4 w-4" /></button>}
                      </div></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
