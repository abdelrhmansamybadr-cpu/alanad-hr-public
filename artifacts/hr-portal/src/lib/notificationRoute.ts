/**
 * Where a clicked notification leads (website). EVERY kind the server creates has a target and an unknown kind opens the
 * dashboard, so a click never does "nothing". `data` is the notification's own data (e.g. {meetingId: 12}).
 */
export function routeForNotification(type: string, data?: any): string {
  const t = (type || "").toLowerCase();
  const meetingId = Number(data?.meetingId ?? data?.meeting_id);
  if (t === "meeting") return Number.isFinite(meetingId) && meetingId > 0 ? `/meetings/${meetingId}` : "/meetings";
  if (t === "complaint") return "/complaints";
  if (t === "chain_head_approved") return "/leaves";
  if (t === "leave_request" || t.startsWith("leave")) return "/leaves";
  if (t.startsWith("request")) return "/requests";
  switch (t) {
    case "payslip": case "loan": return "/payroll";
    case "announcement": return "/announcements";
    case "document": case "employee_added": case "birthday": case "promotion": return "/employees";
    case "shift_assigned": return "/shifts";
    case "late_checkin": case "left_zone": case "security_flag": case "reminder_checkin": case "reminder_checkout": return "/attendance";
    case "onboarding": return "/onboarding";
    case "kudos": return "/kudos";
    case "review": return "/reviews";
    case "department_head": return "/departments";
    case "points": case "reward": case "level_up": return "/rewards";
    default: return "/";
  }
}
