// Tiny helpers shared by the newer portal pages.
export const authToken = () => localStorage.getItem("hr-token") ?? "";

export async function api<T = any>(path: string, method = "GET", body?: unknown): Promise<T> {
  const r = await fetch(`/api${path}`, {
    method,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${authToken()}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error((data as any).error || "Request failed");
  return data as T;
}

/** Download a protected file (CSV export) with the login token. */
export async function downloadFile(path: string, filename: string): Promise<void> {
  const r = await fetch(`/api${path}`, { headers: { Authorization: `Bearer ${authToken()}` } });
  if (!r.ok) {
    const d = await r.json().catch(() => ({}));
    throw new Error((d as any).error || "Download failed");
  }
  const blob = await r.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export function money(v: number | string | null | undefined, currency = "EGP"): string {
  const n = Number(v ?? 0);
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency, maximumFractionDigits: n % 1 === 0 ? 0 : 2 }).format(n);
  } catch {
    return `${n.toLocaleString()} ${currency}`;
  }
}

export const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

/** Absolute URL for uploaded files (logos, avatars). */
export const fileUrl = (p?: string | null) => (!p ? "" : p.startsWith("http") ? p : p);
