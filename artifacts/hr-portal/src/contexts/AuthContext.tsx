import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  ReactNode,
} from "react";
import {
  startRegistration,
  startAuthentication,
  browserSupportsWebAuthn,
  platformAuthenticatorIsAvailable,
} from "@simplewebauthn/browser";
import { setAuthTokenGetter, setBaseUrl } from "@workspace/api-client-react";

// Resolve absolute base URL so fetch works in all environments
// (Vite dev proxy, Replit, production, etc.)
const API_ORIGIN =
  typeof window !== "undefined" ? window.location.origin : "http://localhost:3001";

// Set base URL for the generated API client (customFetch)
setBaseUrl(API_ORIGIN);

function apiUrl(path: string): string {
  return `${API_ORIGIN}${path}`;
}

export interface AuthUser {
  id: number;
  name: string;
  email: string;
  role: string;
  avatar?: string | null;
  title?: string | null;
  phone?: string | null;
  status?: string;
  permissions?: { module: string; enabled: boolean }[];
}

export interface Company {
  id: number;
  name: string;
  logoUrl?: string | null;
  primaryColor: string;
  accentColor: string;
  timezone: string;
  currency: string;
  weekendDays: string;
  lateGraceMinutes: number;
  modules: string[] | null;
  /** Premium features the owner switched on for this company (camelCase keys). Missing = off. */
  features?: Record<string, boolean>;
}

/** One company of the group, with what the signed-in person may do inside it. */
export interface GroupCompany {
  id: number;
  name: string;
  status: string;
  isHome: boolean;
  ceo?: { id: number; name: string; email: string } | null;
  access: { level: "home" | "super" | "full" | "custom"; readOnly: boolean; modules: string[] | null };
  employeeCount?: number;
  departmentCount?: number;
}

/** The holding company and the companies the signed-in person can enter (null outside a group). */
export interface GroupInfo {
  id: number;
  name: string;
  isSuperAdmin: boolean;
  /** The platform owner: creates companies and decides which HR managers run each one. */
  isOwner?: boolean;
  homeCompanyId: number;
  activeCompanyId: number;
  companies: GroupCompany[];
}

interface AuthContextValue {
  user: AuthUser | null;
  company: Company | null;
  group: GroupInfo | null;
  /** Work inside another company of the group (the page reloads so nothing of the old company stays on screen). */
  switchCompany: (companyId: number) => Promise<void>;
  refreshCompany: () => Promise<void>;
  token: string | null;
  isLoading: boolean;
  isManager: boolean;
  hasPermission: (module: string) => boolean;
  login: (email: string, password: string) => Promise<void>;
  loginWithPasskey: (email?: string) => Promise<void>;
  register: (companyName: string, name: string, email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  updateProfile: (
    updates: Partial<Pick<AuthUser, "name" | "title" | "phone" | "avatar">>,
  ) => Promise<void>;
  changePassword: (
    currentPassword: string,
    newPassword: string,
  ) => Promise<void>;
  registerPasskey: () => Promise<void>;
  removePasskey: () => Promise<void>;
  passkeyStatus: { registered: boolean; registeredAt: string | null } | null;
  refreshPasskeyStatus: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
  return ctx;
}

function authHeader(token: string) {
  return { Authorization: `Bearer ${token}` };
}

interface AuthUserWithExtras extends AuthUser {
  status: string;
  permissions: { module: string; enabled: boolean }[];
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [company, setCompany] = useState<Company | null>(null);
  const [group, setGroup] = useState<GroupInfo | null>(null);
  const [token, setToken] = useState<string | null>(() => {
    const t = localStorage.getItem("hr-token");
    // Set immediately so customFetch has the token before any query fires
    setAuthTokenGetter(() => t);
    return t;
  });
  const [isLoading, setIsLoading] = useState(true);
  const [passkeyStatus, setPasskeyStatus] = useState<{
    registered: boolean;
    registeredAt: string | null;
  } | null>(null);

  // Always update the token getter synchronously so customFetch has it
  // before React re-renders child components and they fire queries.
  const applyToken = useCallback((t: string | null) => {
    setAuthTokenGetter(() => t);
    setToken(t);
  }, []);

  const isManager = user?.role === "hr_manager" || user?.role === "hr_admin";

  const hasPermission = useCallback(
    (module: string): boolean => {
      if (!user) return false;
      if (user.role === "hr_admin") return true;
      const perm = (user.permissions || []).find((p) => p.module === module);
      // HR managers can use everything unless an admin switched a module off for them.
      if (user.role === "hr_manager") return perm ? perm.enabled : true;
      return perm ? perm.enabled : false;
    },
    [user],
  );

  useEffect(() => {
    if (!token) {
      setIsLoading(false);
      return;
    }
    fetch(apiUrl("/api/auth/me"), { headers: authHeader(token) })
      .then((r) => (r.ok ? r.json() : null))
      .then((u: (AuthUserWithExtras & { company?: Company | null; group?: GroupInfo | null }) | null) => {
        if (u) {
          if (u.company) setCompany(u.company);
          setGroup(u.group ?? null);
          setUser({
            id: u.id,
            name: u.name,
            email: u.email,
            role: u.role,
            avatar: u.avatar,
            title: u.title,
            phone: u.phone,
            status: u.status,
            permissions: u.permissions || [],
          });
        } else {
          applyToken(null);
          localStorage.removeItem("hr-token");
        }
      })
      .catch(() => {
        applyToken(null);
        localStorage.removeItem("hr-token");
      })
      .finally(() => setIsLoading(false));
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    try {
      const r = await fetch(apiUrl("/api/auth/login"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });
      if (r.ok) {
        const { token: t, user: u, company: c, group: g } = await r.json();
        applyToken(t);
        setUser(u);
        setCompany(c ?? null);
        setGroup(g ?? null);
        localStorage.setItem("hr-token", t);
        try { sessionStorage.removeItem("hr-no-auto"); } catch { /* storage blocked */ }
        window.dispatchEvent(new Event("hr-login"));
        return;
      }
      if (r.status === 401) {
        const err = await r.json().catch(() => ({}));
        throw new Error(err.error || "Invalid email or password");
      }
      if (r.status === 403) {
        const err = await r.json().catch(() => ({}));
        throw new Error(err.error || "Account access denied");
      }
    } catch (err: any) {
      if (
        err.message === "Invalid email or password" ||
        err.message?.includes("Account")
      )
        throw err;
    }

    throw new Error("Invalid email or password");
  }, [applyToken]);

  const register = useCallback(
    async (companyName: string, name: string, email: string, password: string) => {
      const r = await fetch(apiUrl("/api/companies/register"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ companyName, name, email, password }),
      });
      if (!r.ok) {
        const err = await r.json().catch(() => ({}));
        throw new Error(err.error || "Registration failed");
      }
      const { token: t, user: u, company: c } = await r.json();
      applyToken(t);
      setUser(u);
      setCompany(c ?? null);
      localStorage.setItem("hr-token", t);
        window.dispatchEvent(new Event("hr-login"));
    },
    [applyToken],
  );

  const refreshCompany = useCallback(async () => {
    if (!token) return;
    const r = await fetch(apiUrl("/api/auth/me"), { headers: authHeader(token) });
    if (r.ok) {
      const u = await r.json();
      if (u.company) setCompany(u.company);
      setGroup(u.group ?? null);
    }
  }, [token]);

  const switchCompany = useCallback(
    async (companyId: number) => {
      if (!token) return;
      const r = await fetch(apiUrl("/api/group/switch"), {
        method: "POST",
        headers: { "Content-Type": "application/json", ...authHeader(token) },
        body: JSON.stringify({ companyId }),
      });
      if (!r.ok) {
        const err = await r.json().catch(() => ({}));
        throw new Error(err.error || "Could not switch company");
      }
      // The server now remembers the company for this sign-in. Reload so no data of the old company stays on screen.
      window.location.assign(import.meta.env.BASE_URL || "/");
    },
    [token],
  );

  const logout = useCallback(async () => {
    if (token) {
      fetch(apiUrl("/api/auth/logout"), {
        method: "POST",
        headers: authHeader(token),
      }).catch(() => {});
    }
    applyToken(null);
    setUser(null);
    setCompany(null);
    setGroup(null);
    localStorage.removeItem("hr-token");
    // After an intentional sign-out the login page must not pop up Windows Hello by itself.
    try { sessionStorage.setItem("hr-no-auto", "1"); } catch { /* storage blocked */ }
  }, [token]);

  const updateProfile = useCallback(
    async (
      updates: Partial<Pick<AuthUser, "name" | "title" | "phone" | "avatar">>,
    ) => {
      if (!token) return;
      const r = await fetch(apiUrl("/api/auth/profile"), {
        method: "PUT",
        headers: { "Content-Type": "application/json", ...authHeader(token) },
        body: JSON.stringify(updates),
      });
      if (!r.ok) {
        const err = await r.json().catch(() => ({}));
        throw new Error(err.error || "Failed to update profile");
      }
      const u: AuthUser = await r.json();
      setUser(u);
    },
    [token, user],
  );

  const changePassword = useCallback(
    async (currentPassword: string, newPassword: string) => {
      if (!token) return;
      const r = await fetch(apiUrl("/api/auth/password"), {
        method: "PUT",
        headers: { "Content-Type": "application/json", ...authHeader(token) },
        body: JSON.stringify({ currentPassword, newPassword }),
      });
      if (!r.ok) {
        const err = await r.json().catch(() => ({}));
        throw new Error(err.error || "Failed to change password");
      }
    },
    [token],
  );

  // Does this account have a passkey (Windows Hello / fingerprint / face) registered?
  const refreshPasskeyStatus = useCallback(async () => {
    if (!token) return;
    try {
      const r = await fetch(apiUrl("/api/auth/webauthn"), { headers: authHeader(token) });
      if (!r.ok) return;
      const s = await r.json();
      setPasskeyStatus({ registered: !!s.registered, registeredAt: s.registeredAt ?? null });
    } catch {
      /* offline: keep the last known status */
    }
  }, [token]);

  useEffect(() => {
    if (token && user) {
      refreshPasskeyStatus();
    }
  }, [token, user, refreshPasskeyStatus]);

  // `email` is optional: without it the device offers the passkeys it holds for this site.
  const loginWithPasskey = useCallback(async (email?: string) => {
    const optRes = await fetch(apiUrl("/api/auth/webauthn/login-options"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(email ? { email } : {}),
    });
    if (!optRes.ok) {
      const err = await optRes.json().catch(() => ({}));
      throw new Error(err.error || "No passkey registered for this account");
    }
    const optionsJSON = await optRes.json();

    const assertionResponse = await startAuthentication({ optionsJSON });

    const verifyRes = await fetch(apiUrl("/api/auth/webauthn/login-verify"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email || undefined, assertionResponse }),
    });
    if (!verifyRes.ok) {
      const err = await verifyRes.json().catch(() => ({}));
      throw new Error(err.error || "Passkey authentication failed");
    }
    const { token: t, user: u, company: c, group: g } = await verifyRes.json();
    applyToken(t);
    setUser(u);
    if (c) setCompany(c);
    setGroup(g ?? null);
    localStorage.setItem("hr-token", t);
    try {
      localStorage.setItem("hr-passkey", "1");
      sessionStorage.removeItem("hr-no-auto");
    } catch { /* storage blocked */ }
    window.dispatchEvent(new Event("hr-login"));
  }, [applyToken]);

  const registerPasskey = useCallback(async () => {
    if (!token) throw new Error("Please log in with password first");

    const optRes = await fetch(apiUrl("/api/auth/webauthn/register-options"), {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeader(token) },
      body: "{}",
    });
    if (!optRes.ok) throw new Error("Failed to get registration options");
    const optionsJSON = await optRes.json();

    let attResp;
    try {
      attResp = await startRegistration({ optionsJSON });
    } catch (err: any) {
      if (err?.name === "InvalidStateError") throw new Error("This device is already set up. Windows Hello is active here.");
      if (err?.name === "NotAllowedError") throw new Error("Windows Hello was cancelled. Please try again.");
      throw err;
    }

    const verifyRes = await fetch(apiUrl("/api/auth/webauthn/register-verify"), {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeader(token) },
      body: JSON.stringify(attResp),
    });
    if (!verifyRes.ok) {
      const err = await verifyRes.json().catch(() => ({}));
      throw new Error(err.error || "Passkey registration failed");
    }
    try { localStorage.setItem("hr-passkey", "1"); } catch { /* storage blocked */ }
    await refreshPasskeyStatus();
  }, [token, refreshPasskeyStatus]);

  const removePasskey = useCallback(async () => {
    if (!token) return;
    const r = await fetch(apiUrl("/api/auth/webauthn"), {
      method: "DELETE",
      headers: authHeader(token),
    });
    if (!r.ok) throw new Error("Failed to remove passkey");
    try { localStorage.removeItem("hr-passkey"); } catch { /* storage blocked */ }
    setPasskeyStatus({ registered: false, registeredAt: null });
  }, [token]);

  return (
    <AuthContext.Provider
      value={{
        user,
        company,
        group,
        switchCompany,
        refreshCompany,
        token,
        isLoading,
        isManager,
        hasPermission,
        login,
        loginWithPasskey,
        register,
        logout,
        updateProfile,
        changePassword,
        registerPasskey,
        removePasskey,
        passkeyStatus,
        refreshPasskeyStatus,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
