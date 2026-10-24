import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useRef,
  ReactNode,
} from "react";
import { navigate } from "wouter/use-browser-location";
import { routeForNotification } from "@/lib/notificationRoute";

export type NotifType = "info" | "success" | "warning" | "error";

export interface AppNotification {
  id: string;
  type: NotifType;
  titleAr: string;
  titleEn: string;
  bodyAr: string;
  bodyEn: string;
  read: boolean;
  createdAt: Date;
  /** the server's own kind (leave_request, meeting, payslip ...) and data: used to open the right page on click */
  kind?: string;
  data?: any;
}

interface NotificationContextValue {
  notifications: AppNotification[];
  unreadCount: number;
  permission: NotificationPermission | "unsupported";
  requestPermission: () => Promise<void>;
  push: (notif: Omit<AppNotification, "id" | "read" | "createdAt">) => void;
  markAllRead: () => void;
  markRead: (id: string) => void;
  clearAll: () => void;
}

const NotificationContext = createContext<NotificationContextValue | null>(null);

export function useNotifications() {
  const ctx = useContext(NotificationContext);
  if (!ctx) throw new Error("useNotifications must be used inside NotificationProvider");
  return ctx;
}

const POLL_MS = 30_000;

function authFetch(path: string, init?: RequestInit) {
  const token = localStorage.getItem("hr-token");
  if (!token) return Promise.resolve(null);
  return fetch(path, {
    ...init,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, ...(init?.headers ?? {}) },
  }).catch(() => null);
}

function kindOf(type: string): NotifType {
  const t = (type || "").toLowerCase();
  if (t.includes("reject") || t.includes("denied") || t.includes("error")) return "error";
  if (t.includes("approv") || t.includes("payslip") || t.includes("paid") || t.includes("success")) return "success";
  if (t.includes("late") || t.includes("expire") || t.includes("warn")) return "warning";
  return "info";
}

interface ServerNotification {
  id: number;
  type: string;
  title: string;
  body?: string | null;
  readAt?: string | null;
  createdAt: string;
  data?: any;
}

export function NotificationProvider({ children }: { children: ReactNode }) {
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
  const [permission, setPermission] = useState<NotificationPermission | "unsupported">(
    typeof Notification === "undefined" ? "unsupported" : Notification.permission,
  );
  const seen = useRef<Set<string>>(new Set());
  const firstLoad = useRef(true);

  const unreadCount = notifications.filter((n) => !n.read).length;

  const requestPermission = useCallback(async () => {
    if (typeof Notification === "undefined") return;
    const result = await Notification.requestPermission();
    setPermission(result);
  }, []);

  const desktop = useCallback((title: string, body: string, path?: string) => {
    if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
    try {
      const n = new Notification(title, { body, icon: "/favicon.ico", tag: title } as NotificationOptions);
      n.onclick = () => {
        window.focus();
        if (path) navigate(path);   // clicking the system notification opens the page it is about
        n.close();
      };
    } catch {
      // ignore
    }
  }, []);

  const load = useCallback(async () => {
    const r = await authFetch("/api/notifications?limit=50");
    if (!r || !r.ok) return;
    const data = await r.json().catch(() => null);
    const items: ServerNotification[] = data?.items ?? [];
    const mapped: AppNotification[] = items.map((n) => ({
      id: String(n.id),
      type: kindOf(n.type),
      titleAr: n.title,
      titleEn: n.title,
      bodyAr: n.body ?? "",
      bodyEn: n.body ?? "",
      read: !!n.readAt,
      createdAt: new Date(String(n.createdAt).replace(" ", "T") + "Z"),
      kind: n.type,
      data: n.data,
    }));
    if (!firstLoad.current) {
      for (const n of mapped) {
        if (!n.read && !seen.current.has(n.id)) desktop(n.titleEn, n.bodyEn, routeForNotification(n.kind ?? "", n.data));
      }
    }
    mapped.forEach((n) => seen.current.add(n.id));
    firstLoad.current = false;
    setNotifications(mapped);
  }, [desktop]);

  useEffect(() => {
    load();
    const timer = setInterval(() => {
      if (!document.hidden) load();
    }, POLL_MS);
    const onLogin = () => {
      firstLoad.current = true;
      load();
    };
    window.addEventListener("focus", load);
    window.addEventListener("hr-login", onLogin);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", load);
      window.removeEventListener("hr-login", onLogin);
    };
  }, [load]);

  // Local-only notification (used for immediate UI feedback)
  const push = useCallback(
    (notif: Omit<AppNotification, "id" | "read" | "createdAt">) => {
      setNotifications((prev) => [{ ...notif, id: crypto.randomUUID(), read: false, createdAt: new Date() }, ...prev]);
    },
    [],
  );

  const markAllRead = useCallback(() => {
    setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
    authFetch("/api/notifications/read", { method: "POST", body: JSON.stringify({ all: true }) });
  }, []);

  const markRead = useCallback((id: string) => {
    setNotifications((prev) => prev.map((n) => (n.id === id ? { ...n, read: true } : n)));
    if (/^\d+$/.test(id)) authFetch("/api/notifications/read", { method: "POST", body: JSON.stringify({ ids: [Number(id)] }) });
  }, []);

  const clearAll = useCallback(() => {
    setNotifications((prev) => {
      prev.forEach((n) => {
        if (/^\d+$/.test(n.id)) authFetch(`/api/notifications/${n.id}`, { method: "DELETE" });
      });
      return [];
    });
  }, []);

  return (
    <NotificationContext.Provider
      value={{ notifications, unreadCount, permission, requestPermission, push, markAllRead, markRead, clearAll }}
    >
      {children}
    </NotificationContext.Provider>
  );
}
