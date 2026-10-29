import { ReactNode } from "react";
import { X } from "lucide-react";
import { useLang } from "@/contexts/LanguageContext";

/** Translate inline: tr("English", "العربية"). */
export function useTr() {
  const { isRTL } = useLang();
  return (en: string, ar: string) => (isRTL ? ar : en);
}

export const inputCls =
  "w-full px-3 py-2 border border-border rounded-xl bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary";
export const cardCls = "bg-card border border-border rounded-2xl p-5 shadow-sm";
export const btnCls =
  "inline-flex items-center justify-center gap-2 px-4 py-2 rounded-xl bg-primary text-primary-foreground text-sm font-medium hover:opacity-90 disabled:opacity-50 transition";
export const btnGhost =
  "inline-flex items-center justify-center gap-2 px-4 py-2 rounded-xl border border-border text-sm font-medium hover:bg-muted transition disabled:opacity-50";

export function PageHeader({ title, subtitle, children }: { title: string; subtitle?: string; children?: ReactNode }) {
  const { isRTL } = useLang();
  return (
    <div className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isRTL ? "sm:flex-row-reverse text-right" : ""}`}>
      <div>
        <h1 className="text-3xl font-bold text-foreground tracking-tight">{title}</h1>
        {subtitle && <p className="text-muted-foreground mt-1">{subtitle}</p>}
      </div>
      {children && <div className="flex flex-wrap items-center gap-2">{children}</div>}
    </div>
  );
}

export function Modal({ open, title, onClose, children, wide }: { open: boolean; title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  const { isRTL } = useLang();
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div dir={isRTL ? "rtl" : "ltr"} className={`bg-card w-full ${wide ? "max-w-3xl" : "max-w-lg"} max-h-[90vh] overflow-y-auto rounded-2xl shadow-xl border border-border`}>
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card z-10">
          <h2 className="text-lg font-bold">{title}</h2>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted" aria-label="close">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}

export function Field({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) {
  return (
    <label className="block text-sm">
      <span className="block mb-1 font-medium">{label}</span>
      {children}
      {hint && <span className="block mt-1 text-xs text-muted-foreground">{hint}</span>}
    </label>
  );
}

const TONES: Record<string, string> = {
  green: "bg-emerald-100 text-emerald-700",
  amber: "bg-amber-100 text-amber-700",
  red: "bg-red-100 text-red-700",
  blue: "bg-blue-100 text-blue-700",
  orange: "bg-orange-100 text-orange-700",
  gray: "bg-muted text-muted-foreground",
  violet: "bg-teal-100 text-teal-700",
};

export function Badge({ tone = "gray", children }: { tone?: keyof typeof TONES | string; children: ReactNode }) {
  return <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${TONES[tone] ?? TONES.gray}`}>{children}</span>;
}

export const STATUS_TONE: Record<string, string> = {
  present: "green", late: "amber", half_day: "orange", absent: "red", on_leave: "blue", not_in: "gray", not_started: "gray", off: "gray", holiday: "violet",
  approved: "green", pending: "amber", rejected: "red", cancelled: "gray", paid: "green", active: "green", inactive: "gray",
};

export function Empty({ text }: { text: string }) {
  return <div className="p-10 text-center text-muted-foreground bg-card border border-border rounded-2xl">{text}</div>;
}

export function Spinner() {
  return (
    <div className="flex justify-center p-12">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
    </div>
  );
}

/** The three reward points as glossy orbs. */
export function Orb({ kind, size = 28 }: { kind: "green" | "red" | "black"; size?: number }) {
  const c = {
    green: ["#BBF7D0", "#22C55E", "#15803D", "#4ADE80"],
    red: ["#FECACA", "#EF4444", "#B91C1C", "#F87171"],
    black: ["#6B7280", "#1F2937", "#030712", "#94A3B8"],
  }[kind];
  return (
    <span
      style={{
        width: size, height: size, display: "inline-block", borderRadius: "50%",
        background: `radial-gradient(circle at 32% 28%, ${c[0]}, ${c[1]} 52%, ${c[2]})`,
        boxShadow: `0 0 ${size * 0.5}px ${c[3]}66, inset 0 -${size * 0.08}px ${size * 0.15}px rgba(0,0,0,.25)`,
      }}
    />
  );
}
