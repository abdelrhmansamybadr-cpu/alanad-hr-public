import { useState } from "react";
import {
  useLeaveAnalytics,
  useEmployeeLeaveDetail,
  useLeavePolicy,
  useUpdateLeavePolicy,
  useListDepartments,
  EmployeeLeaveAnalytics,
  EmployeeLeaveDetail,
} from "@workspace/api-client-react";
import { useQuery } from "@tanstack/react-query";
import { customFetch } from "@workspace/api-client-react";
import { useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";
import {
  ArrowLeft,
  Search,
  Download,
  Printer,
  BarChart2,
  X,
  Settings,
  ChevronRight,
  Calendar,
  Users,
  TrendingDown,
  Clock,
} from "lucide-react";
import { format } from "date-fns";
import { toast } from "sonner";

const AVATAR_COLORS = [
  "bg-blue-500",
  "bg-emerald-500",
  "bg-amber-500",
  "bg-amber-500",
  "bg-rose-500",
  "bg-cyan-500",
  "bg-cyan-500",
  "bg-orange-500",
];

function getAvatarColor(name: string): string {
  const code = name
    .split("")
    .reduce((acc, char) => acc + char.charCodeAt(0), 0);
  return AVATAR_COLORS[code % AVATAR_COLORS.length];
}

interface Department {
  id: number;
  name: string;
}

export default function LeaveAnalytics() {
  const queryClient = useQueryClient();
  const { t, isRTL } = useLang();
  const { user } = useAuth();

  const [search, setSearch] = useState("");
  const [deptFilter, setDeptFilter] = useState<number | null>(null);
  const [selectedEmpId, setSelectedEmpId] = useState<number | null>(null);
  const [showPolicy, setShowPolicy] = useState(false);
  const [policyForm, setPolicyForm] = useState({
    daysPerMonth: 2,
    daysPerYear: 21,
  });

  const { data: analytics = [], isLoading, isError } = useLeaveAnalytics();
  const { data: detail, isLoading: detailLoading } =
    useEmployeeLeaveDetail(selectedEmpId);
  const { data: policy } = useLeavePolicy();
  const updatePolicy = useUpdateLeavePolicy();
  const { data: departments = [] } = useListDepartments() as {
    data: Department[];
  };

  const isAdmin = user?.role === "hr_admin";

  const filtered = analytics.filter((emp) => {
    const matchSearch =
      !search ||
      `${emp.firstName} ${emp.lastName}`
        .toLowerCase()
        .includes(search.toLowerCase());
    const matchDept = !deptFilter || emp.departmentId === deptFilter;
    return matchSearch && matchDept;
  });

  const handlePolicySave = async () => {
    try {
      await updatePolicy.mutateAsync(policyForm);
      queryClient.invalidateQueries({ queryKey: ["/api/leaves/policy"] });
      toast.success(t.policyUpdated);
      setShowPolicy(false);
    } catch {
      toast.error(t.serverError);
    }
  };

  const exportCsv = (emp: EmployeeLeaveDetail) => {
    const header = "Employee,Leave Type,Start Date,End Date,Days,Status,Reason";
    const rows = emp.history.map((l) =>
      [
        emp.employee.firstName,
        l.type,
        l.startDate,
        l.endDate,
        l.days,
        l.status,
        l.reason || "",
      ].join(","),
    );
    const csv = [header, ...rows].join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `leave-report-${emp.employee.firstName}-${emp.employee.lastName}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const printReport = (emp: EmployeeLeaveDetail) => {
    const printWindow = window.open("", "_blank");
    if (!printWindow) return;

    const html = `
<!DOCTYPE html>
<html dir="${isRTL ? "rtl" : "ltr"}">
<head>
  <meta charset="UTF-8">
  <title>${t.leaveReport} - ${emp.employee.firstName} ${emp.employee.lastName}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; padding: 20px; }
    h1 { font-size: 24px; margin-bottom: 8px; }
    h2 { font-size: 18px; margin: 20px 0 10px; }
    table { width: 100%; border-collapse: collapse; margin-top: 10px; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: ${isRTL ? "right" : "left"}; }
    th { background: #f5f5f5; }
    .summary { display: flex; gap: 20px; margin: 20px 0; }
    .summary-item { padding: 10px; background: #f9f9f9; border-radius: 4px; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
    .badge-approved { background: #dcfce7; color: #166534; }
    .badge-pending { background: #fef3c7; color: #92400e; }
    .badge-rejected { background: #fee2e2; color: #991b1b; }
    @media print { body { padding: 0; } }
  </style>
</head>
<body>
  <h1>${t.leaveReport}</h1>
  <p>${emp.employee.firstName} ${emp.employee.lastName} - ${emp.employee.position}</p>
  
  <div class="summary">
    <div class="summary-item">
      <strong>${t.takenThisWeek}:</strong> ${emp.summary.takenThisWeek}
    </div>
    <div class="summary-item">
      <strong>${t.takenThisMonth}:</strong> ${emp.summary.takenThisMonth} / ${emp.policy.daysPerMonth}
    </div>
    <div class="summary-item">
      <strong>${t.takenThisYear}:</strong> ${emp.summary.takenThisYear} / ${emp.policy.daysPerYear}
    </div>
    <div class="summary-item">
      <strong>${t.pendingRequests}:</strong> ${emp.summary.pendingRequests}
    </div>
  </div>
  
  <h2>${t.leaveHistory}</h2>
  <table>
    <thead>
      <tr>
        <th>${t.datesDuration}</th>
        <th>${t.leaveType}</th>
        <th>${t.daysRequested}</th>
        <th>${t.status}</th>
        <th>${t.reason}</th>
      </tr>
    </thead>
    <tbody>
      ${emp.history
        .map(
          (l) => `
        <tr>
          <td>${format(new Date(l.startDate), "MMM d, yyyy")} - ${format(new Date(l.endDate), "MMM d, yyyy")}</td>
          <td>${l.type}</td>
          <td>${l.days}</td>
          <td><span class="badge badge-${l.status}">${l.status}</span></td>
          <td>${l.reason || "-"}</td>
        </tr>
      `,
        )
        .join("")}
    </tbody>
  </table>
</body>
</html>`;

    printWindow.document.write(html);
    printWindow.document.close();
    printWindow.print();
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div
        className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isRTL ? "sm:flex-row-reverse" : ""}`}
      >
        <div className={isRTL ? "text-right" : ""}>
          <div
            className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}
          >
            <button
              onClick={() => window.history.back()}
              className="p-2 hover:bg-muted rounded-lg transition-colors"
            >
              <ArrowLeft className="w-5 h-5" />
            </button>
            <h1 className="text-3xl font-bold text-foreground tracking-tight">
              {t.employeeLeaveOverview}
            </h1>
          </div>
          <p className="text-muted-foreground mt-1">{t.leaveAnalyticsDesc}</p>
        </div>

        {isAdmin && (
          <button
            onClick={() => {
              if (policy) {
                setPolicyForm({
                  daysPerMonth: policy.daysPerMonth,
                  daysPerYear: policy.daysPerYear,
                });
              }
              setShowPolicy(!showPolicy);
            }}
            className={`flex items-center gap-2 px-4 py-2.5 bg-secondary text-secondary-foreground rounded-xl font-medium shadow-sm hover:-translate-y-0.5 transition-all border border-border ${isRTL ? "flex-row-reverse" : ""}`}
          >
            <Settings className="w-4 h-4" />
            {t.leavePolicy}
          </button>
        )}
      </div>

      {/* Policy Panel */}
      {showPolicy && (
        <div className="bg-card rounded-2xl border border-border shadow-sm p-6">
          <h3 className="text-lg font-semibold mb-4">{t.leavePolicy}</h3>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="text-sm font-medium text-foreground">
                {t.daysPerMonth}
              </label>
              <input
                type="number"
                value={policyForm.daysPerMonth}
                onChange={(e) =>
                  setPolicyForm({
                    ...policyForm,
                    daysPerMonth: parseInt(e.target.value) || 0,
                  })
                }
                className="w-full px-3 py-2 border border-border rounded-lg mt-1"
              />
            </div>
            <div>
              <label className="text-sm font-medium text-foreground">
                {t.daysPerYear}
              </label>
              <input
                type="number"
                value={policyForm.daysPerYear}
                onChange={(e) =>
                  setPolicyForm({
                    ...policyForm,
                    daysPerYear: parseInt(e.target.value) || 0,
                  })
                }
                className="w-full px-3 py-2 border border-border rounded-lg mt-1"
              />
            </div>
          </div>
          <button
            onClick={handlePolicySave}
            disabled={updatePolicy.isPending}
            className="mt-4 px-4 py-2 bg-primary text-primary-foreground rounded-lg font-medium shadow hover:bg-primary/90 disabled:opacity-50"
          >
            {updatePolicy.isPending ? t.saving : t.savePolicy}
          </button>
        </div>
      )}

      {/* Search + Filter Bar */}
      <div
        className={`flex flex-col sm:flex-row gap-4 ${isRTL ? "sm:flex-row-reverse" : ""}`}
      >
        <div className="relative flex-1">
          <Search
            className={`absolute top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground ${isRTL ? "right-3" : "left-3"}`}
          />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t.searchEmployees}
            className={`w-full px-4 py-2.5 pl-10 border border-border rounded-xl bg-background ${isRTL ? "text-right pr-10 pl-4" : ""}`}
          />
        </div>
        <select
          value={deptFilter || ""}
          onChange={(e) =>
            setDeptFilter(e.target.value ? parseInt(e.target.value) : null)
          }
          className="px-4 py-2.5 border border-border rounded-xl bg-background"
        >
          <option value="">{t.allDepartments2}</option>
          {departments.map((d: Department) => (
            <option key={d.id} value={d.id}>
              {d.name}
            </option>
          ))}
        </select>
        <span className="flex items-center text-muted-foreground px-4 py-2.5">
          {filtered.length} / {analytics.length}
        </span>
      </div>

      {/* Employee Cards Grid */}
      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3, 4, 5, 6].map((i) => (
            <div
              key={i}
              className="bg-card rounded-2xl border border-border shadow-sm p-6 animate-pulse"
            >
              <div className="flex items-center gap-4 mb-4">
                <div className="w-12 h-12 rounded-full bg-muted" />
                <div className="flex-1">
                  <div className="h-4 bg-muted rounded w-24 mb-2" />
                  <div className="h-3 bg-muted rounded w-16" />
                </div>
              </div>
              <div className="h-3 bg-muted rounded w-full mb-2" />
              <div className="h-3 bg-muted rounded w-2/3" />
            </div>
          ))}
        </div>
      ) : isError ? (
        <div className="bg-card rounded-2xl border border-border shadow-sm p-6 text-center text-red-500">
          {t.serverError}
        </div>
      ) : filtered.length === 0 ? (
        <div className="bg-card rounded-2xl border border-border shadow-sm p-12 text-center">
          <Users className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
          <p className="text-muted-foreground">{t.noEmployeesFound}</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((emp: EmployeeLeaveAnalytics) => {
            const monthlyPercent = policy
              ? (emp.takenThisMonth / policy.daysPerMonth) * 100
              : 0;
            const monthlyColor =
              monthlyPercent < 70
                ? "bg-emerald-500"
                : monthlyPercent < 100
                  ? "bg-amber-500"
                  : "bg-red-500";

            return (
              <div
                key={emp.employeeId}
                onClick={() => setSelectedEmpId(emp.employeeId)}
                className="bg-card rounded-2xl border border-border shadow-sm p-6 cursor-pointer hover:-translate-y-0.5 transition-all"
              >
                <div
                  className={`flex items-center gap-4 mb-4 ${isRTL ? "flex-row-reverse" : ""}`}
                >
                  <div
                    className={`w-12 h-12 rounded-full ${getAvatarColor(emp.firstName)} flex items-center justify-center text-white font-bold`}
                  >
                    {emp.firstName[0]}
                    {emp.lastName[0]}
                  </div>
                  <div className={isRTL ? "text-right" : ""}>
                    <h3 className="font-semibold text-foreground">
                      {emp.firstName} {emp.lastName}
                    </h3>
                    <p className="text-sm text-muted-foreground">
                      {emp.position}
                    </p>
                  </div>
                </div>

                <span
                  className={`inline-block px-2 py-1 text-xs rounded-md font-medium mb-4 ${
                    emp.status === "active"
                      ? "bg-emerald-50 text-emerald-700"
                      : emp.status === "on_leave"
                        ? "bg-amber-50 text-amber-700"
                        : "bg-muted text-muted-foreground"
                  }`}
                >
                  {emp.status === "active"
                    ? t.active
                    : emp.status === "on_leave"
                      ? t.on_leave
                      : t.inactive}
                </span>

                <div
                  className={`grid grid-cols-3 gap-2 mb-4 text-center ${isRTL ? "text-right" : ""}`}
                >
                  <div>
                    <p className="text-xs text-muted-foreground">
                      {t.thisMonth}
                    </p>
                    <p className="font-semibold">
                      {emp.takenThisMonth}/{policy?.daysPerMonth || 2}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">
                      {t.thisYear}
                    </p>
                    <p className="font-semibold">
                      {emp.takenThisYear}/{policy?.daysPerYear || 21}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">
                      {t.pendingRequests}
                    </p>
                    <p className="font-semibold">{emp.pendingRequests}</p>
                  </div>
                </div>

                <div className="mb-3">
                  <div
                    className={`h-2 rounded-full ${monthlyColor} transition-all`}
                    style={{ width: `${Math.min(monthlyPercent, 100)}%` }}
                  />
                </div>

                <div
                  className={`flex justify-between text-sm ${isRTL ? "flex-row-reverse" : ""}`}
                >
                  <span className="text-muted-foreground">{t.remaining}:</span>
                  <span className="font-medium">
                    {emp.remainingThisMonth} {t.thisMonth.toLowerCase()}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Detail Modal */}
      {selectedEmpId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-card w-full max-w-4xl max-h-[90vh] rounded-2xl shadow-xl overflow-hidden border border-border">
            <div
              className={`p-6 border-b border-border bg-muted/10 flex items-center justify-between ${isRTL ? "flex-row-reverse" : ""}`}
            >
              <div className={isRTL ? "text-right" : ""}>
                <h2 className="text-xl font-bold">
                  {detail?.employee.firstName} {detail?.employee.lastName}
                </h2>
                <p className="text-muted-foreground">
                  {detail?.employee.position}
                </p>
              </div>
              <div
                className={`flex items-center gap-2 ${isRTL ? "flex-row-reverse" : ""}`}
              >
                <button
                  onClick={() => detail && exportCsv(detail)}
                  className="p-2 hover:bg-muted rounded-lg transition-colors"
                  title={t.exportCsv}
                >
                  <Download className="w-5 h-5" />
                </button>
                <button
                  onClick={() => detail && printReport(detail)}
                  className="p-2 hover:bg-muted rounded-lg transition-colors"
                  title={t.printReport}
                >
                  <Printer className="w-5 h-5" />
                </button>
                <button
                  onClick={() => setSelectedEmpId(null)}
                  className="p-2 hover:bg-muted rounded-lg transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            <div className="p-6 overflow-y-auto max-h-[calc(90vh-140px)]">
              {detailLoading ? (
                <div className="flex items-center justify-center p-12">
                  <div className="animate-spin w-8 h-8 border-4 border-primary border-t-transparent rounded-full" />
                </div>
              ) : detail ? (
                <>
                  {/* Summary Cards */}
                  <div
                    className={`grid grid-cols-4 gap-4 mb-6 ${isRTL ? "flex-row-reverse" : ""}`}
                  >
                    <div className="bg-muted/30 rounded-xl p-4 text-center">
                      <Clock className="w-5 h-5 mx-auto mb-2 text-muted-foreground" />
                      <p className="text-2xl font-bold">
                        {detail.summary.takenThisWeek}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {t.takenThisWeek}
                      </p>
                    </div>
                    <div className="bg-muted/30 rounded-xl p-4 text-center">
                      <Calendar className="w-5 h-5 mx-auto mb-2 text-muted-foreground" />
                      <p className="text-2xl font-bold">
                        {detail.summary.takenThisMonth}/
                        {detail.policy.daysPerMonth}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {t.takenThisMonth}
                      </p>
                    </div>
                    <div className="bg-muted/30 rounded-xl p-4 text-center">
                      <TrendingDown className="w-5 h-5 mx-auto mb-2 text-muted-foreground" />
                      <p className="text-2xl font-bold">
                        {detail.summary.takenThisYear}/
                        {detail.policy.daysPerYear}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {t.takenThisYear}
                      </p>
                    </div>
                    <div className="bg-muted/30 rounded-xl p-4 text-center">
                      <Users className="w-5 h-5 mx-auto mb-2 text-muted-foreground" />
                      <p className="text-2xl font-bold">
                        {detail.summary.pendingRequests}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {t.pendingRequests}
                      </p>
                    </div>
                  </div>

                  {/* Progress Bars */}
                  <div
                    className={`mb-6 space-y-4 ${isRTL ? "text-right" : ""}`}
                  >
                    <div>
                      <div
                        className={`flex justify-between mb-1 ${isRTL ? "flex-row-reverse" : ""}`}
                      >
                        <span className="text-sm">{t.takenThisMonth}</span>
                        <span className="text-sm text-muted-foreground">
                          {detail.summary.takenThisMonth}/
                          {detail.policy.daysPerMonth} ({t.remaining}:{" "}
                          {detail.summary.remainingThisMonth})
                        </span>
                      </div>
                      <div className="h-2 bg-muted rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full transition-all ${
                            detail.summary.takenThisMonth >=
                            detail.policy.daysPerMonth
                              ? "bg-red-500"
                              : detail.summary.takenThisMonth >=
                                  detail.policy.daysPerMonth * 0.7
                                ? "bg-amber-500"
                                : "bg-emerald-500"
                          }`}
                          style={{
                            width: `${(detail.summary.takenThisMonth / detail.policy.daysPerMonth) * 100}%`,
                          }}
                        />
                      </div>
                    </div>
                    <div>
                      <div
                        className={`flex justify-between mb-1 ${isRTL ? "flex-row-reverse" : ""}`}
                      >
                        <span className="text-sm">{t.takenThisYear}</span>
                        <span className="text-sm text-muted-foreground">
                          {detail.summary.takenThisYear}/
                          {detail.policy.daysPerYear} ({t.remaining}:{" "}
                          {detail.summary.remainingThisYear})
                        </span>
                      </div>
                      <div className="h-2 bg-muted rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full transition-all ${
                            detail.summary.takenThisYear >=
                            detail.policy.daysPerYear
                              ? "bg-red-500"
                              : detail.summary.takenThisYear >=
                                  detail.policy.daysPerYear * 0.7
                                ? "bg-amber-500"
                                : "bg-emerald-500"
                          }`}
                          style={{
                            width: `${(detail.summary.takenThisYear / detail.policy.daysPerYear) * 100}%`,
                          }}
                        />
                      </div>
                    </div>
                  </div>

                  {/* Leave History Table */}
                  <h3 className="text-lg font-semibold mb-4">
                    {t.leaveHistory}
                  </h3>
                  {detail.history.length === 0 ? (
                    <p className="text-muted-foreground text-center py-8">
                      {t.noLeaves}
                    </p>
                  ) : (
                    <div className="overflow-x-auto">
                      <table className="w-full text-left">
                        <thead>
                          <tr
                            className={`border-b border-border bg-muted/30 ${isRTL ? "text-right" : ""}`}
                          >
                            <th className="px-4 py-3 text-xs font-semibold text-muted-foreground uppercase">
                              {t.datesDuration}
                            </th>
                            <th className="px-4 py-3 text-xs font-semibold text-muted-foreground uppercase">
                              {t.leaveType}
                            </th>
                            <th className="px-4 py-3 text-xs font-semibold text-muted-foreground uppercase">
                              {t.daysRequested}
                            </th>
                            <th className="px-4 py-3 text-xs font-semibold text-muted-foreground uppercase">
                              {t.status}
                            </th>
                            <th className="px-4 py-3 text-xs font-semibold text-muted-foreground uppercase">
                              {t.reason}
                            </th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-border">
                          {detail.history.map((leave) => (
                            <tr
                              key={leave.id}
                              className={`hover:bg-muted/30 ${isRTL ? "text-right" : ""}`}
                            >
                              <td className="px-4 py-3">
                                {format(
                                  new Date(leave.startDate),
                                  "MMM d, yyyy",
                                )}{" "}
                                -{" "}
                                {format(new Date(leave.endDate), "MMM d, yyyy")}
                              </td>
                              <td className="px-4 py-3">
                                {t[
                                  `leaveType_${leave.type}` as keyof typeof t
                                ] || leave.type}
                              </td>
                              <td className="px-4 py-3">{leave.days}</td>
                              <td className="px-4 py-3">
                                <span
                                  className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium capitalize border ${
                                    leave.status === "approved"
                                      ? "bg-emerald-50 text-emerald-700 border-emerald-200"
                                      : leave.status === "pending"
                                        ? "bg-amber-50 text-amber-700 border-amber-200"
                                        : "bg-red-50 text-red-700 border-red-200"
                                  }`}
                                >
                                  {leave.status === "approved"
                                    ? t.approved
                                    : leave.status === "pending"
                                      ? t.pending
                                      : t.rejected}
                                </span>
                              </td>
                              <td className="px-4 py-3 text-muted-foreground">
                                {leave.reason || "-"}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                </>
              ) : null}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
