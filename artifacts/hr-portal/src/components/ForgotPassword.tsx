import { FormEvent, useState } from "react";
import { AlertCircle, ArrowLeft, CheckCircle2, KeyRound, Mail } from "lucide-react";
import { useTr } from "@/components/kit";

async function post(path: string, body: unknown) {
  const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data?.error || "Something went wrong");
  return data;
}

/** Reset a forgotten password with a 6-digit code sent by e-mail (works for HR accounts and employees). */
export function ForgotPassword({ initialEmail, onBack }: { initialEmail: string; onBack: () => void }) {
  const tr = useTr();
  const [step, setStep] = useState<"email" | "code" | "done">("email");
  const [email, setEmail] = useState(initialEmail);
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function sendCode(e: FormEvent | null, via: "email" | "sms" = "email") {
    e?.preventDefault();
    setError(""); setBusy(true);
    try { await post("/api/auth/employee/forgot-password", { email: email.trim(), via }); setStep("code"); }
    catch (err: any) { setError(err.message); }
    finally { setBusy(false); }
  }

  async function reset(e: FormEvent) {
    e.preventDefault();
    setError("");
    if (password.length < 8) { setError(tr("The password must be at least 8 characters.", "يجب ألا تقل كلمة المرور عن 8 أحرف.")); return; }
    setBusy(true);
    try { await post("/api/auth/employee/reset-password", { email: email.trim(), code: code.trim(), newPassword: password }); setStep("done"); }
    catch (err: any) { setError(err.message); }
    finally { setBusy(false); }
  }

  const input = "block w-full px-3 py-2.5 border border-border rounded-xl bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary";
  const btn = "w-full bg-primary text-primary-foreground py-2.5 px-4 rounded-xl font-semibold text-sm hover:bg-primary/90 disabled:opacity-60";

  return (
    <div className="mt-8 space-y-5">
      <button type="button" onClick={onBack} className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"><ArrowLeft className="h-4 w-4 rtl:rotate-180" />{tr("Back to sign in", "العودة لتسجيل الدخول")}</button>
      <div>
        <h2 className="text-2xl font-bold">{tr("Reset your password", "إعادة تعيين كلمة المرور")}</h2>
        <p className="text-muted-foreground text-sm mt-1">
          {step === "email" && tr("Enter your e-mail or mobile number and we will send you a 6-digit code.", "أدخل بريدك الإلكتروني أو رقم جوالك وسنرسل لك رمزاً من 6 أرقام.")}
          {step === "code" && tr("If this address has an account, a code is on its way. It lasts 30 minutes.", "إذا كان لهذا البريد حساب فالرمز في الطريق إليه. صالح لمدة 30 دقيقة.")}
          {step === "done" && tr("Your password has been changed.", "تم تغيير كلمة المرور.")}
        </p>
      </div>

      {error && <div className="flex items-center gap-2 p-3 rounded-xl bg-destructive/10 border border-destructive/20 text-destructive text-sm"><AlertCircle className="w-4 h-4 shrink-0" /><span>{error}</span></div>}

      {step === "email" && (
        <form onSubmit={sendCode} className="space-y-4">
          <div className="relative"><Mail className="h-4 w-4 absolute top-1/2 -translate-y-1/2 start-3 text-muted-foreground" /><input type="text" inputMode="email" dir="ltr" required value={email} onChange={(e) => setEmail(e.target.value)} className={input + " ps-10"} placeholder="you@example.com  /  +966 5x xxx xxxx" autoComplete="username" /></div>
          <button className={btn} disabled={busy}>{busy ? "…" : tr("Send me a code", "أرسل لي رمزاً")}</button>
          <button type="button" disabled={busy || !email.trim()} className="w-full text-sm text-primary hover:underline disabled:opacity-50" onClick={() => sendCode(null, "sms")}>{tr("Send the code by SMS instead", "أرسل الرمز برسالة SMS بدلاً من ذلك")}</button>
          <button type="button" className="w-full text-sm text-primary hover:underline" onClick={() => email.trim() && setStep("code")}>{tr("I already have a code", "لدي رمز بالفعل")}</button>
        </form>
      )}

      {step === "code" && (
        <form onSubmit={reset} className="space-y-4">
          <div className="relative"><KeyRound className="h-4 w-4 absolute top-1/2 -translate-y-1/2 start-3 text-muted-foreground" /><input required inputMode="numeric" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} className={input + " ps-10 tracking-[0.4em] text-center font-bold"} placeholder="000000" autoFocus /></div>
          <input type="password" required value={password} onChange={(e) => setPassword(e.target.value)} className={input} placeholder={tr("New password (8+ characters)", "كلمة المرور الجديدة (8 أحرف أو أكثر)")} autoComplete="new-password" />
          <button className={btn} disabled={busy || code.length !== 6}>{busy ? "…" : tr("Change password", "تغيير كلمة المرور")}</button>
          <button type="button" className="w-full text-sm text-primary hover:underline" onClick={() => setStep("email")}>{tr("Send the code again", "أرسل الرمز مرة أخرى")}</button>
        </form>
      )}

      {step === "done" && (
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-emerald-600 font-semibold"><CheckCircle2 className="h-5 w-5" />{tr("You can sign in with the new password.", "يمكنك الآن تسجيل الدخول بكلمة المرور الجديدة.")}</div>
          <button className={btn} onClick={onBack}>{tr("Sign in", "تسجيل الدخول")}</button>
        </div>
      )}
    </div>
  );
}
