import { useState } from "react";
import { Building2, Check, ChevronsUpDown, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/contexts/AuthContext";
import { useTr } from "@/components/kit";

/** Label for what the signed-in person may do inside a company of the group. */
export function accessLabel(tr: (en: string, ar: string) => string, level: string, readOnly: boolean): string {
  if (level === "home") return tr("Your company", "شركتك");
  if (level === "super") return tr("Super admin", "المدير العام");
  if (readOnly) return tr("Read only", "للقراءة فقط");
  return level === "full" ? tr("Full control", "تحكم كامل") : tr("Chosen parts", "أجزاء محددة");
}

/**
 * Company switcher for the sidebar. A person works inside ONE company at a time; the server decides whether a
 * switch is allowed and the page reloads afterwards, so nothing of the old company stays on screen.
 */
export function CompanySwitcher() {
  const { group, company, switchCompany } = useAuth();
  const tr = useTr();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState<number | null>(null);

  if (!group || group.companies.length < 2) return null;
  const activeId = company?.id ?? group.activeCompanyId;

  async function go(id: number) {
    if (id === activeId) {
      setOpen(false);
      return;
    }
    setBusy(id);
    try {
      await switchCompany(id);
    } catch (e: any) {
      toast.error(e.message);
      setBusy(null);
    }
  }

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        className="w-full flex items-center gap-2 rounded-xl border border-border bg-background px-3 py-2 text-sm font-medium hover:bg-muted transition"
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <Building2 className="h-4 w-4 text-primary shrink-0" />
        <span className="flex-1 truncate text-start">{company?.name}</span>
        <ChevronsUpDown className="h-4 w-4 text-muted-foreground shrink-0" />
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute z-50 mt-2 w-full min-w-64 rounded-xl border border-border bg-card shadow-xl p-2 space-y-1">
            <p className="px-2 py-1 text-xs text-muted-foreground">
              {tr("You work inside one company at a time. Nothing is mixed between companies.", "تعمل داخل شركة واحدة في كل مرة، ولا يختلط أي شيء بين الشركات.")}
            </p>
            {group.companies.map((c) => (
              <button
                key={c.id}
                disabled={!c.status || c.status !== "active" || busy !== null}
                onClick={() => go(c.id)}
                className="w-full flex items-center gap-2 rounded-lg px-2 py-2 text-sm hover:bg-muted disabled:opacity-50 text-start"
              >
                <span className="flex-1 min-w-0">
                  <span className="block truncate font-medium">{c.name}</span>
                  <span className="block text-xs text-muted-foreground truncate">
                    {accessLabel(tr, c.access.level, c.access.readOnly)}
                    {c.ceo ? ` · ${tr("CEO", "الرئيس التنفيذي")}: ${c.ceo.name}` : ""}
                  </span>
                </span>
                {busy === c.id ? <Loader2 className="h-4 w-4 animate-spin" /> : c.id === activeId ? <Check className="h-4 w-4 text-primary" /> : null}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
