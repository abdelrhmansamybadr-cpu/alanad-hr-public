import { useState } from "react";
import { Link, useLocation } from "wouter";
import {
  LayoutDashboard,
  ShieldAlert,
  Users,
  Building2,
  CalendarDays,
  Briefcase,
  Star,
  CircleDollarSign,
  Clock,
  AlarmClock,
  Megaphone,
  Archive,
  UsersRound,
  UserCog,
  ClipboardList,
  Settings2,
  Trophy,
  FileSpreadsheet,
  Network,
  ListChecks,
  Heart,
  Layers,
  Video,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useLang } from "@/contexts/LanguageContext";
import { useAuth } from "@/contexts/AuthContext";
import { useOwnerMe } from "@/lib/premium";
import { HelpPanel } from "@/components/HelpWidget";
import { CompanySwitcher } from "@/components/CompanySwitcher";

export function Sidebar() {
  const [location] = useLocation();
  const { t, isRTL } = useLang();
  const { isManager, hasPermission, company, user, group } = useAuth();
  const ownerMe = useOwnerMe();
  const [helpOpen, setHelpOpen] = useState(false);

  const moduleMap: Record<string, string> = {
    "/": "dashboard",
    "/employees": "employees",
    "/departments": "departments",
    "/leaves": "leaves",
    "/leaves/analytics": "leave_analytics",
    "/recruitment": "recruitment",
    "/reviews": "reviews",
    "/payroll": "payroll",
    "/attendance": "attendance",
    "/shifts": "shifts",
    "/announcements": "announcements",
    "/talent-pool": "talent_pool",
  };

  const navigation = [
    {
      name: t.dashboard,
      href: "/",
      icon: LayoutDashboard,
      module: "dashboard",
    },
    { name: t.employees, href: "/employees", icon: Users, module: "employees" },
    {
      name: t.departments,
      href: "/departments",
      icon: Building2,
      module: "departments",
    },
    {
      name: t.timeLeave,
      href: "/leaves",
      icon: CalendarDays,
      module: "leaves",
    },
    {
      name: t.recruitment,
      href: "/recruitment",
      icon: Briefcase,
      module: "recruitment",
    },
    { name: t.reviews, href: "/reviews", icon: Star, module: "reviews" },
    {
      name: t.payroll,
      href: "/payroll",
      icon: CircleDollarSign,
      module: "payroll",
    },
    {
      name: t.attendance,
      href: "/attendance",
      icon: Clock,
      module: "attendance",
    },
    { name: t.shifts, href: "/shifts", icon: AlarmClock, module: "shifts" },
    {
      name: t.announcements,
      href: "/announcements",
      icon: Megaphone,
      module: "announcements",
    },
    {
      name: t.talentBank,
      href: "/talent-pool",
      icon: UsersRound,
      module: "talent_pool",
    },
    {
      name: isRTL ? "طلبات الموظفين" : "Requests",
      href: "/requests",
      icon: ClipboardList,
      module: "requests",
    },
    {
      name: isRTL ? "المكافآت والمستويات" : "Rewards",
      href: "/rewards",
      icon: Trophy,
      module: "dashboard",
    },
    {
      name: isRTL ? "الاجتماعات" : "Meetings",
      href: "/meetings",
      icon: Video,
      module: "dashboard",
    },
    {
      name: isRTL ? "كلمات الشكر" : "Kudos",
      href: "/kudos",
      icon: Heart,
      module: "dashboard",
    },
    {
      name: isRTL ? "التهيئة الوظيفية" : "Onboarding",
      href: "/onboarding",
      icon: ListChecks,
      module: "dashboard",
    },
    {
      name: isRTL ? "الهيكل التنظيمي" : "Org chart",
      href: "/org",
      icon: Network,
      module: "dashboard",
    },
    {
      name: isRTL ? "التقارير والنشاط" : "Reports",
      href: "/reports",
      icon: FileSpreadsheet,
      module: "dashboard",
    },
  ];

  const isAdmin = user?.role === "hr_admin";
  const managerNav = [
    ...(ownerMe.canManage
      ? [{ name: isRTL ? "التحكم في الخدمات" : "Feature control", href: "/owner", icon: Layers }]
      : []),
    ...(company?.features?.complaints || ownerMe.canManage
      ? [{ name: isRTL ? "الشكاوى" : "Complaints", href: "/complaints", icon: ShieldAlert }]
      : []),
    // Company group: only the super admin manages the companies under the holding
    ...(group?.isSuperAdmin || group?.isOwner
      ? [{ name: isRTL ? "إدارة المجموعة" : "Group management", href: "/group", icon: Layers }]
      : []),
    ...(isAdmin
      ? [
          {
            name: isRTL ? "إدارة الموظفين" : "Staff Management",
            href: "/hr-staff",
            icon: UserCog,
          },
        ]
      : []),
    {
      name: isRTL ? "إعدادات الشركة" : "Company Settings",
      href: "/company",
      icon: Settings2,
    },
  ];

  // Hide what the company switched off and what this HR manager may not use.
  const enabledByCompany = (m: string) =>
    m === "dashboard" || !company?.modules || company.modules.includes(m);
  const filteredNav = navigation.filter(
    (item) => enabledByCompany(item.module) && (item.module === "dashboard" || hasPermission(item.module)),
  );

  return (
    <>
      <div
        className={`flex h-full w-64 flex-col bg-sidebar border-${isRTL ? "l" : "r"} border-sidebar-border shadow-sm shrink-0`}
      >
        <div className="flex h-16 items-center px-6 border-b border-sidebar-border">
          <Link
            href="/"
            className="flex items-center gap-3 group transition-transform hover:scale-105 active:scale-95 cursor-pointer"
          >
            <img src="/images/logo-icon.png" alt="" className="h-9 w-9 rounded-xl" />
            <span className="font-bold text-xl tracking-tight text-sidebar-foreground group-hover:text-primary transition-colors">
              Al Anad HR
            </span>
          </Link>
        </div>

        {group && group.companies.length > 1 && (
          <div className="px-4 pt-4">
            <CompanySwitcher />
          </div>
        )}

        <nav className="flex-1 overflow-y-auto py-6 px-4 space-y-1">
          {filteredNav.map((item) => {
            const isActive =
              location === item.href ||
              (item.href !== "/" && location.startsWith(item.href));

            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "group flex items-center px-3 py-2.5 text-sm font-medium rounded-xl transition-all duration-200",
                  isRTL ? "flex-row-reverse text-right" : "",
                  isActive
                    ? "bg-primary text-primary-foreground shadow-md shadow-primary/20"
                    : "text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                )}
              >
                <item.icon
                  className={cn(
                    "flex-shrink-0 h-5 w-5 transition-transform duration-200",
                    isRTL ? "ml-3" : "mr-3",
                    isActive
                      ? "text-primary-foreground"
                      : "text-sidebar-foreground/60 group-hover:text-sidebar-accent-foreground group-hover:scale-110",
                  )}
                  aria-hidden="true"
                />
                {item.name}
              </Link>
            );
          })}

          {isManager &&
            managerNav.map((item) => {
              const isActive = location === item.href;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "group flex items-center px-3 py-2.5 text-sm font-medium rounded-xl transition-all duration-200",
                    isRTL ? "flex-row-reverse text-right" : "",
                    isActive
                      ? "bg-primary text-primary-foreground shadow-md shadow-primary/20"
                      : "text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                  )}
                >
                  <item.icon
                    className={cn(
                      "flex-shrink-0 h-5 w-5 transition-transform duration-200",
                      isRTL ? "ml-3" : "mr-3",
                      isActive
                        ? "text-primary-foreground"
                        : "text-sidebar-foreground/60 group-hover:text-sidebar-accent-foreground group-hover:scale-110",
                    )}
                    aria-hidden="true"
                  />
                  {item.name}
                </Link>
              );
            })}
        </nav>

        <div className="p-4 border-t border-sidebar-border">
          <div className="rounded-xl bg-gradient-to-br from-primary/10 to-primary/5 p-4 border border-primary/10 relative overflow-hidden">
            <div className="absolute -right-4 -top-4 w-16 h-16 bg-primary/10 rounded-full blur-xl"></div>
            <h4
              className={`font-semibold text-sm text-foreground ${isRTL ? "text-right" : ""}`}
            >
              {t.needHelp}
            </h4>
            <p
              className={`text-xs text-muted-foreground mt-1 mb-3 ${isRTL ? "text-right" : ""}`}
            >
              {t.helpDesc}
            </p>
            <button
              onClick={() => setHelpOpen(true)}
              className="w-full text-xs font-medium bg-background text-foreground border border-border shadow-sm rounded-lg px-3 py-2 hover:bg-muted transition-colors"
            >
              {t.viewDocs}
            </button>
          </div>
        </div>
      </div>

      <HelpPanel open={helpOpen} onClose={() => setHelpOpen(false)} />
    </>
  );
}
