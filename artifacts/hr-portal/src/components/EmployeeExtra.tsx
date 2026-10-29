import { inputCls, useTr } from "@/components/kit";

/** Search text: one spelling of the Arabic letters people type differently, no accents, Arabic digits as 0-9. */
export function normSearch(t: string): string {
  return (t || "").toLowerCase().trim()
    .replace(/[ً-ٰٟـ]/g, "")
    .replace(/[أإآٱ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه").replace(/ؤ/g, "و").replace(/ئ/g, "ي")
    .replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)))
    .replace(/\s+/g, " ");
}

/** Days from today until the residence expires (negative = already expired); null when no date. */
export function iqamaDaysLeft(expiry?: string | null): number | null {
  if (!expiry) return null;
  const d = new Date(String(expiry).slice(0, 10) + "T00:00:00");
  if (isNaN(d.getTime())) return null;
  const t = new Date(); t.setHours(0, 0, 0, 0);
  return Math.round((d.getTime() - t.getTime()) / 86400000);
}

/** When the person first signed in (created the password); attendance is counted from that day. */
export function FirstSignin({ at }: { at?: string | null }) {
  const tr = useTr();
  return at
    ? <div className="mt-1 inline-flex px-2 py-0.5 rounded-full text-[11px] border bg-emerald-50 text-emerald-800 border-emerald-200">{tr("First sign-in: ", "أول تسجيل دخول: ")}{String(at).slice(0, 10)}</div>
    : <div className="mt-1 inline-flex px-2 py-0.5 rounded-full text-[11px] border bg-slate-50 text-slate-600 border-slate-200">{tr("Has not signed in yet — attendance not counted", "لم يسجّل الدخول بعد — الحضور غير محسوب")}</div>;
}

/** Residence status chip: valid / under a month / expired, with the days left. */
export function IqamaChip({ expiry }: { expiry?: string | null }) {
  const tr = useTr();
  const n = iqamaDaysLeft(expiry);
  if (n === null) return null;
  const [cls, label] = n < 0
    ? ["bg-red-50 text-red-800 border-red-200", tr("Residence expired", "الهوية منتهية")]
    : n <= 30
      ? ["bg-amber-50 text-amber-800 border-amber-200", tr("Less than a month left", "متبقي أقل من شهر")]
      : ["bg-emerald-50 text-emerald-800 border-emerald-200", tr("Residence valid", "الهوية سارية")];
  return (
    <div className={`mt-1 inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] border ${cls}`}>
      {label} · {n < 0 ? tr(`${-n} days ago`, `منذ ${-n} يوم`) : tr(`${n} days`, `${n} يوم`)}
    </div>
  );
}

/** ID / residence details (nationality, ID number, bank account, residence expiry). Named inputs, read with extraFromForm(). */
export function EmployeeExtraFields({ e }: { e?: any }) {
  const tr = useTr();
  const lab = "block text-xs text-muted-foreground mb-1";
  return (
    <div className="rounded-xl border border-border p-4 space-y-3 bg-muted/20">
      <p className="text-sm font-semibold">{tr("ID & residence", "الهوية والإقامة")}</p>
      <div className="grid grid-cols-2 gap-3">
        <div><label className={lab}>{tr("Nationality", "الجنسية")}</label><input name="nationality" className={inputCls} defaultValue={e?.nationality ?? ""} /></div>
        <div><label className={lab}>{tr("ID / residence number", "رقم الهوية / الإقامة")}</label><input name="idNumber" dir="ltr" className={inputCls} defaultValue={e?.idNumber ?? ""} /></div>
        <div className="col-span-2"><label className={lab}>{tr("Bank account (IBAN)", "رقم الحساب البنكي (IBAN)")}</label><input name="bankIban" dir="ltr" className={inputCls} defaultValue={e?.bankIban ?? ""} /></div>
        <div><label className={lab}>{tr("Residence expires on", "تاريخ انتهاء الإقامة")}</label><input type="date" name="iqamaExpiry" className={inputCls} defaultValue={(e?.iqamaExpiry ?? "").slice(0, 10)} /></div>
        {e?.iqamaExpiry && <div className="col-span-2"><IqamaChip expiry={e.iqamaExpiry} /></div>}
        <div>
          <label className={lab}>{tr("Renewal period", "مدة التجديد")}</label>
          <select name="iqamaRenewMonths" className={inputCls} defaultValue={e?.iqamaRenewMonths ?? ""}>
            <option value="">—</option>
            {[3, 6, 12, 24].map((m) => <option key={m} value={m}>{m} {tr("months", "أشهر")}</option>)}
          </select>
        </div>
      </div>
    </div>
  );
}

const val = (fd: FormData, k: string) => { const v = String(fd.get(k) ?? "").trim(); return v === "" ? null : v; };

/** The extra fields from a form (empty becomes null, so an edit can clear them). */
export function extraFromForm(fd: FormData) {
  const m = val(fd, "iqamaRenewMonths");
  return { nationality: val(fd, "nationality"), idNumber: val(fd, "idNumber"), bankIban: val(fd, "bankIban"), iqamaExpiry: val(fd, "iqamaExpiry"), iqamaRenewMonths: m ? Number(m) : null };
}
