import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Send, FileDown, Eye, AlertTriangle, CheckCircle2 } from "lucide-react";
import { api, downloadFile, authToken, ymd } from "@/lib/http";
import { Field, btnCls, btnGhost, cardCls, inputCls, useTr } from "@/components/kit";
import { useAuth } from "@/contexts/AuthContext";
import { type Template, parseTemplate, loadImages, renderCertificate, toJpeg, buildValues } from "@/lib/certRender";

export type Emp = { id: number; firstName: string; lastName: string; email: string; status: string; position?: string; departmentName?: string; startDate?: string; terminationDate?: string | null };

const TITLES: Record<string, [string, string]> = {
  experience: ["Certificate of Experience", "شهادة خبرة"],
  end_of_service: ["End of Service Certificate", "شهادة إنهاء خدمة"],
  clearance: ["Clearance Letter", "إخلاء طرف"],
  custom: ["Certificate", "شهادة"],
};

/** Open a protected file (PDF) in a new tab. */
export async function openProtected(path: string) {
  const r = await fetch(`/api${path}`, { headers: { Authorization: `Bearer ${authToken()}` } });
  if (!r.ok) throw new Error("Could not open the file");
  window.open(URL.createObjectURL(await r.blob()), "_blank");
}

export function CertIssue({ employees, templates, presetEmployee, onIssued }: { employees: Emp[]; templates: Template[]; presetEmployee: number | null; onIssued: () => void }) {
  const tr = useTr();
  const { company } = useAuth();
  const qc = useQueryClient();
  const [empId, setEmpId] = useState<number | "">(presetEmployee ?? "");
  const [filter, setFilter] = useState("");
  const [tplId, setTplId] = useState<number | "">(templates[0]?.id ?? "");
  const [title, setTitle] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState(ymd(new Date()));
  const [note, setNote] = useState("");
  const [sendEmail, setSendEmail] = useState(true);
  const [emailTo, setEmailTo] = useState("");
  const [closeMode, setCloseMode] = useState<"none" | "now" | "in" | "date">("none");
  const [closeDays, setCloseDays] = useState(7);
  const [closeDate, setCloseDate] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<any>(null);
  const preview = useRef<HTMLCanvasElement>(null);

  const emp = employees.find((e) => e.id === empId) ?? null;
  const tpl = templates.find((t) => t.id === tplId) ?? null;
  const lang = tpl?.lang ?? "en";
  const companyName = company?.name ?? "";

  useEffect(() => { if (!tplId && templates[0]?.id) setTplId(templates[0].id); }, [templates, tplId]);
  useEffect(() => { if (tpl) setTitle(TITLES[tpl.kind]?.[tpl.lang === "ar" ? 1 : 0] ?? TITLES.custom[0]); }, [tplId]);                // eslint-disable-line
  useEffect(() => { if (emp) { setStart((emp.startDate ?? "").slice(0, 10)); setEmailTo(emp.email); setEnd((emp.terminationDate ?? "").slice(0, 10) || ymd(new Date())); setDone(null); } }, [empId]); // eslint-disable-line

  const values = useMemo(
    () => emp ? buildValues(emp, { company: companyName, serial: "CERT-" + new Date().getFullYear() + "-????", issueDate: ymd(new Date()), startDate: start, endDate: end, lang, note }) : null,
    [emp, companyName, start, end, lang, note],
  );

  useEffect(() => {
    if (!tpl || !values) return;
    let on = true;
    loadImages(tpl).then((imgs) => {
      if (!on) return;
      const { canvas } = renderCertificate(tpl, values, imgs, 1);
      const c = preview.current;
      if (c) { c.width = canvas.width; c.height = canvas.height; c.getContext("2d")!.drawImage(canvas, 0, 0); }
    });
    return () => { on = false; };
  }, [tpl, values]);

  const list = employees.filter((e) => !filter || `${e.firstName} ${e.lastName} ${e.email}`.toLowerCase().includes(filter.toLowerCase()));
  const alreadyOut = emp?.status === "inactive";

  async function issue() {
    if (!emp || !tpl) return undefined;
    if (sendEmail && !/^\S+@\S+\.\S+$/.test(emailTo)) { toast.error(tr("Enter a valid e-mail address", "اكتب بريدًا إلكترونيًا صحيحًا")); return undefined; }
    if (closeMode === "date" && !closeDate) { toast.error(tr("Choose the closing date", "اختر تاريخ الإغلاق")); return undefined; }
    setBusy(true);
    try {
      const d = await api<any>("/certificates/draft", "POST", { employeeId: emp.id, templateId: tpl.id });
      const v = buildValues(emp, { company: d.company || companyName, serial: d.serial, issueDate: d.issueDate, startDate: start, endDate: end, lang, note });
      const imgs = await loadImages(tpl);
      const { canvas } = renderCertificate(tpl, v, imgs, 2);
      const res = await api<any>(`/certificates/${d.id}/issue`, "POST", {
        imageData: toJpeg(canvas, 0.92), title, width: tpl.width, height: tpl.height, values: JSON.stringify(v),
        sendEmail, emailTo: emailTo !== emp.email ? emailTo : undefined, leaveDate: end || undefined,
        close: closeMode === "none" || alreadyOut ? { mode: "none" } : { mode: closeMode, days: closeDays, date: closeDate },
      });
      setDone(res);
      qc.invalidateQueries({ queryKey: ["certs"] });
      qc.invalidateQueries({ queryKey: ["employees-all"] });
      onIssued();
      toast.success(tr("Certificate created", "تم إنشاء الشهادة"));
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }

  if (templates.length === 0) {
    return <div className={cardCls}><p className="text-muted-foreground">{tr("Create a design first (Designs tab) — start from a ready sample or upload your own certificate picture.", "أنشئ تصميمًا أولًا (تبويب التصاميم) — ابدأ من نموذج جاهز أو ارفع صورة شهادتك.")}</p></div>;
  }

  return (
    <div className="grid lg:grid-cols-[360px_minmax(0,1fr)] gap-5">
      <div className={cardCls + " space-y-4"}>
        <Field label={tr("Employee", "الموظف")}>
          <div className="space-y-2">
            <input className={inputCls} placeholder={tr("Search by name or e-mail…", "ابحث بالاسم أو البريد…")} value={filter} onChange={(e) => setFilter(e.target.value)} />
            <select className={inputCls} value={empId} onChange={(e) => setEmpId(e.target.value ? Number(e.target.value) : "")}>
              <option value="">{tr("Choose…", "اختر…")}</option>
              {list.map((e) => <option key={e.id} value={e.id}>{e.firstName} {e.lastName}{e.status === "inactive" ? ` (${tr("left", "غادر")})` : ""}</option>)}
            </select>
          </div>
        </Field>
        <Field label={tr("Design", "التصميم")}>
          <select className={inputCls} value={tplId} onChange={(e) => setTplId(Number(e.target.value))}>
            {templates.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        </Field>
        <Field label={tr("Title (used in the e-mail)", "العنوان (يظهر في البريد)")}><input className={inputCls} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label={tr("Started on", "تاريخ البدء")}><input type="date" className={inputCls} value={start} onChange={(e) => setStart(e.target.value)} /></Field>
          <Field label={tr("Leaving date", "تاريخ المغادرة")}><input type="date" className={inputCls} value={end} onChange={(e) => setEnd(e.target.value)} /></Field>
        </div>
        <Field label={tr("Extra note (optional, shows where {note} is placed)", "ملاحظة إضافية (اختياري، تظهر في مكان {note})")}><textarea rows={2} className={inputCls} value={note} onChange={(e) => setNote(e.target.value)} /></Field>

        <div className="border-t border-border pt-4 space-y-3">
          <label className="flex items-center gap-2 text-sm font-medium"><input type="checkbox" checked={sendEmail} onChange={(e) => setSendEmail(e.target.checked)} />{tr("E-mail it to the employee (PDF + picture)", "إرسالها للموظف بالبريد (PDF + صورة)")}</label>
          {sendEmail && <input type="email" dir="ltr" className={inputCls} value={emailTo} onChange={(e) => setEmailTo(e.target.value)} placeholder="name@example.com" />}
        </div>

        {emp && !alreadyOut && (
          <div className="border-t border-border pt-4 space-y-2">
            <p className="text-sm font-medium">{tr("Then, the employee's account:", "وبعد ذلك، حساب الموظف:")}</p>
            <select className={inputCls} value={closeMode} onChange={(e) => setCloseMode(e.target.value as any)}>
              <option value="none">{tr("Not now — remind me to close it", "ليس الآن — ذكّرني بإغلاقه")}</option>
              <option value="now">{tr("Close it right after sending", "أغلقه فور الإرسال")}</option>
              <option value="in">{tr("Close it after some days", "أغلقه بعد عدد من الأيام")}</option>
              <option value="date">{tr("Close it on a date", "أغلقه في تاريخ محدد")}</option>
            </select>
            {closeMode === "in" && (
              <div className="flex items-center gap-2 text-sm">
                {[1, 3, 7, 14, 30].map((d) => <button key={d} type="button" onClick={() => setCloseDays(d)} className={`px-3 py-1.5 rounded-full border ${closeDays === d ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}>{d}</button>)}
                <input type="number" min={1} max={365} className={inputCls + " w-20"} value={closeDays} onChange={(e) => setCloseDays(Math.max(1, Number(e.target.value)))} /> <span>{tr("days", "يوم")}</span>
              </div>
            )}
            {closeMode === "date" && <input type="date" className={inputCls} value={closeDate} min={ymd(new Date())} onChange={(e) => setCloseDate(e.target.value)} />}
            <p className="text-xs text-muted-foreground">{tr("When the account is closed the person can no longer sign in; the record and certificates are kept.", "عند إغلاق الحساب لا يستطيع الموظف تسجيل الدخول، وتبقى بياناته وشهاداته محفوظة.")}</p>
          </div>
        )}
        {alreadyOut && <p className="text-xs text-muted-foreground border-t border-border pt-3">{tr("This employee's account is already closed.", "حساب هذا الموظف مغلق بالفعل.")}</p>}

        <button className={btnCls + " w-full"} disabled={!emp || !tpl || busy} onClick={issue}>
          <Send className="h-4 w-4" />{busy ? tr("Creating…", "جارٍ الإنشاء…") : sendEmail ? tr("Create & send", "إنشاء وإرسال") : tr("Create certificate", "إنشاء الشهادة")}
        </button>
      </div>

      <div className="space-y-4 min-w-0">
        <div className={cardCls + " !p-3"}>
          {emp && tpl ? (
            <div className="w-full bg-muted/30 rounded-lg overflow-hidden border border-border" style={{ aspectRatio: `${tpl.width} / ${tpl.height}` }}>
              <canvas ref={preview} className="w-full h-full" />
            </div>
          ) : <p className="p-10 text-center text-muted-foreground">{tr("Choose an employee to see the certificate.", "اختر موظفًا لعرض الشهادة.")}</p>}
        </div>

        {done && (
          <div className={cardCls + " space-y-3"}>
            <div className="flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-emerald-600 mt-0.5" />
              <div className="text-sm space-y-1">
                <p className="font-semibold">{tr("Certificate", "الشهادة")} {done.certificate.serial} {tr("is ready.", "جاهزة.")}</p>
                {sendEmail && (done.emailed
                  ? <p className="text-emerald-700">{tr("E-mailed to", "تم الإرسال إلى")} {done.certificate.emailedTo}</p>
                  : <p className="text-amber-700 flex items-center gap-1"><AlertTriangle className="h-4 w-4" />{tr("The e-mail could not be sent — download it and send it yourself, or try again from History.", "تعذر إرسال البريد — حمّلها وأرسلها بنفسك أو أعد المحاولة من السجل.")}</p>)}
                {done.closure
                  ? <p>{tr("The account will be closed on", "سيتم إغلاق الحساب في")} <b>{String(done.closure.closeAt).slice(0, 16).replace("T", " ")}</b>. {tr("You can change or cancel this in History.", "يمكنك تغيير ذلك أو إلغاؤه من السجل.")}</p>
                  : emp && !alreadyOut && <p className="text-amber-700">{tr("The account is still open. You will be reminded to close it.", "الحساب ما زال مفتوحًا، وسنذكّرك بإغلاقه.")}</p>}
              </div>
            </div>
            <div className="flex flex-wrap gap-2">
              <button className={btnGhost} onClick={() => openProtected(`/certificates/${done.certificate.id}/file?type=pdf`).catch((e) => toast.error(e.message))}><Eye className="h-4 w-4" />{tr("View PDF", "عرض PDF")}</button>
              <button className={btnGhost} onClick={() => downloadFile(`/certificates/${done.certificate.id}/file?type=pdf&download=1`, `${done.certificate.serial}.pdf`).catch((e) => toast.error(e.message))}><FileDown className="h-4 w-4" />{tr("Download PDF", "تحميل PDF")}</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
