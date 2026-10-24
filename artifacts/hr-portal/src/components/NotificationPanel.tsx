import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import { motion, AnimatePresence } from "framer-motion";
import { Bell, X, CheckCheck, Trash2, Info, CheckCircle2, AlertTriangle, XCircle, BellOff } from "lucide-react";
import { useNotifications, type AppNotification, type NotifType } from "@/contexts/NotificationContext";
import { useLang } from "@/contexts/LanguageContext";
import { useLocation } from "wouter";
import { routeForNotification } from "@/lib/notificationRoute";

interface NotificationPanelProps {
  open: boolean;
  onClose: () => void;
  anchorRef: React.RefObject<HTMLButtonElement | null>;
}

function timeAgo(date: Date, isAr: boolean, t: { notifJustNow: string; notifMinAgo: string; notifHrAgo: string; notifDayAgo: string }) {
  const diff = Math.floor((Date.now() - date.getTime()) / 1000);
  if (diff < 60) return t.notifJustNow;
  if (diff < 3600) return `${Math.floor(diff / 60)}${isAr ? " " : ""}${t.notifMinAgo}`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}${isAr ? " " : ""}${t.notifHrAgo}`;
  return `${Math.floor(diff / 86400)}${isAr ? " " : ""}${t.notifDayAgo}`;
}

const TYPE_STYLES: Record<NotifType, { icon: React.ElementType; bg: string; text: string; ring: string }> = {
  info:    { icon: Info,           bg: "bg-blue-50",   text: "text-blue-600",   ring: "ring-blue-100" },
  success: { icon: CheckCircle2,   bg: "bg-emerald-50",text: "text-emerald-600",ring: "ring-emerald-100" },
  warning: { icon: AlertTriangle,  bg: "bg-amber-50",  text: "text-amber-600",  ring: "ring-amber-100" },
  error:   { icon: XCircle,        bg: "bg-red-50",    text: "text-red-600",    ring: "ring-red-100" },
};

function NotifItem({ notif, isAr, t, onOpen }: { notif: AppNotification; isAr: boolean; t: any; onOpen: (n: AppNotification) => void }) {
  const { icon: Icon, bg, text, ring } = TYPE_STYLES[notif.type];
  const title = isAr ? notif.titleAr : notif.titleEn;
  const body = isAr ? notif.bodyAr : notif.bodyEn;

  return (
    <motion.div
      initial={{ opacity: 0, x: isAr ? -10 : 10 }}
      animate={{ opacity: 1, x: 0 }}
      onClick={() => onOpen(notif)}
      className={`flex gap-3 px-4 py-3 hover:bg-muted/40 transition-colors cursor-pointer ${isAr ? "flex-row-reverse text-right" : ""} ${!notif.read ? "bg-primary/[0.03]" : ""}`}
    >
      <div className={`flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${bg} ring-1 ${ring}`}>
        <Icon className={`w-4 h-4 ${text}`} />
      </div>
      <div className="flex-1 min-w-0">
        <div className={`flex items-center justify-between gap-2 ${isAr ? "flex-row-reverse" : ""}`}>
          <p className={`text-xs font-semibold text-foreground truncate ${!notif.read ? "text-primary" : ""}`}>{title}</p>
          <span className="text-[10px] text-muted-foreground whitespace-nowrap flex-shrink-0">
            {timeAgo(notif.createdAt, isAr, t)}
          </span>
        </div>
        <p className="text-xs text-muted-foreground mt-0.5 leading-relaxed line-clamp-2">{body}</p>
      </div>
      {!notif.read && (
        <div className={`flex-shrink-0 w-1.5 h-1.5 rounded-full bg-primary mt-1.5 ${isAr ? "ml-0 mr-auto" : "mr-0 ml-auto"} self-start`} />
      )}
    </motion.div>
  );
}

export function NotificationPanel({ open, onClose, anchorRef }: NotificationPanelProps) {
  const { notifications, unreadCount, permission, requestPermission, markAllRead, markRead, clearAll } = useNotifications();
  const [, nav] = useLocation();
  const open_ = (n: AppNotification) => {
    markRead(n.id);
    onClose();
    nav(routeForNotification(n.kind ?? "", n.data));   // a click always opens the page the notification is about
  };
  const { t, isRTL } = useLang();
  const panelRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    function handle(e: MouseEvent) {
      if (
        panelRef.current && !panelRef.current.contains(e.target as Node) &&
        anchorRef.current && !anchorRef.current.contains(e.target as Node)
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
    const handle = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", handle);
    return () => document.removeEventListener("keydown", handle);
  }, [open, onClose]);

  const panel = (
    <AnimatePresence>
      {open && (
        <motion.div
          ref={panelRef}
          initial={{ opacity: 0, y: -8, scale: 0.97 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -8, scale: 0.97 }}
          transition={{ duration: 0.18, ease: "easeOut" }}
          className={`fixed top-16 ${isRTL ? "left-4" : "right-4"} z-50 w-96 max-w-[calc(100vw-2rem)] bg-background border border-border rounded-2xl shadow-2xl flex flex-col overflow-hidden`}
          dir={isRTL ? "rtl" : "ltr"}
        >
          {/* Header */}
          <div className={`flex items-center justify-between px-4 py-3 border-b border-border`}>
            <div className="flex items-center gap-2">
              <Bell className="w-4 h-4 text-primary" />
              <span className="font-semibold text-sm text-foreground">{t.notifications}</span>
              {unreadCount > 0 && (
                <span className="bg-primary text-primary-foreground text-[10px] font-bold rounded-full px-1.5 py-0.5 min-w-[18px] text-center">
                  {unreadCount}
                </span>
              )}
            </div>
            <div className="flex items-center gap-1">
              {unreadCount > 0 && (
                <button
                  onClick={markAllRead}
                  title={t.notifMarkAllRead}
                  className="p-1.5 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                >
                  <CheckCheck className="w-3.5 h-3.5" />
                </button>
              )}
              {notifications.length > 0 && (
                <button
                  onClick={clearAll}
                  title={t.notifClearAll}
                  className="p-1.5 rounded-lg text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              )}
              <button
                onClick={onClose}
                className="p-1.5 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* Desktop notification permission banner */}
          {permission === "default" && (
            <div className={`mx-3 mt-3 rounded-xl bg-primary/5 border border-primary/20 p-3 flex items-start gap-3 ${isRTL ? "flex-row-reverse text-right" : ""}`}>
              <Bell className="w-4 h-4 text-primary flex-shrink-0 mt-0.5" />
              <div className="flex-1 min-w-0">
                <p className="text-xs font-semibold text-foreground">{t.notifPermissionTitle}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{t.notifPermissionDesc}</p>
              </div>
              <button
                onClick={requestPermission}
                className="flex-shrink-0 text-xs font-medium bg-primary text-primary-foreground px-2.5 py-1 rounded-lg hover:bg-primary/90 transition-colors"
              >
                {t.notifPermissionAllow}
              </button>
            </div>
          )}

          {/* Notification list */}
          <div className="overflow-y-auto max-h-[420px] divide-y divide-border/50">
            {notifications.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 gap-3 text-muted-foreground">
                <BellOff className="w-10 h-10 opacity-30" />
                <p className="text-sm">{t.notifEmpty}</p>
              </div>
            ) : (
              notifications.map((notif) => (
                <NotifItem key={notif.id} notif={notif} isAr={isRTL} t={t}  onOpen={open_} />
              ))
            )}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );

  return createPortal(panel, document.body);
}
