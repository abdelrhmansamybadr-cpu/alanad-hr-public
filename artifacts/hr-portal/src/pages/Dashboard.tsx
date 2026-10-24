import {
  useGetDashboardStats,
  useGetRecentActivity,
  useListAnnouncements,
  ActivityItem,
} from "@workspace/api-client-react";
import { customFetch } from "@workspace/api-client-react";
import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/contexts/AuthContext";
import { useLang } from "@/contexts/LanguageContext";
import { useLocation } from "wouter";
import {
  Users,
  UserMinus,
  Briefcase,
  CalendarClock,
  DollarSign,
  ArrowUpRight,
  Megaphone,
  FileText,
  Star,
  TrendingUp,
  Bell,
  Banknote,
  Building2,
  UsersRound,
} from "lucide-react";
import { motion } from "framer-motion";
import { useEffect, useState } from "react";
import { TodayPanel } from "@/components/TodayPanel";
import { WellbeingPanel } from "@/components/WellbeingPanel";

let COMPANY_CURRENCY = "EGP";
function formatCurrency(value: number): string {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency: COMPANY_CURRENCY, maximumFractionDigits: 0 }).format(value || 0);
  } catch {
    return (value || 0).toLocaleString() + " " + COMPANY_CURRENCY;
  }
}

function getRelativeTime(dateString: string, t: any): string {
  if (!dateString) return "-";
  const date = new Date(dateString);
  if (isNaN(date.getTime())) return "-";
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return t.justNow || "Just now";
  if (diffMins < 60) return `${diffMins} ${t.minutesAgo || "minutes ago"}`;
  if (diffHours < 24) return `${diffHours} ${t.hoursAgo || "hours ago"}`;
  return `${diffDays} ${t.daysAgo || "days ago"}`;
}

function getGreeting(t: any): string {
  const hour = new Date().getHours();
  if (hour < 12) return t.goodMorning || "Good morning";
  if (hour < 18) return t.goodAfternoon || "Good afternoon";
  return t.goodEvening || "Good evening";
}

function formatDate(date: Date, locale: string): string {
  return date.toLocaleDateString(locale, {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function getActivityIcon(type: string) {
  switch (type) {
    case "leave":
      return CalendarClock;
    case "application":
      return FileText;
    case "announcement":
      return Bell;
    case "payroll":
      return Banknote;
    default:
      return FileText;
  }
}

function getActivityColor(type: string): string {
  switch (type) {
    case "leave":
      return "text-orange-500 bg-orange-50";
    case "application":
      return "text-blue-500 bg-blue-50";
    case "announcement":
      return "text-amber-500 bg-amber-50";
    case "payroll":
      return "text-emerald-500 bg-emerald-50";
    default:
      return "text-gray-500 bg-gray-50";
  }
}

function getStatusColor(status: string): string {
  const s = status?.toLowerCase();
  if (s === "pending" || s === "draft") return "bg-yellow-100 text-yellow-800";
  if (s === "approved" || s === "paid" || s === "hired")
    return "bg-green-100 text-green-800";
  if (s === "rejected") return "bg-red-100 text-red-800";
  if (s === "new" || s === "urgent") return "bg-blue-100 text-blue-800";
  if (s === "high") return "bg-orange-100 text-orange-800";
  return "bg-gray-100 text-gray-800";
}

function getPriorityColor(priority: string): string {
  const p = priority?.toLowerCase();
  if (p === "urgent") return "bg-red-100 text-red-800";
  if (p === "high") return "bg-orange-100 text-orange-800";
  return "bg-blue-100 text-blue-800";
}

export default function Dashboard() {
  const { user, company } = useAuth();
  COMPANY_CURRENCY = company?.currency ?? "EGP";
  const { t, isRTL } = useLang();
  const [, navigate] = useLocation();

  const {
    data: stats,
    isLoading: statsLoading,
    isError: statsError,
  } = useGetDashboardStats();
  const { data: activities, isLoading: activitiesLoading } =
    useGetRecentActivity();
  const { data: announcements, isLoading: announcementsLoading } =
    useListAnnouncements();

  const { data: departments } = useQuery({
    queryKey: ["departments"],
    queryFn: () => customFetch<any[]>("/api/departments", { method: "GET" }),
  });

  const { data: talentPoolOverview } = useQuery({
    queryKey: ["talent-pool-overview"],
    queryFn: () =>
      customFetch<any[]>("/api/talent-pool/overview", { method: "GET" }),
  });

  const [todayFormatted, setTodayFormatted] = useState("");
  useEffect(() => {
    setTodayFormatted(formatDate(new Date(), isRTL ? "ar-SA" : "en-US"));
  }, [isRTL]);

  if (statsLoading) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    );
  }

  if (!statsLoading && (statsError || !stats)) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center">
          <p className="text-muted-foreground text-sm">
            {isRTL
              ? "تعذر تحميل بيانات لوحة التحكم"
              : "Failed to load dashboard data"}
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            {isRTL
              ? "تأكد من تشغيل الخادم وحاول مجدداً"
              : "Make sure the server is running and refresh"}
          </p>
        </div>
      </div>
    );
  }

  const statCards = [
    {
      title: t.totalEmployees,
      value: stats?.totalEmployees || 0,
      icon: Users,
      color: "text-blue-600",
      bg: "bg-blue-50",
      border: "border-blue-100",
      link: "/employees",
      label: "",
    },
    {
      title: t.activeEmployees || "Active",
      value: stats?.activeEmployees || 0,
      icon: TrendingUp,
      color: "text-emerald-600",
      bg: "bg-emerald-50",
      border: "border-emerald-100",
      link: "/employees",
      label: "active staff",
    },
    {
      title: t.onLeaveToday,
      value: stats?.onLeave || 0,
      icon: UserMinus,
      color: "text-orange-600",
      bg: "bg-orange-50",
      border: "border-orange-100",
      link: "/leaves",
      label: "",
    },
    {
      title: t.openPositions,
      value: stats?.openPositions || 0,
      icon: Briefcase,
      color: "text-amber-600",
      bg: "bg-amber-50",
      border: "border-amber-100",
      link: "/recruitment",
      label: "",
    },
    {
      title: t.pendingLeaves,
      value: stats?.pendingLeaves || 0,
      icon: CalendarClock,
      color: "text-red-600",
      bg: "bg-red-50",
      border: "border-red-100",
      link: "/leaves",
      label: "",
    },
    {
      title: t.newApplications || "Applications",
      value: stats?.newApplications || 0,
      icon: FileText,
      color: "text-sky-600",
      bg: "bg-sky-50",
      border: "border-sky-100",
      link: "/recruitment",
      label: "",
    },
    {
      title: t.upcomingReviews || "Reviews",
      value: stats?.upcomingReviews || 0,
      icon: Star,
      color: "text-amber-600",
      bg: "bg-amber-50",
      border: "border-amber-100",
      link: "/reviews",
      label: "",
    },
    {
      title: t.totalPayroll,
      value: formatCurrency(stats?.totalPayroll || 0),
      icon: Banknote,
      color: "text-green-600",
      bg: "bg-green-50",
      border: "border-green-100",
      link: "/payroll",
      label: "",
    },
  ];

  const attendancePercent =
    stats?.totalEmployees && stats?.todayAttendance !== undefined
      ? Math.round((stats.todayAttendance / stats.totalEmployees) * 100)
      : 0;

  const talentPoolCount =
    talentPoolOverview?.reduce((sum: number, dept: any) => {
      const poolCount =
        dept.jobs?.reduce((jobSum: number, job: any) => {
          return jobSum + (job.counts?.talent_pool || 0);
        }, 0) || 0;
      return sum + poolCount;
    }, 0) || 0;

  return (
    <div className="space-y-8 pb-10">
      <div className={isRTL ? "text-right" : ""}>
        <h1 className="text-3xl font-bold text-foreground tracking-tight">
          {getGreeting(t)}, {user?.name || "User"}
        </h1>
        <p className="text-muted-foreground mt-1">{todayFormatted}</p>
      </div>

      <TodayPanel stats={stats as any} />
      <WellbeingPanel />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-6">
        {statCards.map((stat, i) => (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.1 }}
            key={stat.title}
            onClick={() => stat.link && navigate(stat.link)}
            className={`bg-card p-6 rounded-2xl border ${stat.border} shadow-sm hover:shadow-md transition-all cursor-pointer ${stat.link ? "hover:scale-[1.02]" : ""} relative overflow-hidden group`}
          >
            <div
              className={`absolute -right-6 -top-6 w-24 h-24 rounded-full opacity-20 group-hover:scale-150 transition-transform duration-500 ease-out ${stat.bg}`}
            ></div>
            <div className="flex items-center justify-between relative z-10">
              <div className={isRTL ? "text-right" : ""}>
                <p className="text-sm font-medium text-muted-foreground">
                  {stat.title}
                </p>
                <h3 className="text-2xl font-bold text-foreground mt-2">
                  {stat.value}
                </h3>
                {stat.label && (
                  <p className="text-xs text-muted-foreground mt-1">
                    {stat.label}
                  </p>
                )}
              </div>
              <div className={`p-3 rounded-xl ${stat.bg} ${stat.color}`}>
                <stat.icon className="w-6 h-6" />
              </div>
            </div>
          </motion.div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 bg-card rounded-2xl border border-border shadow-sm p-6">
          <div
            className={`flex items-center justify-between mb-6 ${isRTL ? "flex-row-reverse" : ""}`}
          >
            <h3 className="text-lg font-bold text-foreground">
              {t.recentActivity}
            </h3>
            <button
              onClick={() => navigate("/leaves")}
              className="text-sm text-primary font-medium hover:underline"
            >
              {t.viewAll}
            </button>
          </div>

          <div className="space-y-4">
            {activitiesLoading ? (
              <>
                {[1, 2, 3].map((i) => (
                  <div key={i} className="flex items-start gap-4 animate-pulse">
                    <div className="w-10 h-10 rounded-full bg-gray-200"></div>
                    <div className="flex-1 space-y-2">
                      <div className="h-4 bg-gray-200 rounded w-1/3"></div>
                      <div className="h-3 bg-gray-200 rounded w-2/3"></div>
                    </div>
                  </div>
                ))}
              </>
            ) : activities && activities.length > 0 ? (
              activities.map((item: ActivityItem, i) => {
                const Icon = getActivityIcon(item.type);
                const colorClass = getActivityColor(item.type);
                return (
                  <div
                    key={i}
                    className={`flex items-start gap-4 ${isRTL ? "flex-row-reverse" : ""}`}
                  >
                    <div className={`p-2 rounded-full ${colorClass} mt-0.5`}>
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className={`flex-1 ${isRTL ? "text-right" : ""}`}>
                      <h4 className="text-sm font-semibold text-foreground">
                        {item.title}
                      </h4>
                      <p className="text-sm text-muted-foreground">
                        {item.desc}
                      </p>
                    </div>
                    <div className="flex flex-col items-end gap-1">
                      <span
                        className={`px-2 py-0.5 rounded text-[10px] font-medium ${getStatusColor(item.status)}`}
                      >
                        {(t as any)[
                          `status${item.status.charAt(0).toUpperCase()}${item.status.slice(1)}`
                        ] || item.status}
                      </span>
                      <span className="text-xs text-muted-foreground whitespace-nowrap">
                        {getRelativeTime(item.date, t)}
                      </span>
                    </div>
                  </div>
                );
              })
            ) : (
              <p className="text-muted-foreground text-center py-4">
                {t.noRecentActivity || "No recent activity"}
              </p>
            )}
          </div>
        </div>

        <div className="bg-gradient-to-br from-primary to-primary/80 rounded-2xl shadow-lg p-6 text-primary-foreground relative overflow-hidden">
          <div className="absolute top-0 right-0 w-64 h-64 bg-white/10 rounded-full blur-3xl -mr-10 -mt-10 pointer-events-none"></div>

          <div
            className={`flex items-center gap-3 mb-6 relative z-10 ${isRTL ? "flex-row-reverse" : ""}`}
          >
            <div className="p-2 bg-white/20 rounded-lg">
              <Megaphone className="w-5 h-5 text-white" />
            </div>
            <h3 className="text-lg font-bold">{t.companyNews}</h3>
          </div>

          <div className="space-y-4 relative z-10">
            {announcementsLoading ? (
              <>
                {[1, 2].map((i) => (
                  <div
                    key={i}
                    className="bg-white/10 rounded-xl p-4 animate-pulse"
                  >
                    <div className="h-4 bg-white/20 rounded w-1/4 mb-2"></div>
                    <div className="h-3 bg-white/10 rounded w-3/4"></div>
                  </div>
                ))}
              </>
            ) : announcements && announcements.length > 0 ? (
              announcements.slice(0, 3).map((ann: any, i: number) => (
                <div
                  key={i}
                  onClick={() => navigate("/announcements")}
                  className={`bg-white/10 rounded-xl p-4 backdrop-blur-sm border border-white/10 hover:bg-white/20 transition-colors cursor-pointer ${isRTL ? "text-right" : ""}`}
                >
                  <span
                    className={`px-2 py-0.5 rounded text-[10px] font-bold bg-white/20 text-white uppercase tracking-wider mb-2 inline-block`}
                  >
                    {ann.priority}
                  </span>
                  <h4 className="font-semibold text-white">{ann.title}</h4>
                  <p className="text-sm text-primary-foreground/80 mt-1 line-clamp-2">
                    {ann.content}
                  </p>
                  <p className="text-xs text-primary-foreground/50 mt-2">
                    {new Date(ann.createdAt).toLocaleDateString()}
                  </p>
                </div>
              ))
            ) : (
              <p className="text-primary-foreground/70 text-center py-4">
                {t.noAnnouncements || "No announcements"}
              </p>
            )}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-card rounded-2xl border border-border p-6 shadow-sm">
          <div className="flex items-center gap-4">
            <div className="p-3 rounded-xl bg-cyan-50 text-cyan-600">
              <Building2 className="w-6 h-6" />
            </div>
            <div>
              <p className="text-sm text-muted-foreground">
                {t.totalDepartments || "Departments"}
              </p>
              <h3 className="text-2xl font-bold text-foreground">
                {departments?.length || 0}
              </h3>
            </div>
          </div>
        </div>

        <div className="bg-card rounded-2xl border border-border p-6 shadow-sm">
          <div className="flex items-center gap-4">
            <div className="p-3 rounded-xl bg-cyan-50 text-cyan-600">
              <UsersRound className="w-6 h-6" />
            </div>
            <div>
              <p className="text-sm text-muted-foreground">
                {t.attendanceToday || "Attendance Today"}
              </p>
              <h3 className="text-2xl font-bold text-foreground">
                {attendancePercent}%
              </h3>
              <p className="text-xs text-muted-foreground mt-0.5">
                {stats?.todayAttendance ?? 0} / {stats?.totalEmployees ?? 0}
              </p>
            </div>
          </div>
        </div>

        <div className="bg-card rounded-2xl border border-border p-6 shadow-sm">
          <div className="flex items-center gap-4">
            <div className="p-3 rounded-xl bg-teal-50 text-teal-600">
              <Users className="w-6 h-6" />
            </div>
            <div>
              <p className="text-sm text-muted-foreground">
                {t.talentPoolCount || "Talent Pool"}
              </p>
              <h3 className="text-2xl font-bold text-foreground">
                {talentPoolCount}
              </h3>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
