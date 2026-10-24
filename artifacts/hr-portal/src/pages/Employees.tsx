import { useState, useEffect } from "react";
import { useLocation, useSearch } from "wouter";
import {
  useListEmployees,
  useCreateEmployee,
  useUpdateEmployee,
  useDeleteEmployee,
  useUpdateApplication,
  getListEmployeesQueryKey,
  useListDepartments,
  type Employee,
} from "@workspace/api-client-react";
import { useQueryClient } from "@tanstack/react-query";
import {
  Plus,
  Search,
  Edit2,
  Trash2,
  Mail,
  Phone,
  FileText,
  KeyRound,
  Sparkles,
} from "lucide-react";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { useLang } from "@/contexts/LanguageContext";
import EmployeeDocuments from "./EmployeeDocuments";
import { EmployeeHub } from "@/components/EmployeeHub";
import { PositionInput, confirmNewTitle } from "@/components/Suggest";

const bad = (m: string): void => { toast.error(m); };

async function sendInvite(id: number, name: string, isRTL: boolean, email = false) {
  const r = await fetch(`/api/employees/${id}/invite`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(email ? { sendEmail: true } : {}) });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) return bad(d.error || "Could not create the code");
  try { await navigator.clipboard.writeText(d.code); } catch { /* ignore */ }
  const mailNote = !email ? "" : d.emailed
    ? (isRTL ? ` تم إرسال الدعوة إلى ${d.email}.` : ` Emailed to ${d.email}.`)
    : (isRTL ? " تعذر إرسال البريد، شارك الكود بدلاً من ذلك." : " The e-mail could not be sent, so share the code instead.");
  toast.success(
    isRTL ? `كود الدعوة لـ ${name}: ${d.code}` : `Invite code for ${name}: ${d.code}`,
    { description: (isRTL ? `صالح ${d.expiresInDays} أيام — تم نسخه. يدخله الموظف في التطبيق مع بريده.` : `Valid for ${d.expiresInDays} days — copied. The employee enters it in the app with their email.`) + mailNote, duration: 60000 },
  );
}

export default function Employees() {
  const queryClient = useQueryClient();
  const [, navigate] = useLocation();
  const search = useSearch();
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [editingEmployee, setEditingEmployee] = useState<Employee | null>(null);
  const [selectedEmployeeForDocs, setSelectedEmployeeForDocs] =
    useState<Employee | null>(null);
  const [hubEmployee, setHubEmployee] = useState<Employee | null>(null);
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedDeptId, setSelectedDeptId] = useState<number | null>(null);
  const [prefill, setPrefill] = useState<Record<string, string> | null>(null);
  const [addDept, setAddDept] = useState<string>("");
  const [addPos, setAddPos] = useState<string>("");
  const [editDept, setEditDept] = useState<string>("");
  const [editPos, setEditPos] = useState<string>("");
  const { t, isRTL } = useLang();

  useEffect(() => {
    const p = new URLSearchParams(search);
    if (p.get("from") === "talent" && p.get("appId")) {
      setPrefill({
        firstName: p.get("firstName") ?? "",
        lastName: p.get("lastName") ?? "",
        email: p.get("email") ?? "",
        phone: p.get("phone") ?? "",
        position: p.get("position") ?? "",
        departmentId: p.get("departmentId") ?? "",
        appId: p.get("appId") ?? "",
      });
      setIsAddOpen(true);
    }
  }, [search]);

  const { data: employees = [], isLoading } = useListEmployees();
  const { data: departments = [] } = useListDepartments();

  const handleMutationError = (err: any) => {
    if (err?.status === 401) { navigate("/login"); return; }
    const msg: string = err?.data?.error || err?.message || "";
    const isEmailConflict = err?.status === 409 || msg.toLowerCase().includes("email") || msg.toLowerCase().includes("unique");
    alert(isRTL
      ? isEmailConflict ? "البريد الإلكتروني مستخدم بالفعل لموظف آخر" : `فشل الحفظ: ${msg}`
      : isEmailConflict ? "This email is already used by another employee" : `Save failed: ${msg}`
    );
  };

  const updateApplicationMutation = useUpdateApplication();

  const createMutation = useCreateEmployee({
    mutation: {
      onSuccess: (newEmployee) => {
        queryClient.invalidateQueries({ queryKey: getListEmployeesQueryKey() });
        setIsAddOpen(false);
        const code = (newEmployee as any)?.inviteCode;
        if (code) {
          toast.success(
            isRTL ? `تم إنشاء الموظف. كود الدعوة: ${code}` : `Employee created. Invite code: ${code}`,
            { description: isRTL ? "أعطِ الكود للموظف ليدخله في التطبيق مع بريده (صالح 7 أيام)." : "Give this code to the employee; they enter it in the app with their email (valid 7 days).", duration: 120000 },
          );
        }
        if (prefill?.appId) {
          updateApplicationMutation.mutate({
            id: parseInt(prefill.appId),
            data: { status: "hired" },
          });
          setPrefill(null);
          navigate("/employees");
        }
        setSelectedEmployeeForDocs(newEmployee);
      },
      onError: handleMutationError,
    },
  });

  const deleteMutation = useDeleteEmployee({
    mutation: {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: getListEmployeesQueryKey() });
      },
    },
  });

  const updateMutation = useUpdateEmployee({
    mutation: {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: getListEmployeesQueryKey() });
        setEditingEmployee(null);
      },
      onError: handleMutationError,
    },
  });

  const deptNameOf = (id: string) => departments.find((d) => String(d.id) === String(id))?.name ?? "";
  const titlesIn = (id: string) => employees.filter((x) => String(x.departmentId) === String(id)).map((x) => x.position ?? "").filter(Boolean);

  useEffect(() => { setAddPos(prefill?.position ?? ""); setAddDept(prefill?.departmentId ?? ""); }, [prefill, isAddOpen]);
  useEffect(() => { setEditPos(editingEmployee?.position ?? ""); setEditDept(String(editingEmployee?.departmentId ?? "")); }, [editingEmployee]);

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    if (!confirmNewTitle(String(formData.get("position") ?? ""), deptNameOf(String(formData.get("departmentId") ?? "")), isRTL, titlesIn(String(formData.get("departmentId") ?? "")))) return;
    createMutation.mutate({
      data: {
        firstName: formData.get("firstName") as string,
        lastName: formData.get("lastName") as string,
        email: formData.get("email") as string,
        phone: formData.get("phone") as string,
        position: formData.get("position") as string,
        departmentId: Number(formData.get("departmentId")),
        status: formData.get("status") as string,
        startDate: formData.get("startDate") as string,
        salary: formData.get("salary") ? Number(formData.get("salary")) : undefined,
      },
    });
  };

  const handleEditSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!editingEmployee) return;
    const formData = new FormData(e.currentTarget);
    if (!confirmNewTitle(String(formData.get("position") ?? ""), deptNameOf(String(formData.get("departmentId") ?? "")), isRTL, titlesIn(String(formData.get("departmentId") ?? "")))) return;
    updateMutation.mutate({
      id: editingEmployee.id,
      data: {
        firstName: formData.get("firstName") as string,
        lastName: formData.get("lastName") as string,
        email: formData.get("email") as string,
        phone: formData.get("phone") as string,
        position: formData.get("position") as string,
        departmentId: Number(formData.get("departmentId")),
        status: formData.get("status") as string,
        startDate: formData.get("startDate") as string,
        salary: formData.get("salary") ? Number(formData.get("salary")) : undefined,
      },
    });
  };

  const filteredEmployees = employees.filter(
    (e) =>
      (!selectedDeptId || e.departmentId === selectedDeptId) &&
      ((e.firstName + " " + e.lastName)
        .toLowerCase()
        .includes(searchTerm.toLowerCase()) ||
        e.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
        e.position.toLowerCase().includes(searchTerm.toLowerCase())),
  );

  const getDeptEmployeeCount = (deptId: number) =>
    employees.filter((e) => e.departmentId === deptId).length;

  const statusLabel = (s: string) => {
    if (s === "active") return t.active;
    if (s === "on_leave") return t.on_leave;
    return t.inactive;
  };

  return (
    <div className="space-y-6">
      <div
        className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isRTL ? "sm:flex-row-reverse" : ""}`}
      >
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">
            {t.employeesTitle}
          </h1>
          <p className="text-muted-foreground mt-1">{t.manageTeam}</p>
        </div>
        <button
          onClick={() => setIsAddOpen(true)}
          className="flex items-center justify-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-xl font-medium shadow-sm hover:shadow-md hover:-translate-y-0.5 transition-all"
          data-testid="button-add-employee"
        >
          <Plus className="w-4 h-4" /> {t.addEmployee}
        </button>
      </div>

      <div className="flex gap-2 overflow-x-auto pb-2">
        <button
          onClick={() => setSelectedDeptId(null)}
          className={`shrink-0 px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
            selectedDeptId === null
              ? "bg-primary text-primary-foreground"
              : "bg-muted text-muted-foreground hover:bg-muted/80"
          }`}
        >
          {t.all} ({employees.length})
        </button>
        {departments.map((dept) => {
          const count = getDeptEmployeeCount(dept.id);
          return (
            <button
              key={dept.id}
              onClick={() => setSelectedDeptId(dept.id)}
              className={`shrink-0 px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
                selectedDeptId === dept.id
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-muted-foreground hover:bg-muted/80"
              }`}
            >
              {dept.name} ({count})
            </button>
          );
        })}
      </div>

      <div className="bg-card rounded-2xl border border-border shadow-sm overflow-hidden">
        <div
          className={`p-4 border-b border-border/50 flex items-center justify-between bg-muted/10 ${isRTL ? "flex-row-reverse" : ""}`}
        >
          <div className="relative w-full max-w-sm">
            <Search
              className={`absolute ${isRTL ? "right-3" : "left-3"} top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground`}
            />
            <input
              type="text"
              placeholder={t.searchEmployees}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className={`w-full ${isRTL ? "pr-9 pl-4 text-right" : "pl-9 pr-4"} py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all`}
            />
          </div>
          <div className="text-sm text-muted-foreground font-medium whitespace-nowrap">
            {filteredEmployees.length} {t.total}
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr
                className={`border-b border-border bg-muted/30 ${isRTL ? "text-right" : ""}`}
              >
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  {t.employee}
                </th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  {t.contact}
                </th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  {t.department}
                </th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  {t.status}
                </th>
                <th
                  className={`px-6 py-4 ${isRTL ? "text-left" : "text-right"} text-xs font-semibold text-muted-foreground uppercase tracking-wider`}
                >
                  {t.actions}
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {isLoading ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-8 text-center text-muted-foreground"
                  >
                    {t.loadingEmployees}
                  </td>
                </tr>
              ) : filteredEmployees.length === 0 ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-12 text-center text-muted-foreground"
                  >
                    {t.noEmployeesFound}
                  </td>
                </tr>
              ) : (
                filteredEmployees.map((employee, i) => (
                  <motion.tr
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: i * 0.05 }}
                    key={employee.id}
                    className={`hover:bg-muted/30 transition-colors group ${isRTL ? "text-right" : ""}`}
                  >
                    <td className="px-6 py-4">
                      <div
                        className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}
                      >
                        <div className="h-10 w-10 rounded-full bg-gradient-to-br from-primary/20 to-primary/10 text-primary font-bold flex items-center justify-center shrink-0 border border-primary/20">
                          {employee.firstName[0]}
                          {employee.lastName[0]}
                        </div>
                        <div>
                          <p className="font-semibold text-foreground">
                            {employee.firstName} {employee.lastName}
                          </p>
                          <p className="text-xs text-muted-foreground mt-0.5">
                            {employee.position}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="space-y-1">
                        <div
                          className={`flex items-center text-sm text-foreground ${isRTL ? "flex-row-reverse" : ""}`}
                        >
                          <Mail
                            className={`w-3.5 h-3.5 ${isRTL ? "ml-2" : "mr-2"} text-muted-foreground`}
                          />{" "}
                          {employee.email}
                        </div>
                        {employee.phone && (
                          <div
                            className={`flex items-center text-xs text-muted-foreground ${isRTL ? "flex-row-reverse" : ""}`}
                          >
                            <Phone
                              className={`w-3.5 h-3.5 ${isRTL ? "ml-2" : "mr-2"}`}
                            />{" "}
                            {employee.phone}
                          </div>
                        )}
                      </div>
                    </td>
                    <td className="px-6 py-4 text-sm text-foreground">
                      <span className="inline-flex items-center px-2.5 py-1 rounded-md bg-secondary text-secondary-foreground border border-secondary-border">
                        {employee.departmentName || t.unassigned}
                      </span>
                    </td>
                    <td className="px-6 py-4">
                      <span
                        className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium border ${
                          employee.status === "active"
                            ? "bg-emerald-50 text-emerald-700 border-emerald-200"
                            : employee.status === "on_leave"
                              ? "bg-amber-50 text-amber-700 border-amber-200"
                              : "bg-red-50 text-red-700 border-red-200"
                        }`}
                      >
                        <span
                          className={`w-1.5 h-1.5 rounded-full ${isRTL ? "ml-1.5" : "mr-1.5"} ${
                            employee.status === "active"
                              ? "bg-emerald-500"
                              : employee.status === "on_leave"
                                ? "bg-amber-500"
                                : "bg-red-500"
                          }`}
                        ></span>
                        {statusLabel(employee.status)}
                      </span>
                    </td>
                    <td
                      className={`px-6 py-4 ${isRTL ? "text-left" : "text-right"}`}
                    >
                      <div
                        className={`flex items-center ${isRTL ? "justify-start" : "justify-end"} gap-2 opacity-0 group-hover:opacity-100 transition-opacity`}
                      >
                        <button
                          onClick={() => {
                            setSelectedEmployeeForDocs(employee);
                          }}
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                          title={t.papers}
                        >
                          <FileText className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => setHubEmployee(employee)}
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                          title={isRTL ? "المسار الوظيفي والمكافآت" : "Career, rewards & more"}
                        >
                          <Sparkles className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => setHubEmployee(employee)}
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                          title={isRTL ? "المسار الوظيفي والمكافآت" : "Career, rewards & more"}
                        >
                          <Sparkles className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => sendInvite(employee.id, `${employee.firstName} ${employee.lastName}`, isRTL)}
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                          title={isRTL ? "كود الدعوة" : "Invite code"}
                        >
                          <KeyRound className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => sendInvite(employee.id, `${employee.firstName} ${employee.lastName}`, isRTL, true)}
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                          title={isRTL ? "إرسال الدعوة بالبريد" : "E-mail the invitation"}
                        >
                          <Mail className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => setEditingEmployee(employee)}
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                        >
                          <Edit2 className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => {
                            if (confirm(t.deleteConfirm)) {
                              deleteMutation.mutate({ id: employee.id });
                            }
                          }}
                          className="p-1.5 text-muted-foreground hover:text-destructive rounded-md hover:bg-destructive/10 transition-colors"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </td>
                  </motion.tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {isAddOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="bg-card w-full max-w-2xl rounded-2xl shadow-xl overflow-hidden border border-border flex flex-col max-h-[90vh]"
          >
            <div
              className={`p-6 border-b border-border bg-muted/10 shrink-0 ${isRTL ? "text-right" : ""}`}
            >
              <h2 className="text-xl font-bold">{t.addNewEmployee}</h2>
              <p className="text-sm text-muted-foreground mt-1">
                {t.enterDetails}
              </p>
              {prefill && (
                <div className={`mt-3 flex items-center gap-2 px-3 py-2 bg-emerald-50 border border-emerald-200 rounded-lg text-sm text-emerald-700 ${isRTL ? "flex-row-reverse" : ""}`}>
                  <span className="font-medium">
                    {isRTL ? "تم نقل البيانات من بنك المواهب — أكمل المعلومات الناقصة" : "Pre-filled from Talent Pool — complete the missing info"}
                  </span>
                </div>
              )}
            </div>

            <form
              key={prefill?.appId ?? "new"}
              onSubmit={handleSubmit}
              className="flex-1 overflow-y-auto p-6 space-y-6"
            >
              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.firstName}
                  </label>
                  <input
                    required
                    name="firstName"
                    defaultValue={prefill?.firstName ?? ""}
                    dir={isRTL ? "rtl" : "ltr"}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.lastName}
                  </label>
                  <input
                    required
                    name="lastName"
                    defaultValue={prefill?.lastName ?? ""}
                    dir={isRTL ? "rtl" : "ltr"}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.email}
                  </label>
                  <input
                    required
                    type="email"
                    name="email"
                    defaultValue={prefill?.email ?? ""}
                    dir="ltr"
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.phone}
                  </label>
                  <input
                    name="phone"
                    defaultValue={prefill?.phone ?? ""}
                    dir="ltr"
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.position}
                  </label>
                  <PositionInput required name="position" value={addPos} onChange={setAddPos} deptName={deptNameOf(addDept)} existing={titlesIn(addDept)} />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.department}
                  </label>
                  <select
                    required
                    name="departmentId"
                    defaultValue={prefill?.departmentId ?? ""}
                    onChange={(e) => setAddDept(e.target.value)}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none bg-background"
                  >
                    <option value="">{t.selectDepartment}</option>
                    {departments.map((d) => (
                      <option key={d.id} value={d.id}>
                        {d.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.startDate}
                  </label>
                  <input
                    required
                    type="date"
                    name="startDate"
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.salary}
                  </label>
                  <input
                    type="number"
                    name="salary"
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.status}
                  </label>
                  <select
                    required
                    name="status"
                    defaultValue="active"
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none bg-background"
                  >
                    <option value="active">{t.active}</option>
                    <option value="inactive">{t.inactive}</option>
                    <option value="on_leave">{t.on_leave}</option>
                  </select>
                </div>
              </div>

              <div
                className={`pt-4 flex ${isRTL ? "flex-row-reverse" : ""} justify-end gap-3 border-t border-border shrink-0`}
              >
                <button
                  type="button"
                  onClick={() => { setIsAddOpen(false); setPrefill(null); if (prefill) navigate("/employees"); }}
                  className="px-4 py-2 text-sm font-medium text-muted-foreground hover:text-foreground hover:bg-muted rounded-lg transition-colors"
                >
                  {t.cancel}
                </button>
                <button
                  type="submit"
                  disabled={createMutation.isPending}
                  className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg shadow hover:bg-primary/90 transition-colors disabled:opacity-50"
                >
                  {createMutation.isPending ? t.saving : t.save}
                </button>
              </div>
            </form>
          </motion.div>
        </div>
      )}

      {editingEmployee && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="bg-card w-full max-w-2xl rounded-2xl shadow-xl overflow-hidden border border-border flex flex-col max-h-[90vh]"
          >
            <div
              className={`p-6 border-b border-border bg-muted/10 shrink-0 ${isRTL ? "text-right" : ""}`}
            >
              <h2 className="text-xl font-bold">{t.editEmployee}</h2>
              <p className="text-sm text-muted-foreground mt-1">
                {t.updateEmployeeDetails}
              </p>
            </div>

            <form
              onSubmit={handleEditSubmit}
              className="flex-1 overflow-y-auto p-6 space-y-6"
            >
              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.firstName}
                  </label>
                  <input
                    required
                    name="firstName"
                    defaultValue={editingEmployee.firstName}
                    dir={isRTL ? "rtl" : "ltr"}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.lastName}
                  </label>
                  <input
                    required
                    name="lastName"
                    defaultValue={editingEmployee.lastName}
                    dir={isRTL ? "rtl" : "ltr"}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.email}
                  </label>
                  <input
                    required
                    type="email"
                    name="email"
                    defaultValue={editingEmployee.email}
                    dir="ltr"
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.phone}
                  </label>
                  <input
                    name="phone"
                    defaultValue={editingEmployee.phone ?? ""}
                    dir="ltr"
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.position}
                  </label>
                  <PositionInput required name="position" value={editPos} onChange={setEditPos} deptName={deptNameOf(editDept)} existing={titlesIn(editDept)} />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.department}
                  </label>
                  <select
                    required
                    name="departmentId"
                    defaultValue={editingEmployee.departmentId}
                    onChange={(e) => setEditDept(e.target.value)}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none bg-background"
                  >
                    <option value="">{t.selectDepartment}</option>
                    {departments.map((d) => (
                      <option key={d.id} value={d.id}>
                        {d.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.startDate}
                  </label>
                  <input
                    required
                    type="date"
                    name="startDate"
                    defaultValue={editingEmployee.startDate}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.salary}
                  </label>
                  <input
                    type="number"
                    name="salary"
                    defaultValue={editingEmployee.salary ?? ""}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.status}
                  </label>
                  <select
                    required
                    name="status"
                    defaultValue={editingEmployee.status}
                    className="w-full px-3 py-2 border border-border rounded-lg focus:ring-2 focus:ring-primary/20 focus:border-primary outline-none bg-background"
                  >
                    <option value="active">{t.active}</option>
                    <option value="inactive">{t.inactive}</option>
                    <option value="on_leave">{t.on_leave}</option>
                  </select>
                </div>
              </div>

              <div
                className={`pt-4 flex ${isRTL ? "flex-row-reverse" : ""} justify-end gap-3 border-t border-border shrink-0`}
              >
                <button
                  type="button"
                  onClick={() => setEditingEmployee(null)}
                  className="px-4 py-2 text-sm font-medium text-muted-foreground hover:text-foreground hover:bg-muted rounded-lg transition-colors"
                >
                  {t.cancel}
                </button>
                <button
                  type="submit"
                  disabled={updateMutation.isPending}
                  className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg shadow hover:bg-primary/90 transition-colors disabled:opacity-50"
                >
                  {updateMutation.isPending ? t.saving : t.save}
                </button>
              </div>
            </form>
          </motion.div>
        </div>
      )}

      {hubEmployee && <EmployeeHub employee={hubEmployee as any} onClose={() => { setHubEmployee(null); queryClient.invalidateQueries({ queryKey: getListEmployeesQueryKey() }); }} />}

      {selectedEmployeeForDocs && (
        <EmployeeDocuments
          employee={selectedEmployeeForDocs}
          onClose={() => setSelectedEmployeeForDocs(null)}
        />
      )}
    </div>
  );
}
