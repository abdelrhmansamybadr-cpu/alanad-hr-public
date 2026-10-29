import React, { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { AlertTriangle, CheckCircle2, Copy, Mail, MessageSquare, Send, KeyRound } from "lucide-react";
import { api } from "@/lib/http";
import { Modal, Spinner, btnCls, btnGhost, inputCls, useTr } from "@/components/kit";

export type Messaging = { email: { transport: string; smtp: boolean }; sms: { configured: boolean; provider: string } };

/** Which ways of sending work on this server (e-mail through SMTP or the host's mail, SMS only with a provider). */
export function useMessaging() {
  return useQuery<Messaging>({ queryKey: ["messaging"], queryFn: () => api("/company/messaging"), staleTime: 60_000 });
}

const copy = async (text: string, ok: string) => { try { await navigator.clipboard.writeText(text); toast.success(ok); } catch { /* ignore */ } };

/** What is wrong with an employee's record, in words. */
export function missingLabels(tr: (en: string, ar: string) => string, missing: string[] | undefined): string[] {
  const m: Record<string, [string, string]> = {
    contact: ["e-mail or mobile number", "البريد أو رقم الجوال"],
    department: ["department", "القسم"],
    position: ["job title", "المسمى الوظيفي"],
    start_date: ["start date", "تاريخ البدء"],
    startDate: ["start date", "تاريخ البدء"],
    salary: ["salary", "الراتب"],
  };
  return (missing ?? []).map((k) => (m[k] ? tr(m[k][0], m[k][1]) : k));
}

/** Invite one person: choose e-mail or SMS (or only show the one-time code). Nothing is sent until the button is pressed. */
export function InviteModal({ employee, onClose }: { employee: any; onClose: () => void }) {
  const tr = useTr();
  const { data: msg } = useMessaging();
  const hasMail = !!employee.hasEmail, hasPhone = !!employee.hasPhone;
  const [via, setVia] = useState<"email" | "sms" | "none">(hasMail ? "email" : hasPhone ? "sms" : "none");
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<any>(null);
  const qc = useQueryClient();
  const smsOff = msg && !msg.sms.configured;
  const name = `${employee.firstName} ${employee.lastName}`;

  async function go() {
    setBusy(true);
    try {
      const r = await api<any>(`/employees/${employee.id}/invite`, "POST", { sendVia: via });
      setRes(r);
      qc.invalidateQueries({ queryKey: ["employees-all"] });
      qc.invalidateQueries({ queryKey: ["/api/employees"] });
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }

  const row = (id: "email" | "sms" | "none", icon: React.ReactNode, title: string, sub: string, disabled = false) => (
    <label key={id} className={`flex items-start gap-3 p-3 rounded-xl border cursor-pointer ${via === id ? "border-primary bg-primary/5" : "border-border"} ${disabled ? "opacity-50 cursor-not-allowed" : ""}`}>
      <input type="radio" name="via" className="mt-1" disabled={disabled} checked={via === id} onChange={() => setVia(id)} />
      <span className="mt-0.5">{icon}</span>
      <span className="text-sm"><b>{title}</b><span className="block text-xs text-muted-foreground">{sub}</span></span>
    </label>
  );

  return (
    <Modal open title={tr(`Invite ${name}`, `دعوة ${name}`)} onClose={onClose}>
      {!res ? (
        <div className="space-y-4 text-sm">
          <p className="text-muted-foreground">{employee.hasAccount
            ? tr("This person already has an account. A new code lets them choose a new password.", "لدى الموظف حساب بالفعل. الرمز الجديد يسمح له باختيار كلمة مرور جديدة.")
            : tr("The person gets their username, the company and a one-time code to create their own password.", "يصل للموظف اسم المستخدم واسم الشركة ورمز لمرة واحدة لإنشاء كلمة المرور بنفسه.")}</p>
          <div className="space-y-2">
            {row("email", <Mail className="h-4 w-4" />, tr("Send by e-mail", "إرسال بالبريد الإلكتروني"), hasMail ? employee.email : tr("No e-mail address yet", "لا يوجد بريد إلكتروني"), !hasMail)}
            {row("sms", <MessageSquare className="h-4 w-4" />, tr("Send by SMS", "إرسال برسالة نصية"), hasPhone ? employee.phone + (smsOff ? " — " + tr("SMS is not set up on the server yet", "الرسائل النصية غير مفعّلة على الخادم بعد") : "") : tr("No mobile number yet", "لا يوجد رقم جوال"), !hasPhone || !!smsOff)}
            {row("none", <KeyRound className="h-4 w-4" />, tr("Do not send — just show me the code", "لا ترسل — فقط أظهر لي الرمز"), tr("You can give it to the person yourself", "يمكنك إعطاؤه للموظف بنفسك"))}
          </div>
          {msg && msg.email.transport === "php_mail" && via === "email" && (
            <p className="text-xs text-amber-700 flex items-start gap-1"><AlertTriangle className="h-4 w-4 shrink-0" />{tr("E-mail goes through the hosting's basic mail, which may land in spam. A proper sender account (SMTP) makes it reliable.", "البريد يخرج عبر بريد الاستضافة الأساسي وقد يصل إلى الرسائل غير المرغوبة. حساب إرسال (SMTP) يجعله موثوقًا.")}</p>
          )}
          <div className="flex justify-end gap-2">
            <button className={btnGhost} onClick={onClose}>{tr("Cancel", "إلغاء")}</button>
            <button className={btnCls} disabled={busy} onClick={go}><Send className="h-4 w-4" />{via === "none" ? tr("Create the code", "إنشاء الرمز") : tr("Send now", "إرسال الآن")}</button>
          </div>
        </div>
      ) : (
        <div className="space-y-4 text-sm">
          {via !== "none" && (res.sent
            ? <p className="flex items-center gap-2 text-emerald-700"><CheckCircle2 className="h-5 w-5" />{res.channel === "sms" ? tr("Text message sent to", "تم إرسال رسالة نصية إلى") + " " + res.phone : tr("E-mail sent to", "تم إرسال البريد إلى") + " " + res.email}</p>
            : <p className="flex items-start gap-2 text-amber-700"><AlertTriangle className="h-5 w-5 shrink-0" /><span>{tr("It could not be sent:", "تعذر الإرسال:")} {res.error}<br />{tr("Give the person the code below instead.", "أعطِ الموظف الرمز أدناه بدلًا من ذلك.")}</span></p>)}
          <div className="rounded-xl bg-muted/40 p-4 space-y-2">
            <p><span className="text-muted-foreground">{tr("Username", "اسم المستخدم")}:</span> <b dir="ltr">{res.username}</b></p>
            <div className="flex items-center gap-3">
              <span className="text-muted-foreground">{tr("One-time code", "الرمز (يُستخدم مرة واحدة)")}:</span>
              <b className="text-2xl tracking-[0.3em]" dir="ltr">{res.code}</b>
              <button className={btnGhost + " !px-2 !py-1"} onClick={() => copy(res.code, tr("Code copied", "تم نسخ الرمز"))}><Copy className="h-4 w-4" /></button>
            </div>
            <p className="text-xs text-muted-foreground">{tr(`Valid for ${res.expiresInDays} day(s). It works once.`, `صالح لمدة ${res.expiresInDays} يوم. يعمل مرة واحدة فقط.`)}</p>
          </div>
          <div className="flex justify-end"><button className={btnCls} onClick={onClose}>{tr("Done", "تم")}</button></div>
        </div>
      )}
    </Modal>
  );
}

/** "Send everyone their invitation" — shows what would happen first, then sends only after an explicit confirmation. */
export function InviteAllModal({ onClose }: { onClose: () => void }) {
  const tr = useTr();
  const qc = useQueryClient();
  const status = useQuery<any>({ queryKey: ["invite-status"], queryFn: () => api("/employees/invite-status"), gcTime: 0 });
  const [via, setVia] = useState<"auto" | "email" | "sms">("auto");
  const [again, setAgain] = useState(false);
  const [sure, setSure] = useState(false);
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<any>(null);
  const c = status.data?.summary;
  const ch = status.data?.channels;

  async function send() {
    setBusy(true);
    try {
      setRes(await api("/employees/invite-all", "POST", { confirm: true, sendVia: via, includeInvited: again }));
      qc.invalidateQueries({ queryKey: ["employees-all"] }); qc.invalidateQueries({ queryKey: ["/api/employees"] }); qc.invalidateQueries({ queryKey: ["invite-status"] });
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  }

  return (
    <Modal open title={tr("Send invitations to everyone", "إرسال الدعوات للجميع")} onClose={onClose}>
      {status.isLoading ? <Spinner /> : !c ? <p className="text-sm text-destructive">{tr("Could not load the numbers.", "تعذر تحميل الأرقام.")}</p> : res ? (
        <div className="space-y-3 text-sm">
          <p className="flex items-center gap-2 text-emerald-700"><CheckCircle2 className="h-5 w-5" />{tr(`${res.sent} invitation(s) sent.`, `تم إرسال ${res.sent} دعوة.`)}</p>
          <ul className="text-muted-foreground list-disc ps-5 space-y-1">
            {res.skippedNoContact > 0 && <li>{tr(`${res.skippedNoContact} have no e-mail or mobile number yet — complete them first.`, `${res.skippedNoContact} بلا بريد أو رقم جوال بعد — أكمل بياناتهم أولًا.`)}</li>}
            {res.skippedAlreadyInvited > 0 && <li>{tr(`${res.skippedAlreadyInvited} were invited before and were not sent again.`, `${res.skippedAlreadyInvited} تمت دعوتهم سابقًا ولم تُرسل لهم مرة أخرى.`)}</li>}
            {res.skippedHasAccount > 0 && <li>{tr(`${res.skippedHasAccount} already have an account.`, `${res.skippedHasAccount} لديهم حساب بالفعل.`)}</li>}
          </ul>
          {res.failed?.length > 0 && (
            <div className="rounded-xl bg-amber-50 text-amber-800 p-3"><b>{tr("Not sent:", "لم تُرسل:")}</b>
              <ul className="list-disc ps-5">{res.failed.map((f: any) => <li key={f.id}>{f.name} — {f.error}</li>)}</ul></div>
          )}
          <div className="flex justify-end"><button className={btnCls} onClick={onClose}>{tr("Done", "تم")}</button></div>
        </div>
      ) : (
        <div className="space-y-4 text-sm">
          <div className="grid grid-cols-2 gap-3">
            {[[tr("Waiting for an account", "بانتظار إنشاء حساب"), c.pending], [tr("Ready to invite", "جاهزون للدعوة"), c.ready], [tr("By e-mail", "بالبريد"), c.byEmail], [tr("By SMS only", "بالرسائل فقط"), c.bySmsOnly], [tr("No contact yet", "بلا وسيلة تواصل"), c.noContact], [tr("Already invited", "تمت دعوتهم"), c.alreadyInvited]].map(([l, n], i) => (
              <div key={i} className="rounded-xl border border-border p-3"><div className="text-xs text-muted-foreground">{l as string}</div><div className="text-2xl font-bold">{n as number}</div></div>
            ))}
          </div>
          {c.noContact > 0 && <p className="text-xs text-amber-700 flex items-start gap-1"><AlertTriangle className="h-4 w-4 shrink-0" />{tr(`${c.noContact} employee(s) have no e-mail or mobile number, so they will be skipped until you complete their data.`, `${c.noContact} موظف بلا بريد أو رقم جوال وسيتم تخطيهم حتى تكمل بياناتهم.`)}</p>}
          <div className="space-y-2">
            <label className="flex items-center gap-2"><input type="radio" checked={via === "auto"} onChange={() => setVia("auto")} />{tr("Each person the best way (e-mail first, then SMS)", "لكل شخص بالأنسب (البريد أولًا ثم الرسائل)")}</label>
            <label className="flex items-center gap-2"><input type="radio" checked={via === "email"} onChange={() => setVia("email")} />{tr("Only e-mail", "بالبريد فقط")}</label>
            <label className={`flex items-center gap-2 ${ch && !ch.sms ? "opacity-50" : ""}`}><input type="radio" disabled={!!ch && !ch.sms} checked={via === "sms"} onChange={() => setVia("sms")} />{tr("Only SMS", "بالرسائل النصية فقط")}{ch && !ch.sms ? ` — ${tr("not set up yet", "غير مفعّلة بعد")}` : ""}</label>
          </div>
          {ch && !ch.smtp && <p className="text-xs text-amber-700 flex items-start gap-1"><AlertTriangle className="h-4 w-4 shrink-0" />{tr("E-mail uses the hosting's basic mail (may land in spam). Set up a sender account for reliable delivery.", "البريد يستخدم بريد الاستضافة الأساسي (قد يصل إلى الرسائل غير المرغوبة). فعّل حساب إرسال لضمان الوصول.")}</p>}
          {c.alreadyInvited > 0 && <label className="flex items-center gap-2"><input type="checkbox" checked={again} onChange={(e) => setAgain(e.target.checked)} />{tr("Also send again to the ones already invited (their old code stops working)", "أرسل أيضًا لمن تمت دعوتهم سابقًا (سيتوقف رمزهم القديم)")}</label>}
          <label className="flex items-start gap-2 rounded-xl bg-red-50 text-red-800 p-3"><input type="checkbox" className="mt-1" checked={sure} onChange={(e) => setSure(e.target.checked)} /><span>{tr(`Yes — send the messages to ${again ? c.ready : c.ready - c.alreadyInvited} people now. This cannot be undone.`, `نعم — أرسل الرسائل إلى ${again ? c.ready : c.ready - c.alreadyInvited} شخصًا الآن. لا يمكن التراجع.`)}</span></label>
          <div className="flex justify-end gap-2">
            <button className={btnGhost} onClick={onClose}>{tr("Not now", "ليس الآن")}</button>
            <button className={btnCls} disabled={!sure || busy || c.ready === 0} onClick={send}><Send className="h-4 w-4" />{busy ? tr("Sending…", "جارٍ الإرسال…") : tr("Send invitations", "إرسال الدعوات")}</button>
          </div>
        </div>
      )}
    </Modal>
  );
}
