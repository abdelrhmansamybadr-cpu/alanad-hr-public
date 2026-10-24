import { useState } from "react";
import { Switch, Route, Router as WouterRouter } from "wouter";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Toaster as SonnerToaster } from "sonner";
import { LanguageProvider } from "./contexts/LanguageContext";
import { NotificationProvider } from "./contexts/NotificationContext";
import { AuthProvider, useAuth } from "./contexts/AuthContext";

import { AppLayout } from "./components/layout/AppLayout";
import Dashboard from "./pages/Dashboard";
import Employees from "./pages/Employees";
import Departments from "./pages/Departments";
import Leaves from "./pages/Leaves";
import Recruitment from "./pages/Recruitment";
import Reviews from "./pages/Reviews";
import Payroll from "./pages/Payroll";
import Attendance from "./pages/Attendance";
import Shifts from "./pages/Shifts";
import Announcements from "./pages/Announcements";
import NotFound from "./pages/not-found";
import Login from "./pages/Login";
import TalentPool from "./pages/TalentPool";
import LeaveAnalytics from "./pages/LeaveAnalytics";
import HRStaff from "./pages/HRStaff";
import Company from "./pages/Company";
import Requests from "./pages/Requests";
import Rewards from "./pages/Rewards";
import Onboarding from "./pages/Onboarding";
import Kudos from "./pages/Kudos";
import Reports from "./pages/Reports";
import Org from "./pages/Org";
import Group from "./pages/Group";
import Meetings from "./pages/Meetings";
import Owner from "./pages/Owner";
import Complaints from "./pages/Complaints";
import MeetingRoom from "./pages/MeetingRoom";
import { MeetingProvider } from "./contexts/MeetingContext";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      staleTime: 5 * 60 * 1000,
      retry: 1,
    },
  },
});

function AuthGate() {
  const { user, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-4">
          <div className="h-10 w-10 rounded-xl bg-gradient-to-tr from-primary to-primary/60 flex items-center justify-center shadow-lg">
            <span className="text-white font-bold text-sm">HR</span>
          </div>
          <div className="flex gap-1">
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                className="w-2 h-2 rounded-full bg-primary/60 animate-bounce"
                style={{ animationDelay: `${i * 0.15}s` }}
              />
            ))}
          </div>
        </div>
      </div>
    );
  }

  if (!user) {
    return <Login />;
  }

  return (
    <AppLayout>
      <Switch>
        <Route path="/" component={Dashboard} />
        <Route path="/employees" component={Employees} />
        <Route path="/departments" component={Departments} />
        <Route path="/leaves" component={Leaves} />
        <Route path="/leaves/analytics" component={LeaveAnalytics} />
        <Route path="/recruitment" component={Recruitment} />
        <Route path="/reviews" component={Reviews} />
        <Route path="/payroll" component={Payroll} />
        <Route path="/attendance" component={Attendance} />
        <Route path="/shifts" component={Shifts} />
        <Route path="/announcements" component={Announcements} />
        <Route path="/talent-pool" component={TalentPool} />
        <Route path="/hr-staff" component={HRStaff} />
        <Route path="/company" component={Company} />
        <Route path="/requests" component={Requests} />
        <Route path="/rewards" component={Rewards} />
        <Route path="/onboarding" component={Onboarding} />
        <Route path="/kudos" component={Kudos} />
        <Route path="/reports" component={Reports} />
        <Route path="/org" component={Org} />
        <Route path="/group" component={Group} />
        <Route path="/owner" component={Owner} />
        <Route path="/complaints" component={Complaints} />
        <Route path="/meetings" component={Meetings} />
        <Route path="/meetings/:id" component={MeetingRoom} />
        <Route component={NotFound} />
      </Switch>
    </AppLayout>
  );
}

function App() {
  return (
    <LanguageProvider>
      <AuthProvider>
        <NotificationProvider>
          <MeetingProvider>
          <QueryClientProvider client={queryClient}>
            <TooltipProvider>
              <WouterRouter base={import.meta.env.BASE_URL.replace(/\/$/, "")}>
                <AuthGate />
              </WouterRouter>
              <Toaster />
              <SonnerToaster richColors position="bottom-right" />
            </TooltipProvider>
          </QueryClientProvider>
          </MeetingProvider>
        </NotificationProvider>
      </AuthProvider>
    </LanguageProvider>
  );
}

export default App;
