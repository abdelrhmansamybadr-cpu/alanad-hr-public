import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import {
  employeesTable,
  jobsTable,
  leavesTable,
  applicationsTable,
  reviewsTable,
  payrollTable,
  announcementsTable,
  attendanceTable,
} from "@workspace/db/schema";
import { eq, sql, desc, inArray, and, or } from "drizzle-orm";

const router: IRouter = Router();

router.get("/", async (_req, res) => {
  const [totalEmp] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(employeesTable);
  const [activeEmp] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(employeesTable)
    .where(eq(employeesTable.status, "active"));
  const [onLeaveEmp] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(employeesTable)
    .where(eq(employeesTable.status, "on_leave"));
  const [openJobs] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(jobsTable)
    .where(eq(jobsTable.status, "open"));
  const [pendingLeaves] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(leavesTable)
    .where(eq(leavesTable.status, "pending"));
  const [newApps] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(applicationsTable)
    .where(eq(applicationsTable.status, "new"));
  const [upcomingReviews] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(reviewsTable)
    .where(eq(reviewsTable.status, "draft"));

  const payrollRecords = await db
    .select({ netPay: payrollTable.netPay })
    .from(payrollTable)
    .where(eq(payrollTable.status, "paid"));
  const totalPayroll = payrollRecords.reduce(
    (sum, r) => sum + parseFloat(r.netPay),
    0,
  );

  const todayDate = new Date().toISOString().split("T")[0];
  const [presentToday] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(attendanceTable)
    .where(
      and(
        eq(attendanceTable.date, todayDate),
        or(
          eq(attendanceTable.status, "present"),
          eq(attendanceTable.status, "half_day"),
        ),
      ),
    );

  res.json({
    totalEmployees: totalEmp.count,
    activeEmployees: activeEmp.count,
    onLeave: onLeaveEmp.count,
    openPositions: openJobs.count,
    pendingLeaves: pendingLeaves.count,
    newApplications: newApps.count,
    upcomingReviews: upcomingReviews.count,
    totalPayroll,
    todayAttendance: presentToday?.count ?? 0,
  });
});

interface ActivityItem {
  type: string;
  title: string;
  desc: string;
  status: string;
  date: string;
}

router.get("/activity", async (_req, res) => {
  const activities: ActivityItem[] = [];

  const recentLeaves = await db
    .select({
      id: leavesTable.id,
      employeeId: leavesTable.employeeId,
      type: leavesTable.type,
      status: leavesTable.status,
      createdAt: leavesTable.createdAt,
    })
    .from(leavesTable)
    .orderBy(desc(leavesTable.createdAt))
    .limit(5);

  const leaveEmployeeIds = recentLeaves
    .map((l) => l.employeeId)
    .filter((id): id is number => id != null);
  const leaveEmployees =
    leaveEmployeeIds.length > 0
      ? await db
          .select({
            id: employeesTable.id,
            firstName: employeesTable.firstName,
            lastName: employeesTable.lastName,
          })
          .from(employeesTable)
          .where(inArray(employeesTable.id, leaveEmployeeIds))
      : [];

  for (const leave of recentLeaves) {
    const emp = leaveEmployees.find((e) => e.id === leave.employeeId);
    const empName = emp
      ? `${emp.firstName} ${emp.lastName}`
      : `Employee #${leave.employeeId}`;
    activities.push({
      type: "leave",
      title: "Leave Request",
      desc: `${empName} - ${leave.type}`,
      status: leave.status,
      date: leave.createdAt || leave.type,
    });
  }

  const recentApplications = await db
    .select({
      id: applicationsTable.id,
      applicantName: applicationsTable.applicantName,
      jobId: applicationsTable.jobId,
      status: applicationsTable.status,
      appliedAt: applicationsTable.appliedAt,
    })
    .from(applicationsTable)
    .orderBy(desc(applicationsTable.appliedAt))
    .limit(5);

  const jobIds = recentApplications.map((a) => a.jobId).filter(Boolean);
  const jobs =
    jobIds.length > 0
      ? await db
          .select({ id: jobsTable.id, title: jobsTable.title })
          .from(jobsTable)
          .where(inArray(jobsTable.id, jobIds))
      : [];

  for (const app of recentApplications) {
    const job = jobs.find((j) => j.id === app.jobId);
    activities.push({
      type: "application",
      title: "New Application",
      desc: `${app.applicantName} - ${job?.title || "Unknown Job"}`,
      status: app.status,
      date: app.appliedAt,
    });
  }

  const recentAnnouncements = await db
    .select({
      id: announcementsTable.id,
      title: announcementsTable.title,
      priority: announcementsTable.priority,
      createdAt: announcementsTable.createdAt,
    })
    .from(announcementsTable)
    .orderBy(desc(announcementsTable.createdAt))
    .limit(3);

  for (const ann of recentAnnouncements) {
    activities.push({
      type: "announcement",
      title: "Announcement",
      desc: ann.title,
      status: ann.priority,
      date: ann.createdAt,
    });
  }

  const recentPayroll = await db
    .select({
      id: payrollTable.id,
      month: payrollTable.month,
      year: payrollTable.year,
      status: payrollTable.status,
      createdAt: payrollTable.createdAt,
      paidAt: payrollTable.paidAt,
    })
    .from(payrollTable)
    .orderBy(desc(payrollTable.createdAt))
    .limit(3);

  for (const pay of recentPayroll) {
    activities.push({
      type: "payroll",
      title: "Payroll",
      desc: pay.month,
      status: pay.status,
      date: pay.createdAt || pay.paidAt || "",
    });
  }

  activities.sort(
    (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime(),
  );
  const top10 = activities.slice(0, 10);

  res.json(top10);
});

export default router;
