import { useState } from "react";
import {
  useLocation,
  useRoute,
  useLocation as useWouterLocation,
} from "wouter";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import {
  useListDepartments,
  useListJobs,
  customFetch,
} from "@workspace/api-client-react";
import { motion, AnimatePresence } from "framer-motion";
import { useLang } from "@/contexts/LanguageContext";
import { toast } from "sonner";
import {
  Search,
  ChevronRight,
  ChevronLeft,
  Mail,
  Phone,
  Plus,
  X,
  Trash2,
  Edit,
  Eye,
  Upload,
  Download,
  FileText,
  Building2,
  Users,
  ArrowLeft,
} from "lucide-react";

interface DepartmentWithCount {
  id: number;
  name: string;
  description: string | null;
  waitingCount: number;
  managerName: string | null;
  employeeCount: number;
}

interface CandidateWithDetails {
  id: number;
  applicantName: string;
  email: string;
  phone: string | null;
  resumeUrl: string | null;
  coverLetter: string | null;
  notes: string | null;
  status: string;
  appliedAt: string;
  jobId: number | null;
  jobTitle: string;
  departmentId: number;
  departmentName: string;
  documents: {
    id: number;
    fileName: string;
    filePath: string;
    mimeType: string;
    uploadedAt: string;
  }[];
}

function useTalentBankDepartments() {
  return useQuery<DepartmentWithCount[]>({
    queryKey: ["/api/talent-pool/talent-bank/departments"],
    queryFn: async () => {
      return customFetch<DepartmentWithCount[]>(
        "/api/talent-pool/talent-bank/departments",
        {
          method: "GET",
        },
      );
    },
  });
}

function useDepartmentCandidates(departmentId: number) {
  return useQuery<CandidateWithDetails[]>({
    queryKey: ["/api/talent-pool/talent-bank/department", departmentId],
    queryFn: async () => {
      return customFetch<CandidateWithDetails[]>(
        `/api/talent-pool/talent-bank/department/${departmentId}`,
        {
          method: "GET",
        },
      );
    },
    enabled: departmentId > 0,
  });
}

function useCreateCandidate() {
  return useMutation({
    mutationFn: async (data: {
      applicantName: string;
      email: string;
      phone?: string;
      departmentId: number;
      jobTitle?: string;
      notes?: string;
      coverLetter?: string;
    }) => {
      return customFetch("/api/talent-pool/talent-bank/candidates", {
        method: "POST",
        body: JSON.stringify(data),
        headers: { "Content-Type": "application/json" },
      });
    },
  });
}

function useUpdateCandidate() {
  return useMutation({
    mutationFn: async ({
      id,
      data,
    }: {
      id: number;
      data: { status?: string; notes?: string };
    }) => {
      return customFetch(`/api/talent-pool/talent-bank/candidates/${id}`, {
        method: "PUT",
        body: JSON.stringify(data),
        headers: { "Content-Type": "application/json" },
      });
    },
  });
}

function useDeleteCandidate() {
  return useMutation({
    mutationFn: async (id: number) => {
      return customFetch(`/api/talent-pool/talent-bank/candidates/${id}`, {
        method: "DELETE",
      });
    },
  });
}

function DepartmentCard({
  department,
  onClick,
}: {
  department: DepartmentWithCount;
  onClick: () => void;
}) {
  const { t, isRTL } = useLang();

  return (
    <motion.div
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="bg-card rounded-2xl border border-border p-6 cursor-pointer hover:border-primary/30 hover:shadow-lg transition-all"
    >
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <div className="flex items-center gap-3 mb-3">
            <div className="bg-primary/10 p-2.5 rounded-xl">
              <Building2 className="w-5 h-5 text-primary" />
            </div>
            <h3 className="text-lg font-semibold text-foreground">
              {department.name}
            </h3>
          </div>
          {department.description && (
            <p className="text-sm text-muted-foreground mb-4 line-clamp-2">
              {department.description}
            </p>
          )}
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <Users className="w-4 h-4 text-muted-foreground" />
              <span className="text-sm text-muted-foreground">
                {department.employeeCount} {t.employees2}
              </span>
            </div>
          </div>
        </div>
        <div className="flex flex-col items-end gap-2">
          <div
            className={`px-4 py-2 rounded-xl text-center min-w-[80px] ${
              department.waitingCount > 0
                ? "bg-amber-100 text-amber-700"
                : "bg-muted text-muted-foreground"
            }`}
          >
            <span className="text-2xl font-bold">
              {department.waitingCount}
            </span>
            <p className="text-xs mt-1">
              {department.waitingCount === 1
                ? t.personsWaiting
                : t.waitingPersons}
            </p>
          </div>
          <div
            className={`p-2 rounded-lg ${
              isRTL ? "rotate-180" : ""
            } text-muted-foreground hover:text-primary hover:bg-primary/10`}
          >
            <ChevronRight className="w-5 h-5" />
          </div>
        </div>
      </div>
    </motion.div>
  );
}

function PersonCard({
  candidate,
  onView,
  onEdit,
  onDelete,
}: {
  candidate: CandidateWithDetails;
  onView: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const { t, isRTL } = useLang();

  const getStatusBadge = (status: string) => {
    const colors: Record<string, string> = {
      new: "bg-blue-50 text-blue-700 border-blue-200",
      screening: "bg-amber-50 text-amber-700 border-amber-200",
      interview: "bg-amber-50 text-amber-700 border-amber-200",
      offer: "bg-cyan-50 text-cyan-700 border-cyan-200",
      hired: "bg-emerald-50 text-emerald-700 border-emerald-200",
      rejected: "bg-red-50 text-red-700 border-red-200",
      waiting: "bg-cyan-50 text-cyan-700 border-cyan-200",
    };
    const labels: Record<string, string> = {
      new: t.newStatus,
      screening: t.screening,
      interview: t.interview,
      offer: t.offer,
      hired: t.hired,
      rejected: t.rejectedStatus,
      waiting: t.waitingPersons,
    };
    return (
      <span
        className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border ${colors[status] || colors.new}`}
      >
        {labels[status] || status}
      </span>
    );
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-card rounded-xl border border-border p-4"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-2">
            <h3 className="font-semibold truncate">
              {candidate.applicantName}
            </h3>
            {getStatusBadge(candidate.status)}
          </div>
          <div
            className={`flex items-center gap-4 text-sm text-muted-foreground ${
              isRTL ? "flex-row-reverse" : ""
            }`}
          >
            <span className="flex items-center gap-1">
              <Mail className="w-3.5 h-3.5" />
              {candidate.email}
            </span>
            {candidate.phone && (
              <span className="flex items-center gap-1">
                <Phone className="w-3.5 h-3.5" />
                {candidate.phone}
              </span>
            )}
          </div>
          <div
            className={`flex items-center gap-2 mt-2 text-sm ${isRTL ? "flex-row-reverse" : ""}`}
          >
            <span className="bg-secondary text-secondary-foreground px-2 py-0.5 rounded text-xs">
              {candidate.jobTitle}
            </span>
            <span className="text-muted-foreground text-xs">
              {candidate.departmentName}
            </span>
          </div>
          <p className="text-xs text-muted-foreground mt-2">
            {t.addedOn}: {candidate.appliedAt}
          </p>
          {candidate.notes && (
            <p className="text-sm text-muted-foreground mt-2 line-clamp-2">
              {candidate.notes}
            </p>
          )}
        </div>
        <div
          className={`flex flex-wrap gap-1 ${isRTL ? "flex-row-reverse" : ""}`}
        >
          <button
            onClick={onView}
            className="p-2 text-muted-foreground hover:text-primary hover:bg-primary/10 rounded-lg"
            title={t.viewCandidate}
          >
            <Eye className="w-4 h-4" />
          </button>
          <button
            onClick={onEdit}
            className="p-2 text-muted-foreground hover:text-amber-600 hover:bg-amber-50 rounded-lg"
            title={t.editPerson}
          >
            <Edit className="w-4 h-4" />
          </button>
          <button
            onClick={onDelete}
            className="p-2 text-muted-foreground hover:text-destructive hover:bg-destructive/10 rounded-lg"
            title={t.deletePerson}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      </div>
    </motion.div>
  );
}

function AddPersonForm({
  departmentId,
  onClose,
  onSuccess,
}: {
  departmentId: number;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const { t, isRTL } = useLang();
  const { data: departments = [] } = useListDepartments();
  const createMutation = useCreateCandidate();
  const [selectedDeptId, setSelectedDeptId] = useState<number>(departmentId);
  const [formData, setFormData] = useState({
    applicantName: "",
    email: "",
    phone: "",
    jobTitle: "",
    notes: "",
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const validateForm = () => {
    const newErrors: Record<string, string> = {};
    if (!formData.applicantName.trim()) {
      newErrors.applicantName =
        t.personName + " " + (isRTL ? "مطلوب" : "is required");
    }
    if (!formData.email.trim()) {
      newErrors.email = t.email + " " + (isRTL ? "مطلوب" : "is required");
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = isRTL
        ? "البريد الإلكتروني غير صحيح"
        : "Invalid email format";
    }
    if (!selectedDeptId) {
      newErrors.department = isRTL ? "القسم مطلوب" : "Department is required";
    }
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;
    try {
      await createMutation.mutateAsync({
        applicantName: formData.applicantName,
        email: formData.email,
        phone: formData.phone || undefined,
        departmentId: selectedDeptId,
        jobTitle: formData.jobTitle || undefined,
        notes: formData.notes || undefined,
      });
      toast.success(t.personSaved);
      onSuccess();
    } catch (error) {
      console.error("Error creating candidate:", error);
      toast.error(t.serverError);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-lg rounded-2xl shadow-xl overflow-hidden border border-border max-h-[90vh] flex flex-col"
      >
        <div className="p-6 border-b border-border flex items-center justify-between shrink-0">
          <h2 className="text-xl font-bold">{t.addPersonTitle}</h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form
          onSubmit={handleSubmit}
          className="flex-1 overflow-y-auto p-6 space-y-4"
        >
          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.personSelectDepartment} *
            </label>
            <select
              required
              value={selectedDeptId}
              onChange={(e) => setSelectedDeptId(parseInt(e.target.value))}
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            >
              <option value="">{t.selectDepartment}</option>
              {departments.map((dept) => (
                <option key={dept.id} value={dept.id}>
                  {dept.name}
                </option>
              ))}
            </select>
            {errors.department && (
              <p className="text-xs text-destructive mt-1">{errors.department}</p>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.personName} *
            </label>
            <input
              type="text"
              required
              value={formData.applicantName}
              onChange={(e) =>
                setFormData({ ...formData, applicantName: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
            {errors.applicantName && (
              <p className="text-xs text-destructive mt-1">
                {errors.applicantName}
              </p>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.email} *
            </label>
            <input
              type="email"
              required
              value={formData.email}
              onChange={(e) =>
                setFormData({ ...formData, email: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
            {errors.email && (
              <p className="text-xs text-destructive mt-1">{errors.email}</p>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.phone}
            </label>
            <input
              type="tel"
              value={formData.phone}
              onChange={(e) =>
                setFormData({ ...formData, phone: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.personJobTitle}
            </label>
            <input
              type="text"
              value={formData.jobTitle}
              onChange={(e) =>
                setFormData({ ...formData, jobTitle: e.target.value })
              }
              placeholder={isRTL ? "مثال: مهندس برمجيات" : "e.g. Software Engineer"}
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.additionalNotes}
            </label>
            <textarea
              value={formData.notes}
              onChange={(e) =>
                setFormData({ ...formData, notes: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm min-h-[100px] focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          <div className={`flex gap-3 pt-4 ${isRTL ? "flex-row-reverse" : ""}`}>
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg"
            >
              {t.cancel}
            </button>
            <button
              type="submit"
              disabled={createMutation.isPending}
              className="flex-1 px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 disabled:opacity-50"
            >
              {createMutation.isPending ? t.savingPerson : t.savePerson}
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}

function EditPersonForm({
  candidate,
  onClose,
  onSuccess,
}: {
  candidate: CandidateWithDetails;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const { t, isRTL } = useLang();
  const { data: jobs = [] } = useListJobs();
  const { data: departments = [] } = useListDepartments();
  const updateMutation = useUpdateCandidate();
  const [formData, setFormData] = useState({
    applicantName: candidate.applicantName,
    email: candidate.email,
    phone: candidate.phone || "",
    notes: candidate.notes || "",
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const validateForm = () => {
    const newErrors: Record<string, string> = {};
    if (!formData.applicantName.trim()) {
      newErrors.applicantName =
        t.personName + " " + (isRTL ? "مطلوب" : "is required");
    }
    if (!formData.email.trim()) {
      newErrors.email = t.email + " " + (isRTL ? "مطلوب" : "is required");
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = isRTL
        ? "البريد الإلكتروني غير صحيح"
        : "Invalid email format";
    }
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;
    try {
      await updateMutation.mutateAsync({
        id: candidate.id,
        data: {
          notes: formData.notes || undefined,
        },
      });
      toast.success(t.personSaved);
      onSuccess();
    } catch (error) {
      console.error("Error updating candidate:", error);
      toast.error(t.serverError);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-lg rounded-2xl shadow-xl overflow-hidden border border-border max-h-[90vh] flex flex-col"
      >
        <div className="p-6 border-b border-border flex items-center justify-between shrink-0">
          <h2 className="text-xl font-bold">{t.editPerson}</h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form
          onSubmit={handleSubmit}
          className="flex-1 overflow-y-auto p-6 space-y-4"
        >
          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.personName} *
            </label>
            <input
              type="text"
              required
              value={formData.applicantName}
              onChange={(e) =>
                setFormData({ ...formData, applicantName: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
            {errors.applicantName && (
              <p className="text-xs text-destructive mt-1">
                {errors.applicantName}
              </p>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.email} *
            </label>
            <input
              type="email"
              required
              value={formData.email}
              onChange={(e) =>
                setFormData({ ...formData, email: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
            {errors.email && (
              <p className="text-xs text-destructive mt-1">{errors.email}</p>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.phone}
            </label>
            <input
              type="tel"
              value={formData.phone}
              onChange={(e) =>
                setFormData({ ...formData, phone: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.jobPosition}
            </label>
            <p className="text-sm text-foreground mt-1">{candidate.jobTitle}</p>
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.personDepartment}
            </label>
            <p className="text-sm text-foreground mt-1">
              {candidate.departmentName}
            </p>
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.additionalNotes}
            </label>
            <textarea
              value={formData.notes}
              onChange={(e) =>
                setFormData({ ...formData, notes: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm min-h-[100px] focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          <div className={`flex gap-3 pt-4 ${isRTL ? "flex-row-reverse" : ""}`}>
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg"
            >
              {t.cancel}
            </button>
            <button
              type="submit"
              disabled={updateMutation.isPending}
              className="flex-1 px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 disabled:opacity-50"
            >
              {updateMutation.isPending ? t.savingPerson : t.savePerson}
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}

function PersonDetailModal({
  candidate,
  onClose,
  onEdit,
  onDelete,
}: {
  candidate: CandidateWithDetails;
  onClose: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const { t, isRTL } = useLang();
  const queryClient = useQueryClient();
  const [currentStatus, setCurrentStatus] = useState(candidate.status);
  const statusMutation = useUpdateCandidate();

  const getStatusBadge = (status: string) => {
    const colors: Record<string, string> = {
      new: "bg-blue-50 text-blue-700 border-blue-200",
      screening: "bg-amber-50 text-amber-700 border-amber-200",
      interview: "bg-amber-50 text-amber-700 border-amber-200",
      offer: "bg-cyan-50 text-cyan-700 border-cyan-200",
      hired: "bg-emerald-50 text-emerald-700 border-emerald-200",
      rejected: "bg-red-50 text-red-700 border-red-200",
      waiting: "bg-cyan-50 text-cyan-700 border-cyan-200",
    };
    const labels: Record<string, string> = {
      new: t.newStatus,
      screening: t.screening,
      interview: t.interview,
      offer: t.offer,
      hired: t.hired,
      rejected: t.rejectedStatus,
      waiting: t.waitingPersons,
    };
    return (
      <span
        className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border ${colors[status] || colors.new}`}
      >
        {labels[status] || status}
      </span>
    );
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-2xl rounded-2xl shadow-xl overflow-hidden border border-border max-h-[90vh] flex flex-col"
      >
        <div className="p-6 border-b border-border flex items-center justify-between shrink-0">
          <h2 className="text-xl font-bold">{candidate.applicantName}</h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          <div
            className={`grid grid-cols-2 gap-4 ${isRTL ? "text-right" : ""}`}
          >
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                {t.email}
              </label>
              <p className="text-foreground">{candidate.email}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                {t.phone}
              </label>
              <p className="text-foreground">{candidate.phone || "-"}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                {t.jobPosition}
              </label>
              <p className="text-foreground">{candidate.jobTitle}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                {t.personDepartment}
              </label>
              <p className="text-foreground">{candidate.departmentName}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                {t.status}
              </label>
              <select
                value={currentStatus}
                onChange={(e) => {
                  const newStatus = e.target.value;
                  setCurrentStatus(newStatus);
                  statusMutation
                    .mutateAsync({
                      id: candidate.id,
                      data: { status: newStatus },
                    })
                    .then(() => {
                      queryClient.invalidateQueries({
                        queryKey: [
                          "/api/talent-pool/talent-bank/department",
                          candidate.departmentId,
                        ],
                      });
                      toast.success(
                        isRTL ? "تم تحديث الحالة" : "Status updated",
                      );
                    })
                    .catch(() => {
                      setCurrentStatus(candidate.status);
                      toast.error(t.serverError);
                    });
                }}
                disabled={statusMutation.isPending}
                className="mt-1 px-2 py-1 border border-border rounded-lg text-sm bg-background focus:outline-none focus:ring-2 focus:ring-primary/20"
              >
                <option value="new">{t.newStatus}</option>
                <option value="screening">{t.screening}</option>
                <option value="interview">{t.interview}</option>
                <option value="offer">{t.offer}</option>
                <option value="hired">{t.hired}</option>
                <option value="rejected">{t.rejectedStatus}</option>
              </select>
            </div>
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                {t.addedOn}
              </label>
              <p className="text-foreground">{candidate.appliedAt}</p>
            </div>
          </div>

          {candidate.notes && (
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                {t.additionalNotes}
              </label>
              <p className="text-foreground mt-1">{candidate.notes}</p>
            </div>
          )}

          {candidate.resumeUrl && (
            <div>
              <label className="text-sm font-medium text-muted-foreground">
                Resume
              </label>
              <a
                href={candidate.resumeUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 text-primary hover:underline mt-1"
              >
                <FileText className="w-4 h-4" />
                {t.preview}
              </a>
            </div>
          )}
        </div>

        <div
          className={`p-4 border-t border-border flex justify-between shrink-0 ${isRTL ? "flex-row-reverse" : ""}`}
        >
          <button
            onClick={onDelete}
            className="px-4 py-2 text-sm font-medium text-destructive hover:bg-destructive/10 rounded-lg"
          >
            {t.deletePerson}
          </button>
          <button
            onClick={onEdit}
            className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg hover:bg-primary/90"
          >
            {t.editPerson}
          </button>
        </div>
      </motion.div>
    </div>
  );
}

function DepartmentDetail({
  department,
  onBack,
  onAddPerson,
}: {
  department: DepartmentWithCount;
  onBack: () => void;
  onAddPerson: () => void;
}) {
  const { t, isRTL } = useLang();
  const [, setLocation] = useLocation();
  const queryClient = useQueryClient();
  const [selectedPerson, setSelectedPerson] =
    useState<CandidateWithDetails | null>(null);
  const [editingPerson, setEditingPerson] =
    useState<CandidateWithDetails | null>(null);
  const [searchTerm, setSearchTerm] = useState("");

  const {
    data: candidates = [],
    isLoading,
    error,
  } = useDepartmentCandidates(department.id);

  const deleteMutation = useDeleteCandidate();

  const filteredCandidates = candidates.filter(
    (c) =>
      c.applicantName.toLowerCase().includes(searchTerm.toLowerCase()) ||
      c.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
      c.jobTitle.toLowerCase().includes(searchTerm.toLowerCase()),
  );

  const handleDelete = (id: number) => {
    if (confirm(t.confirmDeletePerson)) {
      deleteMutation
        .mutateAsync(id)
        .then(() => {
          queryClient.invalidateQueries({
            queryKey: ["/api/talent-pool/talent-bank/department", department.id],
          });
          queryClient.invalidateQueries({
            queryKey: ["/api/talent-pool/talent-bank/departments"],
          });
          toast.success(t.personDeleted);
          setSelectedPerson(null);
        })
        .catch(() => {
          toast.error(t.serverError);
        });
    }
  };

  const handleAddSuccess = () => {
    queryClient.invalidateQueries({
      queryKey: ["/api/talent-pool/talent-bank/department", department.id],
    });
    queryClient.invalidateQueries({
      queryKey: ["/api/talent-pool/talent-bank/departments"],
    });
    onAddPerson();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <button
          onClick={onBack}
          className={`flex items-center gap-2 text-muted-foreground hover:text-foreground ${isRTL ? "flex-row-reverse" : ""}`}
        >
          <ArrowLeft className="w-5 h-5" />
          {t.backToTalentBank}
        </button>
        <button
          onClick={onAddPerson}
          className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg hover:bg-primary/90"
        >
          <Plus className="w-4 h-4" />
          {t.addPerson}
        </button>
      </div>

      <div className={isRTL ? "text-right" : ""}>
        <h1 className="text-2xl font-bold text-foreground">
          {department.name}
        </h1>
        <p className="text-muted-foreground mt-1">{t.deptWaitingPersons}</p>
      </div>

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search
            className={`absolute ${isRTL ? "right-3" : "left-3"} top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground`}
          />
          <input
            type="text"
            placeholder={t.searchEmployees}
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className={`w-full ${isRTL ? "pr-9 pl-4" : "pl-9 pr-4"} py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/20`}
          />
        </div>
      </div>

      {isLoading ? (
        <div className="text-center py-12 text-muted-foreground">
          {t.loading}
        </div>
      ) : error ? (
        <div className="text-center py-12 text-destructive">
          {t.serverError}
        </div>
      ) : filteredCandidates.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground bg-muted/30 rounded-xl">
          <Users className="w-12 h-12 mx-auto mb-3 opacity-50" />
          <p>{t.noPersonsInDept}</p>
        </div>
      ) : (
        <div className="grid gap-4">
          {filteredCandidates.map((candidate) => (
            <PersonCard
              key={candidate.id}
              candidate={candidate}
              onView={() => setSelectedPerson(candidate)}
              onEdit={() => setSelectedPerson(candidate)}
              onDelete={() => handleDelete(candidate.id)}
            />
          ))}
        </div>
      )}

      <AnimatePresence>
        {selectedPerson && (
          <PersonDetailModal
            candidate={selectedPerson}
            onClose={() => setSelectedPerson(null)}
            onEdit={() => {
              setEditingPerson(selectedPerson);
              setSelectedPerson(null);
            }}
            onDelete={() => handleDelete(selectedPerson.id)}
          />
        )}

        <AnimatePresence>
          {editingPerson && (
            <EditPersonForm
              candidate={editingPerson}
              onClose={() => setEditingPerson(null)}
              onSuccess={() => {
                queryClient.invalidateQueries({
                  queryKey: ["/api/talent-pool/talent-bank/department", department.id],
                });
                setEditingPerson(null);
                setSelectedPerson(null);
              }}
            />
          )}
        </AnimatePresence>
      </AnimatePresence>
    </div>
  );
}

export default function TalentPool() {
  const { t, isRTL } = useLang();
  const [location, setLocation] = useLocation();
  const queryClient = useQueryClient();
  const [selectedDeptId, setSelectedDeptId] = useState<number | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);

  const {
    data: departments = [],
    isLoading,
    error,
  } = useTalentBankDepartments();

  const selectedDepartment = departments.find((d) => d.id === selectedDeptId);

  const handleDepartmentClick = (deptId: number) => {
    setSelectedDeptId(deptId);
  };

  const handleBackToDepartments = () => {
    setSelectedDeptId(null);
  };

  const handleAddSuccess = () => {
    setShowAddForm(false);
    queryClient.invalidateQueries({
      queryKey: ["/api/talent-pool/talent-bank/departments"],
    });
    if (selectedDeptId) {
      queryClient.invalidateQueries({
        queryKey: ["/api/talent-pool/talent-bank/department", selectedDeptId],
      });
    }
  };

  if (selectedDeptId && selectedDepartment) {
    return (
      <>
        <DepartmentDetail
          department={selectedDepartment}
          onBack={handleBackToDepartments}
          onAddPerson={() => setShowAddForm(true)}
        />
        <AnimatePresence>
          {showAddForm && (
            <AddPersonForm
              departmentId={selectedDeptId}
              onClose={() => setShowAddForm(false)}
              onSuccess={handleAddSuccess}
            />
          )}
        </AnimatePresence>
      </>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">
            {t.talentBank}
          </h1>
          <p className="text-muted-foreground mt-1">{t.talentBankDesc}</p>
        </div>
        <button
          onClick={() => setShowAddForm(true)}
          className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg hover:bg-primary/90"
        >
          <Plus className="w-4 h-4" />
          {t.addPerson}
        </button>
      </div>

      {isLoading ? (
        <div className="text-center py-12 text-muted-foreground">
          {t.loading}
        </div>
      ) : error ? (
        <div className="text-center py-12 text-destructive">
          {t.serverError}
        </div>
      ) : departments.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground bg-muted/30 rounded-xl">
          <Building2 className="w-12 h-12 mx-auto mb-3 opacity-50" />
          <p>{t.noDepts}</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {departments.map((dept) => (
            <DepartmentCard
              key={dept.id}
              department={dept}
              onClick={() => handleDepartmentClick(dept.id)}
            />
          ))}
        </div>
      )}

      <AnimatePresence>
        {showAddForm && (
          <AddPersonForm
            departmentId={selectedDeptId || 0}
            onClose={() => setShowAddForm(false)}
            onSuccess={handleAddSuccess}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
