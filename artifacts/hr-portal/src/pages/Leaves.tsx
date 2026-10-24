import { useState } from "react";
import {
  useListLeaves,
  useUpdateLeave,
  useCreateLeave,
  getListLeavesQueryKey,
  useListEmployees,
} from "@workspace/api-client-react";
import { useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, XCircle, Plus, Calendar, BarChart2 } from "lucide-react";
import { format } from "date-fns";
import { useLang } from "@/contexts/LanguageContext";
import { useLocation } from "wouter";
import { toast } from "sonner";
import { api } from "@/lib/http";

export default function Leaves() {
  const queryClient = useQueryClient();
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [filter, setFilter] = useState("all");
  const { t, isRTL } = useLang();
  const [, navigate] = useLocation();

  const { data: leaves = [], isLoading } = useListLeaves();
  const { data: employees = [] } = useListEmployees();

  const updateMutation = useUpdateLeave({
    mutation: {
      onSuccess: () =>
        queryClient.invalidateQueries({ queryKey: getListLeavesQueryKey() }),
    },
  });

  const createMutation = useCreateLeave({
    mutation: {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: getListLeavesQueryKey() });
        setIsAddOpen(false);
      },
    },
  });

  const handleStatusUpdate = async (id: number, status: "approved" | "rejected") => {
    const leave = leaves.find((l) => l.id === id) as any;
    if (leave?.headStatus === "pending") {
      // two-step approvals: the team head has not decided yet; HR may go past him only with a written reason
      const note = window.prompt(isRTL ? "رئيس الفريق لم يقرر بعد. اكتب سبب القرار دونه:" : "The team head has not decided yet. Write the reason for deciding without him:", "");
      if (note === null) return;
      if (note.trim().length < 3) { toast.error(isRTL ? "اكتب السبب أولاً" : "Write the reason first"); return; }
      try {
        await api(`/leaves/${id}`, "PUT", { status, reviewNote: note, skipHead: true });
        queryClient.invalidateQueries({ queryKey: getListLeavesQueryKey() });
      } catch (e) { toast.error((e as Error).message); }
      return;
    }
    updateMutation.mutate({ id, data: { status } });
  };

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    createMutation.mutate({
      data: {
        employeeId: Number(formData.get("employeeId")),
        type: formData.get("type") as string,
        startDate: formData.get("startDate") as string,
        endDate: formData.get("endDate") as string,
        reason: formData.get("reason") as string,
      },
    });
  };

  const filteredLeaves = leaves.filter((l) =>
    filter === "all" ? true : l.status === filter,
  );

  const filters = [
    { key: "all", label: t.all },
    { key: "pending", label: t.pending },
    { key: "approved", label: t.approved },
    { key: "rejected", label: t.rejected },
  ];

  return (
    <div className="space-y-6">
      <div
        className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isRTL ? "sm:flex-row-reverse" : ""}`}
      >
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">
            {t.leaveManagement}
          </h1>
          <p className="text-muted-foreground mt-1">{t.reviewManage}</p>
        </div>
        <div className={`flex gap-2 ${isRTL ? "flex-row-reverse" : ""}`}>
          <button
            onClick={() => navigate("/leaves/analytics")}
            className="flex items-center gap-2 px-4 py-2.5 bg-secondary text-secondary-foreground rounded-xl font-medium shadow-sm hover:-translate-y-0.5 transition-all border border-border"
          >
            <BarChart2 className="w-4 h-4" />
            {t.leaveAnalytics}
          </button>
          <button
            onClick={() => setIsAddOpen(true)}
            className="flex items-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-xl font-medium shadow-sm hover:-translate-y-0.5 transition-all"
          >
            <Plus className="w-4 h-4" /> {t.requestLeave}
          </button>
        </div>
      </div>

      <div className="bg-card rounded-2xl border border-border shadow-sm overflow-hidden">
        <div
          className={`p-4 border-b border-border bg-muted/10 flex gap-2 ${isRTL ? "flex-row-reverse" : ""}`}
        >
          {filters.map((f) => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                filter === f.key
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-muted"
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr
                className={`border-b border-border bg-muted/30 ${isRTL ? "text-right" : ""}`}
              >
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  {t.employee}
                </th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  {t.leaveDetails}
                </th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  {t.datesDuration}
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
                  <td colSpan={5} className="p-8 text-center">
                    {t.loading}
                  </td>
                </tr>
              ) : filteredLeaves.length === 0 ? (
                <tr>
                  <td
                    colSpan={5}
                    className={`p-12 text-center text-muted-foreground`}
                  >
                    {t.noLeaves}
                  </td>
                </tr>
              ) : (
                filteredLeaves.map((leave) => (
                  <tr
                    key={leave.id}
                    className={`hover:bg-muted/30 transition-colors ${isRTL ? "text-right" : ""}`}
                  >
                    <td className="px-6 py-4 font-medium text-foreground">
                      {leave.employeeName}
                    </td>
                    <td className="px-6 py-4">
                      <span className="inline-block px-2 py-1 bg-secondary text-secondary-foreground text-xs rounded-md font-medium mb-1">
                        {leave.type}
                      </span>
                      {leave.reason && (
                        <p className="text-xs text-muted-foreground line-clamp-1">
                          {leave.reason}
                        </p>
                      )}
                    </td>
                    <td className="px-6 py-4">
                      <div
                        className={`flex items-center text-sm text-foreground ${isRTL ? "flex-row-reverse" : ""}`}
                      >
                        <Calendar
                          className={`w-3.5 h-3.5 ${isRTL ? "ml-2" : "mr-2"} text-muted-foreground`}
                        />
                        {format(new Date(leave.startDate), "MMM d, yyyy")} -{" "}
                        {format(new Date(leave.endDate), "MMM d, yyyy")}
                      </div>
                      <p className="text-xs text-muted-foreground mt-1">
                        {leave.days} {t.daysRequested}
                      </p>
                    </td>
                    <td className="px-6 py-4">
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
                      {leave.status === "pending" && (leave as any).headStatus && (
                        <p className={`text-xs mt-1 font-medium ${(leave as any).headStatus === "pending" ? "text-amber-700" : "text-sky-700"}`}>
                          {(leave as any).headStatus === "pending"
                            ? (isRTL ? "عند رئيس الفريق" : "Waiting for the team head")
                            : (isRTL ? "وافق الرئيس — قرارك النهائي" : "Head approved. Your decision.")}
                        </p>
                      )}
                    </td>
                    <td
                      className={`px-6 py-4 ${isRTL ? "text-left" : "text-right"}`}
                    >
                      {leave.status === "pending" ? (
                        <div
                          className={`flex items-center ${isRTL ? "justify-start" : "justify-end"} gap-2`}
                        >
                          <button
                            onClick={() =>
                              handleStatusUpdate(leave.id, "approved")
                            }
                            className="p-1.5 text-emerald-600 bg-emerald-50 hover:bg-emerald-100 rounded-md transition-colors"
                            title={t.approved}
                          >
                            <CheckCircle2 className="w-5 h-5" />
                          </button>
                          <button
                            onClick={() =>
                              handleStatusUpdate(leave.id, "rejected")
                            }
                            className="p-1.5 text-red-600 bg-red-50 hover:bg-red-100 rounded-md transition-colors"
                            title={t.rejected}
                          >
                            <XCircle className="w-5 h-5" />
                          </button>
                        </div>
                      ) : (
                        <span className="text-xs text-muted-foreground">
                          {t.processed}
                        </span>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {isAddOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-card w-full max-w-md rounded-2xl shadow-xl overflow-hidden border border-border">
            <div
              className={`p-6 border-b border-border bg-muted/10 ${isRTL ? "text-right" : ""}`}
            >
              <h2 className="text-xl font-bold">{t.newLeaveRequest}</h2>
            </div>
            <form onSubmit={handleSubmit} className="p-6 space-y-4">
              <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                <label className="text-sm font-medium text-foreground">
                  {t.employee}
                </label>
                <select
                  required
                  name="employeeId"
                  className="w-full px-3 py-2 border border-border rounded-lg bg-background"
                >
                  <option value="">{t.selectEmployee}</option>
                  {employees.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.firstName} {e.lastName}
                    </option>
                  ))}
                </select>
              </div>
              <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                <label className="text-sm font-medium text-foreground">
                  {t.leaveType}
                </label>
                <select
                  required
                  name="type"
                  className="w-full px-3 py-2 border border-border rounded-lg bg-background"
                >
                  <option value="annual">{t.annual}</option>
                  <option value="sick">{t.sick}</option>
                  <option value="unpaid">{t.unpaid}</option>
                  <option value="maternity">{t.maternity}</option>
                  <option value="paternity">{t.paternity}</option>
                  <option value="other">{t.other}</option>
                </select>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.startDate}
                  </label>
                  <input
                    required
                    type="date"
                    name="startDate"
                    className="w-full px-3 py-2 border border-border rounded-lg"
                  />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium text-foreground">
                    {t.endDate}
                  </label>
                  <input
                    required
                    type="date"
                    name="endDate"
                    className="w-full px-3 py-2 border border-border rounded-lg"
                  />
                </div>
              </div>
              <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                <label className="text-sm font-medium text-foreground">
                  {t.reasonOptional}
                </label>
                <textarea
                  name="reason"
                  rows={2}
                  className="w-full px-3 py-2 border border-border rounded-lg resize-none"
                />
              </div>
              <div
                className={`pt-4 flex ${isRTL ? "flex-row-reverse" : ""} justify-end gap-3`}
              >
                <button
                  type="button"
                  onClick={() => setIsAddOpen(false)}
                  className="px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg"
                >
                  {t.cancel}
                </button>
                <button
                  type="submit"
                  disabled={createMutation.isPending}
                  className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg shadow hover:bg-primary/90 disabled:opacity-50"
                >
                  {createMutation.isPending ? t.saving : t.submitRequest}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
