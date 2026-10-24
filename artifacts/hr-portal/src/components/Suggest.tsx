import { useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown } from "lucide-react";
import { useLang } from "@/contexts/LanguageContext";
import { departmentOptions, isKnownTitle, norm, titleOptions, type Suggestion } from "@/lib/jobCatalog";

const FIELD =
  "w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none bg-background";

/**
 * A text box with a big drop-down list that filters while the person types. Anything can be typed: the list only
 * suggests, it never blocks. The value is a normal `<input name=...>` so plain forms (FormData) keep working.
 */
export function Suggest({
  value, onChange, options, name, placeholder, className, required, emptyHint,
}: {
  value: string;
  onChange: (v: string) => void;
  options: Suggestion[];
  name?: string;
  placeholder?: string;
  className?: string;
  required?: boolean;
  emptyHint?: string;
}) {
  const { isRTL } = useLang();
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const box = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  const q = norm(value);
  const shown = useMemo(() => {
    if (!q) return options;
    return options.filter((o) => norm(o.label).includes(q) || (o.alt && norm(o.alt).includes(q)));
  }, [options, q]);

  useEffect(() => {
    const close = (e: MouseEvent) => { if (box.current && !box.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, []);
  useEffect(() => { setActive(-1); }, [q, open]);
  useEffect(() => {
    if (active < 0) return;
    (listRef.current?.children[active] as HTMLElement | undefined)?.scrollIntoView({ block: "nearest" });
  }, [active]);

  const pick = (s: Suggestion) => { onChange(s.label); setOpen(false); };

  return (
    <div ref={box} className="relative">
      <input
        name={name}
        required={required}
        value={value}
        placeholder={placeholder}
        autoComplete="off"
        dir={isRTL ? "rtl" : "ltr"}
        className={className ?? `${FIELD} ${isRTL ? "pl-9" : "pr-9"}`}
        onFocus={() => setOpen(true)}
        onChange={(e) => { onChange(e.target.value); setOpen(true); }}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown") { e.preventDefault(); setOpen(true); setActive((a) => Math.min(shown.length - 1, a + 1)); }
          else if (e.key === "ArrowUp") { e.preventDefault(); setActive((a) => Math.max(0, a - 1)); }
          else if (e.key === "Enter" && open && active >= 0 && shown[active]) { e.preventDefault(); pick(shown[active]); }
          else if (e.key === "Escape") setOpen(false);
        }}
      />
      <button
        type="button"
        tabIndex={-1}
        aria-label="list"
        onClick={() => setOpen((o) => !o)}
        className={`absolute top-1/2 -translate-y-1/2 text-muted-foreground ${isRTL ? "left-2.5" : "right-2.5"}`}
      >
        <ChevronDown className="h-4 w-4" />
      </button>
      {open && (
        <div
          ref={listRef}
          className="absolute z-[70] mt-1 w-full max-h-72 overflow-auto rounded-xl border border-border bg-card shadow-xl py-1"
        >
          {shown.length === 0 ? (
            <div className="px-3 py-2.5 text-sm text-muted-foreground">
              {emptyHint ?? (isRTL ? "غير موجود في القائمة — سيُحفظ كما كتبته." : "Not in the list — it will be saved as you typed it.")}
            </div>
          ) : (
            shown.map((o, i) => (
              <button
                type="button"
                key={o.label}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => pick(o)}
                className={`w-full text-start px-3 py-2 text-sm hover:bg-muted flex items-center justify-between gap-3 ${i === active ? "bg-muted" : ""} ${o.label === value ? "font-semibold text-primary" : ""}`}
              >
                <span>{o.label}</span>
                {o.alt && <span className="text-xs text-muted-foreground" dir={isRTL ? "ltr" : "rtl"}>{o.alt}</span>}
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}

/** Department name: suggests every department a company can have, accepts anything else. */
export function DepartmentInput({ value, onChange, className }: { value: string; onChange: (v: string) => void; className?: string }) {
  const { isRTL } = useLang();
  const options = useMemo(() => departmentOptions(isRTL ? "ar" : "en"), [isRTL]);
  return <Suggest value={value} onChange={onChange} options={options} className={className} placeholder={isRTL ? "اكتب أو اختر من القائمة" : "Type or pick from the list"} />;
}

/**
 * Job title: suggests the titles that fit the chosen department (plus the ones already used in the company).
 * `confirmNewTitle` asks before saving a title that is not in the list.
 */
export function PositionInput({
  value, onChange, deptName, existing, name, required, className,
}: { value: string; onChange: (v: string) => void; deptName: string; existing?: string[]; name?: string; required?: boolean; className?: string }) {
  const { isRTL } = useLang();
  const lang = isRTL ? "ar" : "en";
  const options = useMemo(() => titleOptions(deptName, lang, existing ?? []), [deptName, lang, existing]);
  return (
    <Suggest
      name={name}
      required={required}
      value={value}
      onChange={onChange}
      options={options}
      className={className}
      placeholder={isRTL ? "اكتب أو اختر المسمى" : "Type or pick a job title"}
      emptyHint={isRTL ? "مسمى جديد غير موجود في القائمة — سنسألك قبل حفظه." : "A new title that is not in the list — we will ask before saving it."}
    />
  );
}

/** Returns true when it is fine to save: the title is known, or the person agreed to save it as a new title. */
export function confirmNewTitle(title: string, deptName: string, isRTL: boolean, existing: string[] = []): boolean {
  const t = title.trim();
  if (!t || isKnownTitle(t, deptName, isRTL ? "ar" : "en", existing)) return true;
  return window.confirm(
    isRTL
      ? `المسمى «${t}» غير موجود في القائمة.\nهل تريد حفظه كمسمى وظيفي جديد؟`
      : `The job title "${t}" is not in the list.\nSave it as a new job title?`,
  );
}
