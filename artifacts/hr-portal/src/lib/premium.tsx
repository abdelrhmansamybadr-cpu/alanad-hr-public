import { useCallback, useEffect, useState } from "react";
import { ToggleLeft } from "lucide-react";
import { api } from "@/lib/http";
import { useTr } from "@/components/kit";

/** 'local_laws' -> 'localLaws' (the server sends switches with camelCase keys). */
export const camel = (k: string) => k.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());

/** The server says "This feature is turned off for your company." when the owner has switched a feature off. */
export const isOff = (e: unknown) => /turned off/i.test((e as Error | undefined)?.message ?? "");

/** Load one endpoint; `error` is set when it fails. Reload with `reload()`. */
export function useLoad<T>(path: string | null, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [loading, setLoading] = useState(path !== null);
  const reload = useCallback(() => {
    if (path === null) return Promise.resolve();
    setLoading(true);
    return api<T>(path)
      .then((d) => { setData(d); setError(null); })
      .catch((e: Error) => setError(e))
      .finally(() => setLoading(false));
  }, [path]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { reload(); }, [reload, ...deps]);
  return { data, error, loading, reload };
}

/** Is the signed-in person the platform owner / a group Super Admin? (the server decides) */
export function useOwnerMe() {
  const { data } = useLoad<{ isOwner?: boolean; isSuperAdmin?: boolean; canManage?: boolean }>("/owner/me");
  return { isOwner: !!data?.isOwner, canManage: !!data?.canManage };
}

/** Shown when a premium feature is switched off for the company (the server answers 403 'turned off'). */
export function FeatureOff() {
  const tr = useTr();
  return (
    <div className="p-12 text-center bg-card border border-border rounded-2xl space-y-2">
      <ToggleLeft className="h-12 w-12 mx-auto text-muted-foreground" />
      <p className="font-bold text-lg">{tr("This feature is turned off", "هذه الخدمة متوقفة")}</p>
      <p className="text-muted-foreground">{tr("The owner switched it off. It comes back with all its data when it is switched on again.", "أوقفها المالك. وتعود بكل بياناتها عند تشغيلها من جديد.")}</p>
    </div>
  );
}

export const fmtMoney = (v: number | string | null | undefined, cur = "EGP") => {
  const n = Number(v ?? 0);
  try { return new Intl.NumberFormat(undefined, { style: "currency", currency: cur, maximumFractionDigits: n % 1 === 0 ? 0 : 2 }).format(n); } catch { return `${n.toLocaleString()} ${cur}`; }
};
