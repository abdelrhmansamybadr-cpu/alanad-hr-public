import { useState, useMemo } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Users, Clock, X } from "lucide-react";
import { useLang } from "@/contexts/LanguageContext";
import { toast } from "sonner";
import { useListEmployees } from "@workspace/api-client-react";

type ShiftEmployee = {
  id: number;
  firstName: string;
  lastName: string;
  position: string;
  avatar?: string | null;
};

type Shift = {
  id: number;
  name: string;
  startTime: string;
  endTime: string;
  color: string;
  description?: string | null;
  days: string;
  createdAt: string;
  employees: ShiftEmployee[];
};

const SHIFTS_KEY = ["shifts"];

const COLORS = [
  { id: "blue", hex: "#3b82f6" },
  { id: "purple", hex: "#a855f7" },
  { id: "emerald", hex: "#10b981" },
  { id: "orange", hex: "#f97316" },
  { id: "rose", hex: "#f43f5e" },
  { id: "amber", hex: "#f59e0b" },
  { id: "teal", hex: "#14b8a6" },
  { id: "indigo", hex: "#6366f1" },
];

const COLOR_MAP: Record<string, string> = {
  blue: "#3b82f6", purple: "#a855f7", emerald: "#10b981", orange: "#f97316",
  rose: "#f43f5e", amber: "#f59e0b", teal: "#14b8a6", indigo: "#6366f1",
};

const ALL_DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

function formatTime(t: string) {
  const [h, m] = t.split(":").map(Number);
  const ampm = h >= 12 ? "PM" : "AM";
  const hour = h % 12 || 12;
  return `${hour}:${m.toString().padStart(2, "0")} ${ampm}`;
}

function calcDuration(start: string, end: string) {
  const [sh, sm] = start.split(":").map(Number);
  const [eh, em] = end.split(":").map(Number);
  let mins = (eh * 60 + em) - (sh * 60 + sm);
  if (mins < 0) mins += 24 * 60;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m > 0 ? `${h}h ${m}m` : `${h}h`;
}

function initials(first: string, last: string) {
  return `${first[0] ?? ""}${last[0] ?? ""}`.toUpperCase();
}

type FormState = { name: string; startTime: string; endTime: string; color: string; description: string; days: string };
const EMPTY_FORM: FormState = { name: "", startTime: "09:00", endTime: "17:00", color: "blue", description: "", days: "mon,tue,wed,thu,fri" };

export default function Shifts() {
  const queryClient = useQueryClient();
  const { t, isRTL } = useLang();
  const { data: employees = [] } = useListEmployees();

  const { data: shifts = [], isLoading } = useQuery<Shift[]>({
    queryKey: SHIFTS_KEY,
    queryFn: () => fetch("/api/shifts").then((r) => r.json()),
  });

  const [isAddOpen, setIsAddOpen] = useState(false);
  const [editShift, setEditShift] = useState<Shift | null>(null);
  const [manageShift, setManageShift] = useState<Shift | null>(null);
  const [deleteId, setDeleteId] = useState<number | null>(null);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);
  const [editForm, setEditForm] = useState<FormState>(EMPTY_FORM);

  const assignedIds = useMemo(
    () => new Set(shifts.flatMap((s) => s.employees.map((e) => e.id))),
    [shifts]
  );
  const unassignedEmployees = employees.filter((e) => !assignedIds.has(e.id));

  const dayLabel = (d: string) =>
    ({ mon: t.dayMon, tue: t.dayTue, wed: t.dayWed, thu: t.dayThu, fri: t.dayFri, sat: t.daySat, sun: t.daySun }[d] ?? d);

  const toggleDay = (day: string, current: string, set: (v: string) => void) => {
    const arr = current.split(",").filter(Boolean);
    const idx = arr.indexOf(day);
    if (idx >= 0) arr.splice(idx, 1); else arr.push(day);
    set(ALL_DAYS.filter((d) => arr.includes(d)).join(","));
  };

  // Mutations
  const createShift = useMutation({
    mutationFn: (data: FormState) =>
      fetch("/api/shifts", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) }).then((r) => r.json()),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: SHIFTS_KEY }); setIsAddOpen(false); setForm(EMPTY_FORM); toast.success(t.shiftSaved); },
    onError: () => toast.error(isRTL ? "فشل إنشاء الوردية" : "Failed to create shift"),
  });

  const updateShift = useMutation({
    mutationFn: ({ id, data }: { id: number; data: FormState }) =>
      fetch(`/api/shifts/${id}`, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) }).then((r) => r.json()),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: SHIFTS_KEY }); setEditShift(null); toast.success(t.shiftSaved); },
    onError: () => toast.error(isRTL ? "فشل التحديث" : "Failed to update"),
  });

  const deleteShift = useMutation({
    mutationFn: (id: number) => fetch(`/api/shifts/${id}`, { method: "DELETE" }).then((r) => r.json()),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: SHIFTS_KEY }); setDeleteId(null); toast.success(t.shiftDeleted); },
    onError: () => toast.error(isRTL ? "فشل الحذف" : "Failed to delete"),
  });

  const assignEmployee = useMutation({
    mutationFn: ({ employeeId, shiftId }: { employeeId: number; shiftId: number }) =>
      fetch("/api/shifts/assign", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ employeeId, shiftId }) }).then((r) => r.json()),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: SHIFTS_KEY }); toast.success(t.shiftAssigned); },
    onError: () => toast.error(isRTL ? "فشل التعيين" : "Failed to assign"),
  });

  const unassignEmployee = useMutation({
    mutationFn: (employeeId: number) => fetch(`/api/shifts/assign/${employeeId}`, { method: "DELETE" }).then((r) => r.json()),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: SHIFTS_KEY }); toast.success(t.shiftUnassigned); },
    onError: () => toast.error(isRTL ? "فشل الإزالة" : "Failed to remove"),
  });

  const openEdit = (s: Shift) => {
    setEditShift(s);
    setEditForm({ name: s.name, startTime: s.startTime, endTime: s.endTime, color: s.color, description: s.description ?? "", days: s.days });
  };

  // Shared form fields component
  const ShiftFormFields = ({ values, onChange }: { values: FormState; onChange: (v: FormState) => void }) => (
    <div className="space-y-4">
      <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
        <label className="text-sm font-medium">{t.shiftName}</label>
        <input
          required value={values.name}
          onChange={(e) => onChange({ ...values, name: e.target.value })}
          dir={isRTL ? "rtl" : "ltr"}
          className="w-full px-3 py-2 border border-border rounded-lg outline-none focus:ring-2 focus:ring-primary/20 bg-background"
          placeholder={isRTL ? "مثال: وردية الصباح" : "e.g. Morning Shift"}
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
          <label className="text-sm font-medium">{t.shiftStartTime}</label>
          <input required type="time" value={values.startTime}
            onChange={(e) => onChange({ ...values, startTime: e.target.value })}
            className="w-full px-3 py-2 border border-border rounded-lg outline-none focus:ring-2 focus:ring-primary/20 bg-background" />
        </div>
        <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
          <label className="text-sm font-medium">{t.shiftEndTime}</label>
          <input required type="time" value={values.endTime}
            onChange={(e) => onChange({ ...values, endTime: e.target.value })}
            className="w-full px-3 py-2 border border-border rounded-lg outline-none focus:ring-2 focus:ring-primary/20 bg-background" />
        </div>
      </div>

      {values.startTime && values.endTime && (
        <div className={`flex items-center gap-2 text-sm text-muted-foreground px-3 py-2 bg-primary/5 rounded-lg ${isRTL ? "flex-row-reverse" : ""}`}>
          <Clock className="w-4 h-4 text-primary" />
          <span>{t.shiftDuration}: <strong className="text-primary">{calcDuration(values.startTime, values.endTime)}</strong></span>
        </div>
      )}

      <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
        <label className="text-sm font-medium">{t.workingDays}</label>
        <div className={`flex flex-wrap gap-2 ${isRTL ? "flex-row-reverse" : ""}`}>
          {ALL_DAYS.map((day) => {
            const active = values.days.split(",").includes(day);
            return (
              <button key={day} type="button"
                onClick={() => toggleDay(day, values.days, (d) => onChange({ ...values, days: d }))}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${active ? "bg-primary text-primary-foreground border-primary" : "border-border text-muted-foreground hover:border-primary/50"}`}
              >
                {dayLabel(day)}
              </button>
            );
          })}
        </div>
      </div>

      <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
        <label className="text-sm font-medium">{t.shiftColor}</label>
        <div className={`flex gap-2.5 flex-wrap ${isRTL ? "flex-row-reverse" : ""}`}>
          {COLORS.map((c) => (
            <button key={c.id} type="button"
              onClick={() => onChange({ ...values, color: c.id })}
              className={`w-8 h-8 rounded-full border-2 transition-all hover:scale-110 ${values.color === c.id ? "border-foreground scale-110 shadow-md" : "border-transparent"}`}
              style={{ backgroundColor: c.hex }}
              title={c.id}
            />
          ))}
        </div>
      </div>

      <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
        <label className="text-sm font-medium">{t.shiftDescField}</label>
        <input value={values.description}
          onChange={(e) => onChange({ ...values, description: e.target.value })}
          dir={isRTL ? "rtl" : "ltr"}
          className="w-full px-3 py-2 border border-border rounded-lg outline-none focus:ring-2 focus:ring-primary/20 bg-background"
        />
      </div>
    </div>
  );

  const totalAssigned = shifts.reduce((s, sh) => s + sh.employees.length, 0);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isRTL ? "sm:flex-row-reverse" : ""}`}>
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">{t.shiftsTitle}</h1>
          <p className="text-muted-foreground mt-1">{t.manageShifts}</p>
        </div>
        <button
          onClick={() => { setForm(EMPTY_FORM); setIsAddOpen(true); }}
          className="flex items-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-xl font-medium shadow-sm hover:-translate-y-0.5 transition-all"
        >
          <Plus className="w-4 h-4" />
          {t.addShift}
        </button>
      </div>

      {/* Summary */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        {[
          { label: t.totalShifts, value: shifts.length, color: "text-foreground", bg: "bg-muted/30" },
          { label: t.assignedEmps, value: totalAssigned, color: "text-primary", bg: "bg-primary/5" },
          { label: t.unassignedEmps, value: unassignedEmployees.length, color: "text-amber-600", bg: "bg-amber-50 dark:bg-amber-950/30" },
        ].map((c) => (
          <div key={c.label} className={`${c.bg} rounded-xl p-4 border border-border`}>
            <p className="text-xs text-muted-foreground font-medium">{c.label}</p>
            <p className={`text-2xl font-bold mt-1 ${c.color}`}>{c.value}</p>
          </div>
        ))}
      </div>

      {/* Shifts Grid */}
      {isLoading ? (
        <div className="py-16 text-center text-muted-foreground">{t.loading}</div>
      ) : shifts.length === 0 ? (
        <div className="py-16 text-center text-muted-foreground bg-card border border-border rounded-2xl">{t.noShifts}</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {shifts.map((shift) => {
            const color = COLOR_MAP[shift.color] ?? "#6366f1";
            const activeDays = shift.days.split(",");
            return (
              <div key={shift.id} className="bg-card rounded-2xl border border-border shadow-sm overflow-hidden hover:shadow-md transition-all group">
                {/* Color bar */}
                <div className="h-1.5" style={{ backgroundColor: color }} />

                <div className="p-5">
                  {/* Title row */}
                  <div className={`flex items-start justify-between mb-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                    <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                      <div className="p-2 rounded-xl" style={{ backgroundColor: color + "20" }}>
                        <Clock className="w-5 h-5" style={{ color }} />
                      </div>
                      <div className={isRTL ? "text-right" : ""}>
                        <h3 className="text-base font-bold text-foreground">{shift.name}</h3>
                        {shift.description && <p className="text-xs text-muted-foreground">{shift.description}</p>}
                      </div>
                    </div>
                    <div className={`flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity ${isRTL ? "flex-row-reverse" : ""}`}>
                      <button onClick={() => openEdit(shift)}
                        className="p-1.5 rounded-lg text-muted-foreground hover:text-primary hover:bg-primary/10 transition-all">
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button onClick={() => setDeleteId(shift.id)}
                        className="p-1.5 rounded-lg text-muted-foreground hover:text-red-500 hover:bg-red-50 transition-all">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </div>

                  {/* Time badge */}
                  <div className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-xl text-sm font-semibold mb-4 ${isRTL ? "flex-row-reverse" : ""}`}
                    style={{ backgroundColor: color + "15", color }}>
                    <span>{formatTime(shift.startTime)}</span>
                    <span className="opacity-60">–</span>
                    <span>{formatTime(shift.endTime)}</span>
                    <span className="text-xs opacity-70">({calcDuration(shift.startTime, shift.endTime)})</span>
                  </div>

                  {/* Days */}
                  <div className={`flex flex-wrap gap-1 mb-4 ${isRTL ? "flex-row-reverse" : ""}`}>
                    {ALL_DAYS.map((day) => (
                      <span key={day}
                        className={`px-2 py-0.5 rounded-md text-xs font-semibold ${activeDays.includes(day) ? "text-white" : "bg-muted text-muted-foreground"}`}
                        style={activeDays.includes(day) ? { backgroundColor: color } : {}}>
                        {dayLabel(day)}
                      </span>
                    ))}
                  </div>

                  {/* Employees footer */}
                  <div className={`flex items-center justify-between border-t border-border pt-4 ${isRTL ? "flex-row-reverse" : ""}`}>
                    <div className={`flex items-center gap-2 ${isRTL ? "flex-row-reverse" : ""}`}>
                      {shift.employees.length > 0 ? (
                        <>
                          <div className={`flex ${isRTL ? "-space-x-reverse" : ""} -space-x-2`}>
                            {shift.employees.slice(0, 5).map((emp) => (
                              <div key={emp.id}
                                className="w-7 h-7 rounded-full border-2 border-card flex items-center justify-center text-xs font-bold text-white flex-shrink-0"
                                style={{ backgroundColor: color }}
                                title={`${emp.firstName} ${emp.lastName}`}>
                                {initials(emp.firstName, emp.lastName)}
                              </div>
                            ))}
                            {shift.employees.length > 5 && (
                              <div className="w-7 h-7 rounded-full border-2 border-card bg-muted flex items-center justify-center text-xs font-bold text-muted-foreground">
                                +{shift.employees.length - 5}
                              </div>
                            )}
                          </div>
                          <span className="text-xs text-muted-foreground">{shift.employees.length} {t.empCountInShift}</span>
                        </>
                      ) : (
                        <span className="text-xs text-muted-foreground italic">{t.noEmpsInShift}</span>
                      )}
                    </div>
                    <button onClick={() => setManageShift(shift)}
                      className="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-border hover:border-primary hover:text-primary transition-all">
                      <Users className="w-3.5 h-3.5" />
                      {t.manageShiftEmps}
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Unassigned employees panel */}
      {unassignedEmployees.length > 0 && shifts.length > 0 && (
        <div className="bg-card rounded-2xl border border-amber-200 dark:border-amber-800/60 shadow-sm p-5">
          <div className={`flex items-center gap-2 mb-4 ${isRTL ? "flex-row-reverse" : ""}`}>
            <div className="p-1.5 bg-amber-100 rounded-lg">
              <Users className="w-4 h-4 text-amber-600" />
            </div>
            <h3 className="font-semibold text-foreground">{t.unassignedEmps} ({unassignedEmployees.length})</h3>
          </div>
          <div className={`flex flex-wrap gap-2 ${isRTL ? "flex-row-reverse" : ""}`}>
            {unassignedEmployees.map((emp) => (
              <div key={emp.id} className={`flex items-center gap-2 bg-muted/50 rounded-xl px-3 py-2 border border-border ${isRTL ? "flex-row-reverse" : ""}`}>
                <div className="w-7 h-7 rounded-full bg-amber-400 flex items-center justify-center text-xs font-bold text-white flex-shrink-0">
                  {(emp.firstName?.[0] ?? "") + (emp.lastName?.[0] ?? "")}
                </div>
                <div className={isRTL ? "text-right" : ""}>
                  <p className="text-sm font-medium leading-none">{emp.firstName} {emp.lastName}</p>
                  <p className="text-xs text-muted-foreground">{emp.position}</p>
                </div>
                <select
                  onChange={(e) => { if (e.target.value) { assignEmployee.mutate({ employeeId: emp.id, shiftId: parseInt(e.target.value) }); e.target.value = ""; } }}
                  className="text-xs border border-border rounded-lg px-2 py-1 bg-background outline-none ml-1"
                  defaultValue=""
                >
                  <option value="">{t.assignToShift} ▾</option>
                  {shifts.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── Add Shift Modal ── */}
      {isAddOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-card w-full max-w-lg rounded-2xl shadow-xl border border-border flex flex-col max-h-[90vh]">
            <div className={`p-6 border-b border-border bg-muted/10 flex items-center justify-between flex-shrink-0 ${isRTL ? "flex-row-reverse" : ""}`}>
              <h2 className="text-xl font-bold">{t.addShift}</h2>
              <button onClick={() => setIsAddOpen(false)} className="text-muted-foreground hover:text-foreground p-1 rounded-lg hover:bg-muted"><X className="w-5 h-5" /></button>
            </div>
            <form onSubmit={(e) => { e.preventDefault(); createShift.mutate(form); }} className="p-6 overflow-y-auto space-y-4">
              <ShiftFormFields values={form} onChange={setForm} />
              <div className={`pt-4 flex ${isRTL ? "flex-row-reverse" : ""} justify-end gap-3`}>
                <button type="button" onClick={() => setIsAddOpen(false)} className="px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg">{t.cancel}</button>
                <button type="submit" disabled={createShift.isPending || !form.days}
                  className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg shadow hover:bg-primary/90 disabled:opacity-50">
                  {createShift.isPending ? t.saving : t.createShift}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ── Edit Shift Modal ── */}
      {editShift && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-card w-full max-w-lg rounded-2xl shadow-xl border border-border flex flex-col max-h-[90vh]">
            <div className={`p-6 border-b border-border bg-muted/10 flex items-center justify-between flex-shrink-0 ${isRTL ? "flex-row-reverse" : ""}`}>
              <h2 className="text-xl font-bold">{t.editShift}</h2>
              <button onClick={() => setEditShift(null)} className="text-muted-foreground hover:text-foreground p-1 rounded-lg hover:bg-muted"><X className="w-5 h-5" /></button>
            </div>
            <form onSubmit={(e) => { e.preventDefault(); updateShift.mutate({ id: editShift.id, data: editForm }); }} className="p-6 overflow-y-auto space-y-4">
              <ShiftFormFields values={editForm} onChange={setEditForm} />
              <div className={`pt-4 flex ${isRTL ? "flex-row-reverse" : ""} justify-end gap-3`}>
                <button type="button" onClick={() => setEditShift(null)} className="px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg">{t.cancel}</button>
                <button type="submit" disabled={updateShift.isPending || !editForm.days}
                  className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg shadow hover:bg-primary/90 disabled:opacity-50">
                  {updateShift.isPending ? t.saving : t.saveChanges}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ── Manage Employees Modal ── */}
      {manageShift && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-card w-full max-w-lg rounded-2xl shadow-xl border border-border flex flex-col max-h-[85vh]">
            <div className={`p-5 border-b border-border flex items-center justify-between flex-shrink-0 ${isRTL ? "flex-row-reverse" : ""}`}>
              <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                <div className="w-3 h-8 rounded-full" style={{ backgroundColor: COLOR_MAP[manageShift.color] ?? "#6366f1" }} />
                <div className={isRTL ? "text-right" : ""}>
                  <h2 className="text-lg font-bold">{t.manageShiftEmps}</h2>
                  <p className="text-sm text-muted-foreground">{manageShift.name} · {formatTime(manageShift.startTime)} – {formatTime(manageShift.endTime)}</p>
                </div>
              </div>
              <button onClick={() => setManageShift(null)} className="text-muted-foreground hover:text-foreground p-1 rounded-lg hover:bg-muted"><X className="w-5 h-5" /></button>
            </div>

            <div className="overflow-y-auto flex-1 p-5 space-y-5">
              {/* Assigned */}
              {manageShift.employees.length > 0 && (
                <div>
                  <p className={`text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3 ${isRTL ? "text-right" : ""}`}>
                    {isRTL ? "في هذه الوردية" : "In this shift"} ({manageShift.employees.length})
                  </p>
                  <div className="space-y-2">
                    {manageShift.employees.map((emp) => (
                      <div key={emp.id} className={`flex items-center justify-between p-3 bg-primary/5 rounded-xl border border-primary/10 ${isRTL ? "flex-row-reverse" : ""}`}>
                        <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                          <div className="w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold text-white flex-shrink-0"
                            style={{ backgroundColor: COLOR_MAP[manageShift.color] ?? "#6366f1" }}>
                            {initials(emp.firstName, emp.lastName)}
                          </div>
                          <div className={isRTL ? "text-right" : ""}>
                            <p className="text-sm font-semibold">{emp.firstName} {emp.lastName}</p>
                            <p className="text-xs text-muted-foreground">{emp.position}</p>
                          </div>
                        </div>
                        <button
                          onClick={() => {
                            unassignEmployee.mutate(emp.id);
                            setManageShift((prev) => prev ? { ...prev, employees: prev.employees.filter((e) => e.id !== emp.id) } : null);
                          }}
                          className="text-xs text-red-500 hover:bg-red-50 border border-red-200 rounded-lg px-2.5 py-1 transition-all"
                        >
                          {t.removeFromShift}
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Add unassigned */}
              {unassignedEmployees.length > 0 && (
                <div>
                  <p className={`text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3 ${isRTL ? "text-right" : ""}`}>
                    {isRTL ? "إضافة موظفين" : "Add employees"} ({unassignedEmployees.length})
                  </p>
                  <div className="space-y-2">
                    {unassignedEmployees.map((emp) => (
                      <div key={emp.id} className={`flex items-center justify-between p-3 bg-muted/30 rounded-xl border border-border ${isRTL ? "flex-row-reverse" : ""}`}>
                        <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                          <div className="w-9 h-9 rounded-full bg-muted-foreground/20 flex items-center justify-center text-sm font-bold text-muted-foreground flex-shrink-0">
                            {(emp.firstName?.[0] ?? "") + (emp.lastName?.[0] ?? "")}
                          </div>
                          <div className={isRTL ? "text-right" : ""}>
                            <p className="text-sm font-semibold">{emp.firstName} {emp.lastName}</p>
                            <p className="text-xs text-muted-foreground">{emp.position}</p>
                          </div>
                        </div>
                        <button
                          onClick={() => {
                            assignEmployee.mutate({ employeeId: emp.id, shiftId: manageShift.id });
                            setManageShift((prev) =>
                              prev ? { ...prev, employees: [...prev.employees, { id: emp.id, firstName: emp.firstName, lastName: emp.lastName, position: emp.position ?? "", avatar: emp.avatar }] } : null
                            );
                          }}
                          className="text-xs text-primary hover:bg-primary/10 border border-primary/20 rounded-lg px-2.5 py-1 transition-all"
                        >
                          {t.assignToShift}
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {manageShift.employees.length === 0 && unassignedEmployees.length === 0 && (
                <p className="text-center text-muted-foreground py-8 text-sm">
                  {isRTL ? "جميع الموظفين معينون لورديات أخرى" : "All employees are assigned to other shifts"}
                </p>
              )}
            </div>

            <div className="p-4 border-t border-border flex-shrink-0">
              <button onClick={() => setManageShift(null)} className="w-full py-2 text-sm font-medium bg-muted text-foreground rounded-lg hover:bg-muted/80 transition-all">
                {t.cancel}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Delete Confirm ── */}
      {deleteId !== null && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-card w-full max-w-sm rounded-2xl shadow-xl border border-border p-6 space-y-4">
            <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
              <div className="p-2 bg-red-100 rounded-xl"><Trash2 className="w-5 h-5 text-red-600" /></div>
              <h3 className="text-lg font-bold">{t.deleteShift}</h3>
            </div>
            <p className="text-sm text-muted-foreground">{t.deleteConfirm}</p>
            <div className={`flex gap-3 ${isRTL ? "flex-row-reverse" : ""} justify-end`}>
              <button onClick={() => setDeleteId(null)} className="px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg">{t.cancel}</button>
              <button onClick={() => deleteShift.mutate(deleteId)} disabled={deleteShift.isPending}
                className="px-4 py-2 text-sm font-medium bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50">
                {deleteShift.isPending ? t.saving : t.deleteShift}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
