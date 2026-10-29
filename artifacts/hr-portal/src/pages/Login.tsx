import { useState, FormEvent, useEffect } from "react";
import { motion } from "framer-motion";
import {
  Eye,
  EyeOff,
  Lock,
  Mail,
  AlertCircle,
  Fingerprint,
} from "lucide-react";
import {
  browserSupportsWebAuthn,
  platformAuthenticatorIsAvailable,
} from "@simplewebauthn/browser";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";
import { ForgotPassword } from "@/components/ForgotPassword";

export default function Login() {
  const { login, loginWithPasskey } = useAuth();
  const { t, lang, setLang, isRTL } = useLang();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [passkeyLoading, setPasskeyLoading] = useState(false);
  const [forgot, setForgot] = useState(false);
  const [webAuthnSupported, setWebAuthnSupported] = useState<boolean | null>(
    null,
  );

  useEffect(() => {
    // Show the Windows Hello / fingerprint button only when this device can do it.
    let cancelled = false;
    (async () => {
      let ok = false;
      try {
        ok = browserSupportsWebAuthn() && (await platformAuthenticatorIsAvailable());
      } catch {
        ok = false;
      }
      if (cancelled) return;
      setWebAuthnSupported(ok);

      // Fast path: this device already has a passkey -> offer Windows Hello straight away,
      // unless the person just signed out on purpose.
      let known = false;
      let noAuto = false;
      try {
        known = localStorage.getItem("hr-passkey") === "1";
        noAuto = sessionStorage.getItem("hr-no-auto") === "1";
      } catch {
        /* storage blocked */
      }
      if (ok && known && !noAuto) {
        try {
          await loginWithPasskey();
        } catch {
          /* cancelled or failed: the normal form stays available */
        }
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setIsLoading(true);
    try {
      await login(email.trim(), password);
    } catch (err: any) {
      setError(err.message || t.loginError);
    } finally {
      setIsLoading(false);
    }
  }

  async function handleWindowsHello() {
    setError("");
    setPasskeyLoading(true);
    try {
      // E-mail is optional: empty = the device shows the passkeys it holds for this site.
      await loginWithPasskey(email.trim() || undefined);
    } catch (err: any) {
      // The person closing the Windows Hello window is not an error worth showing.
      if (err?.name !== "NotAllowedError") {
        setError(err.message || "Passkey authentication failed");
      }
    } finally {
      setPasskeyLoading(false);
    }
  }

  return (
    <div
      className="min-h-screen flex"
      dir={isRTL ? "rtl" : "ltr"}
      style={{ fontFamily: isRTL ? "'Cairo', sans-serif" : "inherit" }}
    >
      {/* Left panel — Branding */}
      <div className="hidden lg:flex lg:w-1/2 bg-gradient-to-br from-primary via-primary/90 to-primary/70 flex-col justify-between p-12 relative overflow-hidden">
        {/* Background decoration */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <div className="absolute -top-32 -right-32 w-96 h-96 bg-white/5 rounded-full" />
          <div className="absolute top-1/2 -left-24 w-72 h-72 bg-white/5 rounded-full" />
          <div className="absolute -bottom-24 right-1/4 w-64 h-64 bg-white/5 rounded-full" />
        </div>

        <div className="relative z-10">
          <div className="flex items-center gap-3">
            <img src="/images/mark-white.png" alt="" className="h-11 w-11" />
            <span className="text-white font-bold text-2xl tracking-tight">
              Al Anad HR
            </span>
          </div>
        </div>

        <div className="relative z-10 space-y-6">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
          >
            <h2 className="text-white text-4xl font-bold leading-tight">
              {isRTL
                ? "إدارة فريقك\nبكفاءة عالية"
                : "Manage your team\nwith confidence"}
            </h2>
            <p className="text-white/70 mt-4 text-lg leading-relaxed">
              {isRTL
                ? "منصة شاملة لإدارة الموارد البشرية، الرواتب، الإجازات والمزيد."
                : "A complete platform for HR management, payroll, leave tracking, and more."}
            </p>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4 }}
            className="grid grid-cols-2 gap-4"
          >
            {[
              { num: "10+", label: isRTL ? "موظف" : "Employees" },
              { num: "9", label: isRTL ? "وحدات نظام" : "Modules" },
              { num: "100%", label: isRTL ? "ثنائي اللغة" : "Bilingual" },
              { num: "24/7", label: isRTL ? "متاح دائماً" : "Available" },
            ].map((stat) => (
              <div
                key={stat.label}
                className="bg-white/10 rounded-2xl p-4 border border-white/10"
              >
                <p className="text-white font-bold text-2xl">{stat.num}</p>
                <p className="text-white/60 text-sm mt-0.5">{stat.label}</p>
              </div>
            ))}
          </motion.div>
        </div>

        <div className="relative z-10 text-white/40 text-sm">
          © 2025 Al Anad HR.{" "}
          {isRTL ? "جميع الحقوق محفوظة." : "All rights reserved."}
        </div>
      </div>

      {/* Right panel — Form */}
      <div className="flex-1 flex flex-col items-center justify-center px-6 py-12 bg-background">
        {/* Mobile logo */}
        <div className="lg:hidden flex items-center gap-2 mb-8">
          <img src="/images/logo-icon.png" alt="" className="h-9 w-9 rounded-xl" />
          <span className="font-bold text-xl text-foreground">Al Anad HR</span>
        </div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.3 }}
          className="w-full max-w-md"
        >
          {/* Language toggle */}
          <div
            className={`flex ${isRTL ? "justify-start" : "justify-end"} mb-6`}
          >
            <button
              onClick={() => setLang(lang === "ar" ? "en" : "ar")}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border bg-background text-sm font-semibold text-foreground hover:bg-muted transition-colors"
            >
              <span>{lang === "ar" ? "🇺🇸" : "🇸🇦"}</span>
              <span>{lang === "ar" ? "EN" : "عربي"}</span>
            </button>
          </div>

          <div className={isRTL ? "text-right" : "text-left"}>
            <h1 className="text-3xl font-bold text-foreground">
              {t.loginTitle}
            </h1>
            <p className="text-muted-foreground mt-2">{t.loginSubtitle}</p>
          </div>

          {forgot ? (
            <ForgotPassword initialEmail={email} onBack={() => setForgot(false)} />
          ) : (
          <>
          <form onSubmit={handleSubmit} className="mt-8 space-y-5">
            {/* Error */}
            {error && (
              <motion.div
                initial={{ opacity: 0, scale: 0.97 }}
                animate={{ opacity: 1, scale: 1 }}
                className={`flex items-center gap-2.5 p-3 rounded-xl bg-destructive/10 border border-destructive/20 text-destructive text-sm ${isRTL ? "flex-row-reverse" : ""}`}
              >
                <AlertCircle className="w-4 h-4 flex-shrink-0" />
                <span>{error}</span>
              </motion.div>
            )}

            {/* Email */}
            <div className="space-y-1.5">
              <label
                className={`block text-sm font-medium text-foreground ${isRTL ? "text-right" : ""}`}
              >
                {isRTL ? "البريد الإلكتروني أو رقم الجوال" : "Email or mobile number"}
              </label>
              <div className="relative">
                <div
                  className={`absolute inset-y-0 ${isRTL ? "right-0 pr-3" : "left-0 pl-3"} flex items-center pointer-events-none`}
                >
                  <Mail className="h-4 w-4 text-muted-foreground" />
                </div>
                <input
                  type="text"
                  inputMode="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  autoComplete="username"
                  dir="ltr"
                  className={`block w-full ${isRTL ? "pr-10 pl-3 text-right" : "pl-10 pr-3"} py-2.5 border border-border rounded-xl bg-background text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary text-sm transition-all`}
                  placeholder="you@example.com  /  +966 5x xxx xxxx"
                />
              </div>
            </div>

            {/* Password */}
            <div className="space-y-1.5">
              <label
                className={`block text-sm font-medium text-foreground ${isRTL ? "text-right" : ""}`}
              >
                {t.password}
              </label>
              <div className="relative">
                <div
                  className={`absolute inset-y-0 ${isRTL ? "right-0 pr-3" : "left-0 pl-3"} flex items-center pointer-events-none`}
                >
                  <Lock className="h-4 w-4 text-muted-foreground" />
                </div>
                <input
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                  className={`block w-full ${isRTL ? "pr-10 pl-10 text-right" : "pl-10 pr-10"} py-2.5 border border-border rounded-xl bg-background text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary text-sm transition-all`}
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  className={`absolute inset-y-0 ${isRTL ? "left-0 pl-3" : "right-0 pr-3"} flex items-center text-muted-foreground hover:text-foreground transition-colors`}
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
            </div>

            <div className={isRTL ? "text-left" : "text-right"}>
              <button type="button" onClick={() => setForgot(true)} className="text-sm text-primary hover:underline">
                {isRTL ? "نسيت كلمة المرور؟" : "Forgot password?"}
              </button>
            </div>

            {/* Submit */}
            <button
              type="submit"
              disabled={isLoading || passkeyLoading}
              className="w-full bg-primary text-primary-foreground py-2.5 px-4 rounded-xl font-semibold text-sm hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-primary/40 transition-all disabled:opacity-60 disabled:cursor-not-allowed shadow-sm shadow-primary/20 mt-2"
            >
              {isLoading ? t.signingIn : t.signIn}
            </button>
          </form>

          {/* Windows Hello / Passkey (only when this device supports it) */}
          {webAuthnSupported && (
            <div className="relative my-6">
              <div className="absolute inset-0 flex items-center">
                <div className="w-full border-t border-border" />
              </div>
              <div className="relative flex justify-center text-xs">
                <span className="bg-background px-2 text-muted-foreground">
                  {isRTL ? "أو" : "or"}
                </span>
              </div>
            </div>
          )}
          {webAuthnSupported && (
            <button
              type="button"
              onClick={handleWindowsHello}
              disabled={isLoading || passkeyLoading}
              className={`w-full flex items-center justify-center gap-2.5 py-2.5 px-4 rounded-xl font-semibold text-sm border border-border bg-background hover:bg-muted focus:outline-none focus:ring-2 focus:ring-primary/30 transition-all disabled:opacity-60 disabled:cursor-not-allowed ${isRTL ? "flex-row-reverse" : ""}`}
            >
              {passkeyLoading ? (
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
              ) : (
                <Fingerprint className="h-4 w-4" />
              )}
              <span>
                {passkeyLoading
                  ? t.signingInWithPasskey
                  : t.signInWithWindowsHello}
              </span>
            </button>
          )}

          </>
          )}
        </motion.div>
      </div>
    </div>
  );
}
