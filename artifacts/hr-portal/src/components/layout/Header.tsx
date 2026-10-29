import { useState, useRef, useEffect } from "react";
import { useLocation } from "wouter";
import { api } from "@/lib/http";
import { Bell, Search } from "lucide-react";
import { useLang } from "@/contexts/LanguageContext";
import { useNotifications } from "@/contexts/NotificationContext";
import { useAuth } from "@/contexts/AuthContext";
import { NotificationPanel } from "@/components/NotificationPanel";
import { ProfilePanel } from "@/components/ProfilePanel";
import { useOwnerMe } from "@/lib/premium";

function getInitials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0].toUpperCase())
    .join("");
}

/** The search box in the top bar: finds employees of the open company (name in any Arabic spelling, ID, mobile, job, nationality). */
function GlobalSearch() {
  const { t, isRTL } = useLang();
  const { user, switchCompany } = useAuth();
  const { isOwner } = useOwnerMe();
  const [, navigate] = useLocation();
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<any[]>([]);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  const isHr = user?.role === "hr_admin" || user?.role === "hr_manager";

  useEffect(() => {
    const term = q.trim();
    if (!isHr || term.length < 2) { setRows([]); return; }
    setBusy(true);
    const h = setTimeout(async () => {
      try {
        // The owner searches EVERY company of the group; everybody else only the company they are working in.
        const r: any = await api((isOwner ? "/group/search?q=" : "/employees?q=") + encodeURIComponent(term));
        const list = Array.isArray(r) ? r : Array.isArray(r?.data) ? r.data : [];
        setRows(list.slice(0, isOwner ? 15 : 8));
      } catch { setRows([]); }
      setBusy(false);
    }, 300);
    return () => clearTimeout(h);
  }, [q, isHr, isOwner]);

  useEffect(() => {
    const off = (e: MouseEvent) => { if (box.current && !box.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener("mousedown", off);
    return () => document.removeEventListener("mousedown", off);
  }, []);

  const go = (term: string) => { setOpen(false); navigate("/employees?q=" + encodeURIComponent(term)); };
  const none = isRTL ? "لا توجد نتائج" : "No results";

  return (
    <div ref={box} className="relative w-full max-w-md group">
      <div className={`absolute inset-y-0 ${isRTL ? "right-0 pr-3" : "left-0 pl-3"} flex items-center pointer-events-none`}>
        <Search className="h-4 w-4 text-muted-foreground group-focus-within:text-primary transition-colors" />
      </div>
      <input
        type="text"
        value={q}
        onChange={(e) => { setQ(e.target.value); setOpen(true); }}
        onFocus={() => setOpen(true)}
        onKeyDown={(e) => { if (e.key === "Enter" && q.trim()) go(q.trim()); if (e.key === "Escape") setOpen(false); }}
        className={`block w-full ${isRTL ? "pr-10 pl-3 text-right" : "pl-10 pr-3"} py-2 border-none bg-muted/50 rounded-xl leading-5 text-foreground placeholder-muted-foreground focus:outline-none focus:bg-background focus:ring-2 focus:ring-primary/20 sm:text-sm transition-all duration-200`}
        placeholder={t.searchPlaceholder}
      />
      {open && isHr && q.trim().length >= 2 && (
        <div className="absolute top-full mt-2 w-full bg-background border border-border rounded-xl shadow-lg overflow-hidden z-50">
          {rows.length === 0 ? (
            <p className="px-4 py-3 text-sm text-muted-foreground">{busy ? "…" : none}</p>
          ) : (
            rows.map((r) => (
              <button
                key={`${r.companyId ?? 0}-${r.id}`}
                onClick={() => {
                  const term = `${r.firstName} ${r.lastName}`.trim();
                  // a result from another company: open that company first, then the employee list filtered to the person
                  if (isOwner && r.companyId && r.isCurrent === false) { setOpen(false); void switchCompany(r.companyId, "/employees?q=" + encodeURIComponent(term)).catch(() => {}); }
                  else go(term);
                }}
                className="w-full text-start px-4 py-2.5 hover:bg-muted flex flex-col"
              >
                <span className="text-sm font-semibold text-foreground">{r.firstName} {r.lastName}</span>
                <span className="text-xs text-muted-foreground">{[r.position, r.departmentName, r.idNumber].filter(Boolean).join(" · ")}</span>
                {isOwner && r.companyName && <span className="text-[11px] text-primary font-medium">{r.companyName}</span>}
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}

export function Header() {
  const { t, lang, setLang, isRTL } = useLang();
  const { unreadCount } = useNotifications();
  const { user } = useAuth();
  const ownerMe = useOwnerMe();

  const [notifOpen, setNotifOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);

  const bellRef = useRef<HTMLButtonElement>(null);
  const avatarRef = useRef<HTMLDivElement>(null);

  const displayName = user?.name ?? "Jane Doe";
  const displayTitle = ownerMe.isOwner ? (t.hrDirector === "مدير الموارد البشرية" ? "المالك" : "Owner") : (user?.title ?? t.hrDirector);

  return (
    <header className="h-16 flex items-center justify-between px-8 bg-background border-b border-border/60 sticky top-0 z-10">
      <div className="flex-1 flex items-center">
        <GlobalSearch />
      </div>

      <div className={`${isRTL ? "mr-4" : "ml-4"} flex items-center gap-3`}>
        {/* Language Toggle */}
        <button
          onClick={() => setLang(lang === "ar" ? "en" : "ar")}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border bg-background text-sm font-semibold text-foreground hover:bg-muted transition-colors shadow-sm"
          data-testid="button-lang-toggle"
          title={lang === "ar" ? "Switch to English" : "التبديل إلى العربية"}
        >
          <span className="text-base">{lang === "ar" ? "🇸🇦" : "🇺🇸"}</span>
          <span>{lang === "ar" ? "EN" : "عربي"}</span>
        </button>

        {/* Bell button */}
        <button
          ref={bellRef}
          onClick={() => { setNotifOpen((v) => !v); setProfileOpen(false); }}
          className={`p-2 rounded-full transition-colors relative ${notifOpen ? "bg-primary/10 text-primary" : "text-muted-foreground hover:bg-muted hover:text-foreground"}`}
          aria-label={t.notifications}
        >
          {unreadCount > 0 && (
            <span className={`absolute top-1 ${isRTL ? "left-1" : "right-1"} min-w-[16px] h-4 bg-destructive text-white text-[9px] font-bold rounded-full flex items-center justify-center px-0.5 border-2 border-background`}>
              {unreadCount > 9 ? "9+" : unreadCount}
            </span>
          )}
          <Bell className="h-5 w-5" />
        </button>

        <div className="h-8 w-px bg-border"></div>

        {/* Profile button */}
        <div
          ref={avatarRef}
          onClick={() => { setProfileOpen((v) => !v); setNotifOpen(false); }}
          className={`flex items-center gap-3 cursor-pointer group ${profileOpen ? "opacity-90" : ""}`}
        >
          <div className={`${isRTL ? "text-left" : "text-right"} hidden md:block`}>
            <p className="text-sm font-semibold leading-none text-foreground group-hover:text-primary transition-colors">
              {displayName}
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">{displayTitle}</p>
          </div>
          <div
            className={`h-9 w-9 rounded-full bg-primary/10 border-2 flex items-center justify-center font-bold overflow-hidden shadow-sm group-hover:shadow-md transition-all group-hover:ring-2 ${profileOpen ? "border-primary ring-2 ring-primary/20" : "border-primary/20 ring-primary/20"}`}
          >
            {user?.avatar ? (
              <img src={user.avatar} alt={displayName} className="w-full h-full object-cover" />
            ) : (
              <span className="text-primary text-sm">{getInitials(displayName)}</span>
            )}
          </div>
        </div>
      </div>

      <NotificationPanel
        open={notifOpen}
        onClose={() => setNotifOpen(false)}
        anchorRef={bellRef}
      />
      <ProfilePanel
        open={profileOpen}
        onClose={() => setProfileOpen(false)}
        anchorRef={avatarRef}
      />
    </header>
  );
}
