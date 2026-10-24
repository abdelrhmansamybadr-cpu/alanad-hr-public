import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { motion, AnimatePresence } from "framer-motion";
import {
  User,
  LogOut,
  Lock,
  ChevronRight,
  X,
  Check,
  Eye,
  EyeOff,
  Pencil,
  Phone,
  Briefcase,
  Shield,
  Fingerprint,
  Trash2,
} from "lucide-react";
import { browserSupportsWebAuthn } from "@simplewebauthn/browser";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";
import { toast } from "sonner";
import { useOwnerMe } from "@/lib/premium";

interface ProfilePanelProps {
  open: boolean;
  onClose: () => void;
  anchorRef: React.RefObject<HTMLElement | null>;
}

type PanelView = "menu" | "edit-profile" | "change-password" | "windows-hello";

function getInitials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0].toUpperCase())
    .join("");
}

export function ProfilePanel({ open, onClose, anchorRef }: ProfilePanelProps) {
  const ownerMe = useOwnerMe();
  const { user, logout, updateProfile, changePassword, registerPasskey, removePasskey, passkeyStatus, token } = useAuth();
  const { t, isRTL } = useLang();
  const panelRef = useRef<HTMLDivElement>(null);
  const [view, setView] = useState<PanelView>("menu");

  // Edit profile state
  const [editName, setEditName] = useState(user?.name ?? "");
  const [editTitle, setEditTitle] = useState(user?.title ?? "");
  const [editPhone, setEditPhone] = useState(user?.phone ?? "");
  const [editSaving, setEditSaving] = useState(false);

  // Passkey state
  const [passkeyLoading, setPasskeyLoading] = useState(false);
  const [passkeyError, setPasskeyError] = useState("");
  const isDemo = token?.startsWith("demo-") ?? false;

  // Change password state
  const [currentPwd, setCurrentPwd] = useState("");
  const [newPwd, setNewPwd] = useState("");
  const [confirmPwd, setConfirmPwd] = useState("");
  const [showPwd, setShowPwd] = useState(false);
  const [pwdSaving, setPwdSaving] = useState(false);
  const [pwdError, setPwdError] = useState("");

  // Reset form state when panel closes or changes view
  useEffect(() => {
    if (!open) {
      setTimeout(() => setView("menu"), 200);
    }
  }, [open]);

  useEffect(() => {
    setEditName(user?.name ?? "");
    setEditTitle(user?.title ?? "");
    setEditPhone(user?.phone ?? "");
  }, [user]);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    function handle(e: MouseEvent) {
      if (
        panelRef.current &&
        !panelRef.current.contains(e.target as Node) &&
        anchorRef.current &&
        !anchorRef.current.contains(e.target as Node)
      ) {
        onClose();
      }
    }
    document.addEventListener("mousedown", handle);
    return () => document.removeEventListener("mousedown", handle);
  }, [open, onClose, anchorRef]);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const handle = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (view !== "menu") setView("menu");
        else onClose();
      }
    };
    document.addEventListener("keydown", handle);
    return () => document.removeEventListener("keydown", handle);
  }, [open, onClose, view]);

  async function handleSaveProfile() {
    setEditSaving(true);
    try {
      await updateProfile({
        name: editName.trim(),
        title: editTitle.trim(),
        phone: editPhone.trim(),
      });
      toast.success(t.profileSaved);
      setView("menu");
    } catch (err: any) {
      toast.error(err.message || (isRTL ? "فشل الحفظ" : "Save failed"));
    } finally {
      setEditSaving(false);
    }
  }

  async function handleChangePassword() {
    setPwdError("");
    if (newPwd !== confirmPwd) {
      setPwdError(t.passwordMismatch);
      return;
    }
    if (newPwd.length < 6) {
      setPwdError(isRTL ? "كلمة المرور يجب أن تكون 6 أحرف على الأقل" : "Password must be at least 6 characters");
      return;
    }
    setPwdSaving(true);
    try {
      await changePassword(currentPwd, newPwd);
      toast.success(t.passwordChanged);
      setCurrentPwd("");
      setNewPwd("");
      setConfirmPwd("");
      setView("menu");
    } catch (err: any) {
      setPwdError(err.message || t.wrongCurrentPassword);
    } finally {
      setPwdSaving(false);
    }
  }

  async function handleLogout() {
    onClose();
    await logout();
  }

  if (!user) return null;

  const roleLabel = ownerMe.isOwner ? (isRTL ? "المالك" : "Owner") : user.role === "hr_admin"
    ? (isRTL ? "مدير الموارد البشرية" : "HR Administrator")
    : user.role;

  const panel = (
    <AnimatePresence>
      {open && (
        <motion.div
          ref={panelRef}
          initial={{ opacity: 0, y: -8, scale: 0.97 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -8, scale: 0.97 }}
          transition={{ duration: 0.18, ease: "easeOut" }}
          className={`fixed top-[72px] ${isRTL ? "left-4" : "right-4"} z-50 w-80 bg-background border border-border rounded-2xl shadow-2xl overflow-hidden`}
          dir={isRTL ? "rtl" : "ltr"}
        >
          {/* ── MENU VIEW ── */}
          {view === "menu" && (
            <>
              {/* User header */}
              <div className="px-5 py-4 bg-gradient-to-br from-primary/5 to-primary/10 border-b border-border">
                <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                  {/* Avatar */}
                  <div className="h-12 w-12 rounded-full bg-primary/15 border-2 border-primary/20 flex items-center justify-center text-primary font-bold text-lg flex-shrink-0 overflow-hidden shadow-sm">
                    {user.avatar ? (
                      <img src={user.avatar} alt={user.name} className="w-full h-full object-cover" />
                    ) : (
                      <span>{getInitials(user.name)}</span>
                    )}
                  </div>
                  <div className={`flex-1 min-w-0 ${isRTL ? "text-right" : ""}`}>
                    <p className="font-semibold text-foreground text-sm leading-tight truncate">{user.name}</p>
                    <p className="text-xs text-muted-foreground mt-0.5 truncate">{user.email}</p>
                    <div className="flex items-center gap-1 mt-1">
                      <Shield className="w-3 h-3 text-primary flex-shrink-0" />
                      <span className="text-[11px] text-primary font-medium">{roleLabel}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Menu items */}
              <div className="py-2">
                <button
                  onClick={() => setView("edit-profile")}
                  className={`w-full flex items-center gap-3 px-4 py-3 hover:bg-muted transition-colors text-sm text-foreground ${isRTL ? "flex-row-reverse text-right" : ""}`}
                >
                  <div className="w-8 h-8 rounded-lg bg-blue-50 flex items-center justify-center flex-shrink-0">
                    <User className="w-4 h-4 text-blue-600" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-medium">{t.editProfile}</p>
                    <p className="text-xs text-muted-foreground">{isRTL ? "تعديل اسمك ومعلوماتك" : "Edit your name and info"}</p>
                  </div>
                  <ChevronRight className={`w-4 h-4 text-muted-foreground flex-shrink-0 ${isRTL ? "rotate-180" : ""}`} />
                </button>

                <button
                  onClick={() => { setView("change-password"); setPwdError(""); }}
                  className={`w-full flex items-center gap-3 px-4 py-3 hover:bg-muted transition-colors text-sm text-foreground ${isRTL ? "flex-row-reverse text-right" : ""}`}
                >
                  <div className="w-8 h-8 rounded-lg bg-amber-50 flex items-center justify-center flex-shrink-0">
                    <Lock className="w-4 h-4 text-amber-600" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-medium">{t.changePassword}</p>
                    <p className="text-xs text-muted-foreground">{isRTL ? "تحديث كلمة المرور" : "Update your password"}</p>
                  </div>
                  <ChevronRight className={`w-4 h-4 text-muted-foreground flex-shrink-0 ${isRTL ? "rotate-180" : ""}`} />
                </button>

                {browserSupportsWebAuthn() && !isDemo && (
                  <button
                    onClick={() => { setView("windows-hello"); setPasskeyError(""); }}
                    className={`w-full flex items-center gap-3 px-4 py-3 hover:bg-muted transition-colors text-sm text-foreground ${isRTL ? "flex-row-reverse text-right" : ""}`}
                  >
                    <div className="w-8 h-8 rounded-lg bg-blue-50 flex items-center justify-center flex-shrink-0">
                      <Fingerprint className="w-4 h-4 text-blue-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium">{isRTL ? "Windows Hello" : "Windows Hello"}</p>
                      <p className="text-xs text-muted-foreground">
                        {passkeyStatus?.registered
                          ? (isRTL ? "✓ مُفعَّل" : "✓ Enabled")
                          : (isRTL ? "تسجيل الدخول بالبصمة أو PIN" : "Sign in with PIN or fingerprint")}
                      </p>
                    </div>
                    <ChevronRight className={`w-4 h-4 text-muted-foreground flex-shrink-0 ${isRTL ? "rotate-180" : ""}`} />
                  </button>
                )}
              </div>

              <div className="border-t border-border py-2">
                <button
                  onClick={handleLogout}
                  className={`w-full flex items-center gap-3 px-4 py-3 hover:bg-destructive/5 transition-colors text-sm text-destructive ${isRTL ? "flex-row-reverse text-right" : ""}`}
                >
                  <div className="w-8 h-8 rounded-lg bg-red-50 flex items-center justify-center flex-shrink-0">
                    <LogOut className="w-4 h-4 text-red-500" />
                  </div>
                  <span className="font-medium">{t.signOut}</span>
                </button>
              </div>
            </>
          )}

          {/* ── EDIT PROFILE VIEW ── */}
          {view === "edit-profile" && (
            <>
              <div className={`flex items-center gap-2 px-4 py-3 border-b border-border ${isRTL ? "flex-row-reverse" : ""}`}>
                <button
                  onClick={() => setView("menu")}
                  className="p-1.5 rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
                >
                  <X className="w-4 h-4" />
                </button>
                <h3 className="font-semibold text-sm text-foreground flex-1">{t.editProfile}</h3>
              </div>

              <div className="p-4 space-y-4">
                {/* Avatar preview */}
                <div className={`flex ${isRTL ? "justify-end" : "justify-start"}`}>
                  <div className="h-16 w-16 rounded-full bg-primary/15 border-2 border-primary/20 flex items-center justify-center text-primary font-bold text-2xl overflow-hidden shadow-sm">
                    {user.avatar ? (
                      <img src={user.avatar} alt={user.name} className="w-full h-full object-cover" />
                    ) : (
                      <span>{getInitials(editName || user.name)}</span>
                    )}
                  </div>
                </div>

                {/* Name */}
                <div>
                  <label className={`block text-xs font-medium text-muted-foreground mb-1 ${isRTL ? "text-right" : ""}`}>
                    <Pencil className="w-3 h-3 inline-block mr-1" />{isRTL ? "الاسم" : "Full Name"}
                  </label>
                  <input
                    type="text"
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    className={`w-full px-3 py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all ${isRTL ? "text-right" : ""}`}
                  />
                </div>

                {/* Title / Position */}
                <div>
                  <label className={`block text-xs font-medium text-muted-foreground mb-1 ${isRTL ? "text-right" : ""}`}>
                    <Briefcase className="w-3 h-3 inline-block mr-1" />{isRTL ? "المسمى الوظيفي" : "Job Title"}
                  </label>
                  <input
                    type="text"
                    value={editTitle}
                    onChange={(e) => setEditTitle(e.target.value)}
                    className={`w-full px-3 py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all ${isRTL ? "text-right" : ""}`}
                    placeholder={isRTL ? "مدير الموارد البشرية" : "HR Director"}
                  />
                </div>

                {/* Phone */}
                <div>
                  <label className={`block text-xs font-medium text-muted-foreground mb-1 ${isRTL ? "text-right" : ""}`}>
                    <Phone className="w-3 h-3 inline-block mr-1" />{isRTL ? "الهاتف" : "Phone"}
                  </label>
                  <input
                    type="tel"
                    value={editPhone}
                    onChange={(e) => setEditPhone(e.target.value)}
                    className={`w-full px-3 py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all ${isRTL ? "text-right" : ""}`}
                    placeholder="+1 555 0100"
                  />
                </div>

                {/* Email (read-only) */}
                <div>
                  <label className={`block text-xs font-medium text-muted-foreground mb-1 ${isRTL ? "text-right" : ""}`}>
                    {isRTL ? "البريد الإلكتروني (لا يمكن تغييره)" : "Email (cannot be changed)"}
                  </label>
                  <input
                    type="email"
                    value={user.email}
                    disabled
                    className={`w-full px-3 py-2 border border-border rounded-lg bg-muted text-muted-foreground text-sm cursor-not-allowed ${isRTL ? "text-right" : ""}`}
                  />
                </div>

                <div className={`flex gap-2 pt-1 ${isRTL ? "flex-row-reverse" : ""}`}>
                  <button
                    onClick={handleSaveProfile}
                    disabled={editSaving || !editName.trim()}
                    className="flex-1 flex items-center justify-center gap-1.5 bg-primary text-primary-foreground py-2 rounded-lg text-sm font-semibold hover:bg-primary/90 transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
                  >
                    {editSaving ? (
                      <span>{t.savingChanges}</span>
                    ) : (
                      <>
                        <Check className="w-3.5 h-3.5" />
                        <span>{t.saveChanges}</span>
                      </>
                    )}
                  </button>
                  <button
                    onClick={() => setView("menu")}
                    className="px-4 py-2 rounded-lg border border-border text-sm text-muted-foreground hover:bg-muted transition-colors"
                  >
                    {t.cancel}
                  </button>
                </div>
              </div>
            </>
          )}

          {/* ── WINDOWS HELLO VIEW ── */}
          {view === "windows-hello" && (
            <>
              <div className={`flex items-center gap-2 px-4 py-3 border-b border-border ${isRTL ? "flex-row-reverse" : ""}`}>
                <button onClick={() => setView("menu")} className="p-1.5 rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground transition-colors">
                  <X className="w-4 h-4" />
                </button>
                <h3 className="font-semibold text-sm text-foreground flex-1">Windows Hello</h3>
              </div>

              <div className="p-4 space-y-4">
                {/* Hero */}
                <div className="flex flex-col items-center py-4 gap-3">
                  <div className="w-16 h-16 rounded-2xl bg-blue-50 border border-blue-100 flex items-center justify-center">
                    <Fingerprint className="w-9 h-9 text-blue-500" />
                  </div>
                  <div className="text-center">
                    <p className="font-semibold text-foreground">
                      {isRTL ? "تسجيل الدخول بـ Windows Hello" : "Sign in with Windows Hello"}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1">
                      {isRTL
                        ? "استخدم رقم التعريف الشخصي أو بصمة الإصبع أو التعرف على الوجه بدلاً من كلمة المرور"
                        : "Use your PIN, fingerprint, or face recognition instead of a password"}
                    </p>
                  </div>
                </div>

                {passkeyError && (
                  <div className="p-3 rounded-xl bg-destructive/10 border border-destructive/20 text-destructive text-xs">
                    {passkeyError}
                  </div>
                )}

                {passkeyStatus?.registered ? (
                  <div className="space-y-3">
                    <div className="flex items-center gap-2 p-3 bg-emerald-50 border border-emerald-100 rounded-xl">
                      <Check className="w-4 h-4 text-emerald-600 flex-shrink-0" />
                      <div>
                        <p className="text-sm font-medium text-emerald-800">{isRTL ? "مُفعَّل" : "Active"}</p>
                        {passkeyStatus.registeredAt && (
                          <p className="text-xs text-emerald-600">
                            {isRTL ? "تم الإعداد في" : "Set up on"} {passkeyStatus.registeredAt}
                          </p>
                        )}
                      </div>
                    </div>

                    <button
                      onClick={async () => {
                        setPasskeyLoading(true);
                        setPasskeyError("");
                        try {
                          await registerPasskey();
                          toast.success(isRTL ? "تم تحديث بيانات Windows Hello" : "Windows Hello updated");
                        } catch (err: any) {
                          setPasskeyError(err.message || (isRTL ? "فشل التحديث" : "Update failed"));
                        } finally {
                          setPasskeyLoading(false);
                        }
                      }}
                      disabled={passkeyLoading}
                      className="w-full py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 transition-colors disabled:opacity-60"
                    >
                      {passkeyLoading ? (isRTL ? "جارٍ التحديث..." : "Updating...") : (isRTL ? "تحديث بيانات Windows Hello" : "Update Windows Hello")}
                    </button>

                    <button
                      onClick={async () => {
                        setPasskeyLoading(true);
                        setPasskeyError("");
                        try {
                          await removePasskey();
                          toast.success(isRTL ? "تم إزالة Windows Hello" : "Windows Hello removed");
                        } catch (err: any) {
                          setPasskeyError(err.message || (isRTL ? "فشل الإزالة" : "Remove failed"));
                        } finally {
                          setPasskeyLoading(false);
                        }
                      }}
                      disabled={passkeyLoading}
                      className="w-full flex items-center justify-center gap-2 py-2 text-sm font-medium text-red-500 border border-red-200 hover:bg-red-50 rounded-lg transition-colors disabled:opacity-60"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                      {isRTL ? "إزالة Windows Hello" : "Remove Windows Hello"}
                    </button>
                  </div>
                ) : (
                  <button
                    onClick={async () => {
                      setPasskeyLoading(true);
                      setPasskeyError("");
                      try {
                        await registerPasskey();
                        toast.success(isRTL ? "تم إعداد Windows Hello بنجاح" : "Windows Hello set up successfully");
                      } catch (err: any) {
                        setPasskeyError(err.message || (isRTL ? "فشل الإعداد" : "Setup failed"));
                      } finally {
                        setPasskeyLoading(false);
                      }
                    }}
                    disabled={passkeyLoading}
                    className="w-full flex items-center justify-center gap-2 py-2.5 text-sm font-semibold bg-blue-600 text-white rounded-xl hover:bg-blue-700 transition-colors disabled:opacity-60 shadow-sm"
                  >
                    <Fingerprint className="w-4 h-4" />
                    {passkeyLoading
                      ? (isRTL ? "جارٍ الإعداد..." : "Setting up...")
                      : (isRTL ? "إعداد Windows Hello" : "Set up Windows Hello")}
                  </button>
                )}

                <p className="text-[11px] text-muted-foreground text-center leading-relaxed">
                  {isRTL
                    ? "يتطلب Windows Hello مع متصفح Chrome أو Edge على Windows 10/11"
                    : "Requires Windows Hello with Chrome or Edge on Windows 10/11"}
                </p>
              </div>
            </>
          )}

          {/* ── CHANGE PASSWORD VIEW ── */}
          {view === "change-password" && (
            <>
              <div className={`flex items-center gap-2 px-4 py-3 border-b border-border ${isRTL ? "flex-row-reverse" : ""}`}>
                <button
                  onClick={() => setView("menu")}
                  className="p-1.5 rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
                >
                  <X className="w-4 h-4" />
                </button>
                <h3 className="font-semibold text-sm text-foreground flex-1">{t.changePassword}</h3>
              </div>

              <div className="p-4 space-y-4">
                {pwdError && (
                  <div className={`p-3 rounded-xl bg-destructive/10 border border-destructive/20 text-destructive text-xs ${isRTL ? "text-right" : ""}`}>
                    {pwdError}
                  </div>
                )}

                {[
                  { label: t.currentPassword, value: currentPwd, setter: setCurrentPwd, ac: "current-password" },
                  { label: t.newPassword, value: newPwd, setter: setNewPwd, ac: "new-password" },
                  { label: t.confirmNewPassword, value: confirmPwd, setter: setConfirmPwd, ac: "new-password" },
                ].map(({ label, value, setter, ac }) => (
                  <div key={label}>
                    <label className={`block text-xs font-medium text-muted-foreground mb-1 ${isRTL ? "text-right" : ""}`}>
                      {label}
                    </label>
                    <div className="relative">
                      <input
                        type={showPwd ? "text" : "password"}
                        value={value}
                        onChange={(e) => setter(e.target.value)}
                        autoComplete={ac}
                        className={`w-full ${isRTL ? "pr-3 pl-9 text-right" : "pl-3 pr-9"} py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all`}
                        placeholder="••••••••"
                      />
                      <button
                        type="button"
                        onClick={() => setShowPwd((v) => !v)}
                        className={`absolute inset-y-0 ${isRTL ? "left-0 pl-2.5" : "right-0 pr-2.5"} flex items-center text-muted-foreground hover:text-foreground transition-colors`}
                      >
                        {showPwd ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                      </button>
                    </div>
                  </div>
                ))}

                <div className={`flex gap-2 pt-1 ${isRTL ? "flex-row-reverse" : ""}`}>
                  <button
                    onClick={handleChangePassword}
                    disabled={pwdSaving || !currentPwd || !newPwd || !confirmPwd}
                    className="flex-1 flex items-center justify-center gap-1.5 bg-primary text-primary-foreground py-2 rounded-lg text-sm font-semibold hover:bg-primary/90 transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
                  >
                    {pwdSaving ? t.savingChanges : t.saveChanges}
                  </button>
                  <button
                    onClick={() => { setView("menu"); setPwdError(""); }}
                    className="px-4 py-2 rounded-lg border border-border text-sm text-muted-foreground hover:bg-muted transition-colors"
                  >
                    {t.cancel}
                  </button>
                </div>
              </div>
            </>
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );

  return createPortal(panel, document.body);
}
