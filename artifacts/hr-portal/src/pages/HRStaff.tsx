import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { motion, AnimatePresence } from "framer-motion";
import { useLang } from "@/contexts/LanguageContext";
import { useAuth } from "@/contexts/AuthContext";
import {
  useGetHRStaff,
  useCreateHRStaff,
  useUpdateHRStaff,
  useUpdateHRStaffStatus,
  useResetHRStaffPassword,
  useUpdateHRStaffPermissions,
  useDeleteHRStaff,
  type HRStaffMember,
} from "@workspace/api-client-react";
import {
  Plus,
  X,
  Edit,
  Trash2,
  Shield,
  Key,
  MoreHorizontal,
  Check,
  XCircle,
} from "lucide-react";
import { toast } from "sonner";

const MODULES = [
  { key: "dashboard", ar: "لوحة التحكم", en: "Dashboard" },
  { key: "employees", ar: "الموظفين", en: "Employees" },
  { key: "departments", ar: "الأقسام", en: "Departments" },
  { key: "leaves", ar: "الإجازات", en: "Leaves" },
  { key: "leave_analytics", ar: "تحليلات الإجازات", en: "Leave Analytics" },
  { key: "recruitment", ar: "التوظيف", en: "Recruitment" },
  { key: "talent_pool", ar: "بنك المواهب", en: "Talent Pool" },
  { key: "attendance", ar: "الحضور", en: "Attendance" },
  { key: "shifts", ar: "الورديات", en: "Shifts" },
  { key: "payroll", ar: "الرواتب", en: "Payroll" },
  { key: "reviews", ar: "التقييمات", en: "Reviews" },
  { key: "announcements", ar: "الإعلانات", en: "Announcements" },
  { key: "employee_documents", ar: "وثائق الموظفين", en: "Employee Documents" },
];

function getStatusColor(status: string): string {
  switch (status) {
    case "active":
      return "bg-emerald-100 text-emerald-700 border-emerald-200";
    case "pending":
      return "bg-amber-100 text-amber-700 border-amber-200";
    case "suspended":
      return "bg-orange-100 text-orange-700 border-orange-200";
    case "disabled":
      return "bg-red-100 text-red-700 border-red-200";
    default:
      return "bg-gray-100 text-gray-700 border-gray-200";
  }
}

function getStatusLabel(status: string, t: any): string {
  switch (status) {
    case "active":
      return t.active || "Active";
    case "pending":
      return t.pending || "Pending";
    case "suspended":
      return t.suspended || "Suspended";
    case "disabled":
      return t.disabled || "Disabled";
    default:
      return status;
  }
}

interface CreateFormProps {
  onClose: () => void;
  onSuccess: () => void;
}

function CreateForm({ onClose, onSuccess }: CreateFormProps) {
  const { t, isRTL } = useLang();
  const createMutation = useCreateHRStaff();
  const [formData, setFormData] = useState({
    name: "",
    email: "",
    password: "",
    title: "",
    phone: "",
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const validate = () => {
    const newErrors: Record<string, string> = {};
    if (!formData.name.trim()) {
      newErrors.name = isRTL ? "الاسم مطلوب" : "Name is required";
    }
    if (!formData.email.trim()) {
      newErrors.email = isRTL ? "البريد مطلوب" : "Email is required";
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = isRTL ? "البريد غير صحيح" : "Invalid email";
    }
    if (!formData.password) {
      newErrors.password = isRTL
        ? "كلمة المرور مطلوبة"
        : "Password is required";
    } else if (formData.password.length < 6) {
      newErrors.password = isRTL ? "6 أحرف على الأقل" : "Minimum 6 characters";
    }
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;
    try {
      await createMutation.mutateAsync(formData);
      toast.success(
        isRTL ? "تم إضافة الموظف بنجاح" : "Employee added successfully",
      );
      onSuccess();
    } catch (error: any) {
      toast.error(error?.message || (isRTL ? "حدث خطأ" : "An error occurred"));
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-lg rounded-2xl shadow-xl overflow-hidden border border-border"
      >
        <div className="p-6 border-b border-border flex items-center justify-between">
          <h2 className="text-xl font-bold">
            {isRTL ? "إضافة موظف جديد" : "Add New Employee"}
          </h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.fullName || "Name"} *
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) =>
                setFormData({ ...formData, name: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
            {errors.name && (
              <p className="text-xs text-destructive mt-1">{errors.name}</p>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.email} *
            </label>
            <input
              type="email"
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
              {t.password} *
            </label>
            <input
              type="password"
              value={formData.password}
              onChange={(e) =>
                setFormData({ ...formData, password: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
            {errors.password && (
              <p className="text-xs text-destructive mt-1">{errors.password}</p>
            )}
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.position}
            </label>
            <input
              type="text"
              value={formData.title}
              onChange={(e) =>
                setFormData({ ...formData, title: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
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
              {createMutation.isPending
                ? t.saving || "Saving..."
                : t.save || "Save"}
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}

interface EditFormProps {
  staff: HRStaffMember;
  onClose: () => void;
  onSuccess: () => void;
}

function EditForm({ staff, onClose, onSuccess }: EditFormProps) {
  const { t, isRTL } = useLang();
  const updateMutation = useUpdateHRStaff();
  const [formData, setFormData] = useState({
    name: staff.name,
    title: staff.title || "",
    phone: staff.phone || "",
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await updateMutation.mutateAsync({ id: staff.id, data: formData });
      toast.success(isRTL ? "تم التحديث بنجاح" : "Updated successfully");
      onSuccess();
    } catch (error) {
      toast.error(isRTL ? "حدث خطأ" : "An error occurred");
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-lg rounded-2xl shadow-xl overflow-hidden border border-border"
      >
        <div className="p-6 border-b border-border flex items-center justify-between">
          <h2 className="text-xl font-bold">
            {isRTL ? "تعديل بيانات الموظف" : "Edit Employee"}
          </h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.fullName || "Name"}
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) =>
                setFormData({ ...formData, name: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {t.position}
            </label>
            <input
              type="text"
              value={formData.title}
              onChange={(e) =>
                setFormData({ ...formData, title: e.target.value })
              }
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
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
              {updateMutation.isPending
                ? t.saving || "Saving..."
                : t.save || "Save"}
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}

interface StatusFormProps {
  staff: HRStaffMember;
  onClose: () => void;
  onSuccess: () => void;
}

function StatusForm({ staff, onClose, onSuccess }: StatusFormProps) {
  const { t, isRTL } = useLang();
  const statusMutation = useUpdateHRStaffStatus();
  const [status, setStatus] = useState(staff.status);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await statusMutation.mutateAsync({ id: staff.id, status });
      toast.success(isRTL ? "تم تحديث الحالة" : "Status updated");
      onSuccess();
    } catch (error) {
      toast.error(isRTL ? "حدث خطأ" : "An error occurred");
    }
  };

  const statuses = [
    { value: "active", label: isRTL ? "نشط" : "Active" },
    { value: "pending", label: isRTL ? "معلق" : "Pending" },
    { value: "suspended", label: isRTL ? "موقف" : "Suspended" },
    { value: "disabled", label: isRTL ? "معطل" : "Disabled" },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-md rounded-2xl shadow-xl overflow-hidden border border-border"
      >
        <div className="p-6 border-b border-border flex items-center justify-between">
          <h2 className="text-xl font-bold">
            {isRTL ? "تغيير الحالة" : "Change Status"}
          </h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="space-y-2">
            {statuses.map((s) => (
              <label
                key={s.value}
                className={`flex items-center p-3 rounded-lg border cursor-pointer transition-colors ${
                  status === s.value
                    ? "border-primary bg-primary/10"
                    : "border-border hover:bg-muted"
                }`}
              >
                <input
                  type="radio"
                  name="status"
                  value={s.value}
                  checked={status === s.value}
                  onChange={(e) => setStatus(e.target.value)}
                  className="mr-3"
                />
                <span
                  className={`text-sm font-medium ${getStatusColor(s.value)}`}
                >
                  {s.label}
                </span>
              </label>
            ))}
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
              disabled={statusMutation.isPending}
              className="flex-1 px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 disabled:opacity-50"
            >
              {statusMutation.isPending
                ? t.saving || "Saving..."
                : t.save || "Save"}
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}

interface PasswordFormProps {
  staff: HRStaffMember;
  onClose: () => void;
  onSuccess: () => void;
}

function PasswordForm({ staff, onClose, onSuccess }: PasswordFormProps) {
  const { t, isRTL } = useLang();
  const passwordMutation = useResetHRStaffPassword();
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < 6) {
      setError(isRTL ? "6 أحرف على الأقل" : "Minimum 6 characters");
      return;
    }
    if (password !== confirm) {
      setError(isRTL ? "كلمتان غير متطابقتين" : "Passwords don't match");
      return;
    }
    try {
      await passwordMutation.mutateAsync({ id: staff.id, password });
      toast.success(
        isRTL ? "تم إعادة تعيين كلمة المرور" : "Password reset successfully",
      );
      onSuccess();
    } catch (error) {
      toast.error(isRTL ? "حدث خطأ" : "An error occurred");
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-md rounded-2xl shadow-xl overflow-hidden border border-border"
      >
        <div className="p-6 border-b border-border flex items-center justify-between">
          <h2 className="text-xl font-bold">
            {isRTL ? "إعادة تعيين كلمة المرور" : "Reset Password"}
          </h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {isRTL ? "كلمة المرور الجديدة" : "New Password"}
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          <div>
            <label className="text-sm font-medium text-muted-foreground">
              {isRTL ? "تأكيد كلمة المرور" : "Confirm Password"}
            </label>
            <input
              type="password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              className="w-full mt-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
            />
          </div>

          {error && <p className="text-xs text-destructive">{error}</p>}

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
              disabled={passwordMutation.isPending}
              className="flex-1 px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 disabled:opacity-50"
            >
              {passwordMutation.isPending
                ? t.saving || "Saving..."
                : t.save || "Save"}
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}

interface PermissionsFormProps {
  staff: HRStaffMember;
  onClose: () => void;
  onSuccess: () => void;
}

function PermissionsForm({ staff, onClose, onSuccess }: PermissionsFormProps) {
  const { t, isRTL } = useLang();
  const queryClient = useQueryClient();
  const permissionsMutation = useUpdateHRStaffPermissions();
  const [permissions, setPermissions] = useState<Record<string, boolean>>(
    () => {
      const initial: Record<string, boolean> = {};
      MODULES.forEach((m) => {
        const existing = staff.permissions?.find((p) => p.module === m.key);
        initial[m.key] = existing?.enabled ?? false;
      });
      return initial;
    },
  );

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const perms = Object.entries(permissions).map(([module, enabled]) => ({
        module,
        enabled,
      }));
      await permissionsMutation.mutateAsync({
        id: staff.id,
        permissions: perms,
      });
      queryClient.invalidateQueries({ queryKey: ["/api/hr-staff"] });
      toast.success(isRTL ? "تم حفظ الأذونات" : "Permissions saved");
      onSuccess();
    } catch (error) {
      toast.error(isRTL ? "حدث خطأ" : "An error occurred");
    }
  };

  const toggleModule = (module: string) => {
    setPermissions((prev) => ({ ...prev, [module]: !prev[module] }));
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card w-full max-w-lg rounded-2xl shadow-xl overflow-hidden border border-border max-h-[80vh] flex flex-col"
      >
        <div className="p-6 border-b border-border flex items-center justify-between shrink-0">
          <h2 className="text-xl font-bold">
            {isRTL
              ? `إدارة صلاحيات ${staff.name}`
              : `Manage Permissions - ${staff.name}`}
          </h2>
          <button onClick={onClose} className="p-2 hover:bg-muted rounded-lg">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form
          onSubmit={handleSubmit}
          className="p-6 space-y-3 overflow-y-auto flex-1"
        >
          {MODULES.map((module) => (
            <label
              key={module.key}
              className="flex items-center justify-between p-3 rounded-lg border border-border hover:bg-muted/50 cursor-pointer"
            >
              <span className="text-sm font-medium">
                {isRTL ? module.ar : module.en}
              </span>
              <button
                type="button"
                onClick={() => toggleModule(module.key)}
                className={`w-10 h-6 rounded-full transition-colors ${
                  permissions[module.key] ? "bg-primary" : "bg-muted"
                }`}
              >
                <div
                  className={`w-5 h-5 rounded-full bg-white shadow transition-transform ${
                    permissions[module.key]
                      ? "translate-x-4"
                      : "translate-x-0.5"
                  }`}
                />
              </button>
            </label>
          ))}
        </form>

        <div
          className={`p-6 border-t border-border flex gap-3 shrink-0 ${isRTL ? "flex-row-reverse" : ""}`}
        >
          <button
            type="button"
            onClick={onClose}
            className="flex-1 px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg"
          >
            {t.cancel}
          </button>
          <button
            type="submit"
            onClick={handleSubmit}
            disabled={permissionsMutation.isPending}
            className="flex-1 px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 disabled:opacity-50"
          >
            {permissionsMutation.isPending
              ? t.saving || "Saving..."
              : t.save || "Save"}
          </button>
        </div>
      </motion.div>
    </div>
  );
}

export default function HRStaff() {
  const { t, isRTL } = useLang();
  const { isManager } = useAuth();
  const queryClient = useQueryClient();
  const { data: staff = [], isLoading } = useGetHRStaff();

  const [showCreate, setShowCreate] = useState(false);
  const [editingStaff, setEditingStaff] = useState<HRStaffMember | null>(null);
  const [statusStaff, setStatusStaff] = useState<HRStaffMember | null>(null);
  const [passwordStaff, setPasswordStaff] = useState<HRStaffMember | null>(
    null,
  );
  const [permsStaff, setPermsStaff] = useState<HRStaffMember | null>(null);
  const [deletingStaff, setDeletingStaff] = useState<HRStaffMember | null>(
    null,
  );
  const deleteMutation = useDeleteHRStaff();

  if (!isManager) {
    return (
      <div className="flex items-center justify-center min-h-[400px]">
        <div className="text-center p-6 bg-muted/30 rounded-xl border border-border">
          <h3 className="text-lg font-semibold text-foreground mb-2">
            {isRTL ? "غير مصرح" : "Access Denied"}
          </h3>
          <p className="text-sm text-muted-foreground">
            {isRTL
              ? "هذه الصفحة للمديرين فقط"
              : "This page is for managers only"}
          </p>
        </div>
      </div>
    );
  }

  const handleDelete = async () => {
    if (!deletingStaff) return;
    try {
      await deleteMutation.mutateAsync(deletingStaff.id);
      queryClient.invalidateQueries({ queryKey: ["/api/hr-staff"] });
      toast.success(isRTL ? "تم الحذف بنجاح" : "Deleted successfully");
      setDeletingStaff(null);
    } catch (error) {
      toast.error(isRTL ? "حدث خطأ" : "An error occurred");
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">
            {isRTL ? "إدارة الموظفين" : "Staff Management"}
          </h1>
          <p className="text-muted-foreground mt-1">
            {isRTL ? "إدارة موظفي الموارد البشرية" : "Manage HR staff members"}
          </p>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg hover:bg-primary/90"
        >
          <Plus className="w-4 h-4" />
          {isRTL ? "إضافة موظف" : "Add Employee"}
        </button>
      </div>

      {isLoading ? (
        <div className="text-center py-12 text-muted-foreground">
          {t.loading || "Loading..."}
        </div>
      ) : staff.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground bg-muted/30 rounded-xl">
          <p>{isRTL ? "لا يوجد موظفين" : "No staff members found"}</p>
        </div>
      ) : (
        <div className="grid gap-4">
          {staff.map((member) => (
            <motion.div
              key={member.id}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              className="bg-card rounded-xl border border-border p-4"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                    <span className="text-primary font-semibold">
                      {member.name.charAt(0).toUpperCase()}
                    </span>
                  </div>
                  <div>
                    <h3 className="font-semibold text-foreground">
                      {member.name}
                    </h3>
                    <p className="text-sm text-muted-foreground">
                      {member.email}
                    </p>
                    {member.title && (
                      <p className="text-sm text-muted-foreground">
                        {member.title}
                      </p>
                    )}
                  </div>
                </div>

                <div
                  className={`flex items-center gap-4 ${isRTL ? "flex-row-reverse" : ""}`}
                >
                  <span
                    className={`px-3 py-1 rounded-full text-xs font-medium border ${getStatusColor(member.status)}`}
                  >
                    {getStatusLabel(member.status, t)}
                  </span>

                  {(member as any).isOwner && (
                    <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full text-xs font-medium border bg-amber-50 text-amber-800 border-amber-200">
                      <Shield className="w-3.5 h-3.5" />{isRTL ? "حساب المالك — لا يغيّره غير المالك" : "Owner account — only the owner can change it"}
                    </span>
                  )}
                  <div className={`flex gap-1 ${(member as any).isOwner ? "hidden" : ""}`}>
                    <button
                      onClick={() => setEditingStaff(member)}
                      className="p-2 text-muted-foreground hover:text-primary hover:bg-primary/10 rounded-lg"
                      title={isRTL ? "تعديل" : "Edit"}
                    >
                      <Edit className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => setPermsStaff(member)}
                      className="p-2 text-muted-foreground hover:text-amber-600 hover:bg-amber-50 rounded-lg"
                      title={isRTL ? "الصلاحيات" : "Permissions"}
                    >
                      <Shield className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => setStatusStaff(member)}
                      className="p-2 text-muted-foreground hover:text-amber-600 hover:bg-amber-50 rounded-lg"
                      title={isRTL ? "الحالة" : "Status"}
                    >
                      <MoreHorizontal className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => setPasswordStaff(member)}
                      className="p-2 text-muted-foreground hover:text-blue-600 hover:bg-blue-50 rounded-lg"
                      title={isRTL ? "كلمة المرور" : "Password"}
                    >
                      <Key className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => setDeletingStaff(member)}
                      className="p-2 text-muted-foreground hover:text-destructive hover:bg-destructive/10 rounded-lg"
                      title={isRTL ? "حذف" : "Delete"}
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              </div>

              <p className="text-xs text-muted-foreground mt-2">
                {isRTL ? "تاريخ الإنشاء: " : "Created: "}
                {new Date(member.createdAt).toLocaleDateString()}
              </p>
            </motion.div>
          ))}
        </div>
      )}

      <AnimatePresence>
        {showCreate && (
          <CreateForm
            onClose={() => setShowCreate(false)}
            onSuccess={() => {
              setShowCreate(false);
              queryClient.invalidateQueries({ queryKey: ["/api/hr-staff"] });
            }}
          />
        )}

        {editingStaff && (
          <EditForm
            staff={editingStaff}
            onClose={() => setEditingStaff(null)}
            onSuccess={() => {
              setEditingStaff(null);
              queryClient.invalidateQueries({ queryKey: ["/api/hr-staff"] });
            }}
          />
        )}

        {statusStaff && (
          <StatusForm
            staff={statusStaff}
            onClose={() => setStatusStaff(null)}
            onSuccess={() => {
              setStatusStaff(null);
              queryClient.invalidateQueries({ queryKey: ["/api/hr-staff"] });
            }}
          />
        )}

        {passwordStaff && (
          <PasswordForm
            staff={passwordStaff}
            onClose={() => setPasswordStaff(null)}
            onSuccess={() => setPasswordStaff(null)}
          />
        )}

        {permsStaff && (
          <PermissionsForm
            staff={permsStaff}
            onClose={() => setPermsStaff(null)}
            onSuccess={() => setPermsStaff(null)}
          />
        )}

        {deletingStaff && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              className="bg-card w-full max-w-md rounded-2xl shadow-xl overflow-hidden border border-border p-6"
            >
              <h3 className="text-xl font-bold mb-4">
                {isRTL ? "تأكيد الحذف" : "Confirm Delete"}
              </h3>
              <p className="text-muted-foreground mb-6">
                {isRTL
                  ? `هل أنت متأكد من حذف ${deletingStaff.name}؟`
                  : `Are you sure you want to delete ${deletingStaff.name}?`}
              </p>
              <div className={`flex gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                <button
                  onClick={() => setDeletingStaff(null)}
                  className="flex-1 px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg"
                >
                  {t.cancel}
                </button>
                <button
                  onClick={handleDelete}
                  className="flex-1 px-4 py-2 text-sm font-medium bg-destructive text-destructive-foreground rounded-lg hover:bg-destructive/90"
                >
                  {isRTL ? "حذف" : "Delete"}
                </button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
