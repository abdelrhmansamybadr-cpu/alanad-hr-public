import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import {
  leavesTable,
  employeesTable,
  leavePolicyTable,
} from "@workspace/db/schema";
import { eq, and, sql } from "drizzle-orm";
import { CreateLeaveBody, UpdateLeaveBody } from "@workspace/api-zod";

const router: IRouter = Router();

function calcDays(start: string, end: string): number {
  const s = new Date(start);
  const e = new Date(end);
  const diff =
    Math.ceil((e.getTime() - s.getTime()) / (1000 * 60 * 60 * 24)) + 1;
  return Math.max(1, diff);
}

function currentWeekRange(): { start: string; end: string } {
  const now = new Date();
  const day = now.getDay();
  const monday = new Date(now);
  monday.setDate(now.getDate() - ((day + 6) % 7));
  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  return {
    start: monday.toISOString().split("T")[0],
    end: sunday.toISOString().split("T")[0],
  };
}

function currentMonthRange(): { start: string; end: string } {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const lastDay = new Date(y, now.getMonth() + 1, 0).getDate();
  return { start: `${y}-${m}-01`, end: `${y}-${m}-${lastDay}` };
}

function currentYearRange(): { start: string; end: string } {
  const y = new Date().getFullYear();
  return { start: `${y}-01-01`, end: `${y}-12-31` };
}

function daysInRange(
  leaves: { startDate: string; days: number }[],
  start: string,
  end: string,
): number {
  return leaves
    .filter((l) => l.startDate >= start && l.startDate <= end)
    .reduce((sum, l) => sum + l.days, 0);
}

// GET /api/leaves/policy
router.get("/policy", async (_req, res): Promise<void> => {
  try {
    const [policy] = await db
      .select()
      .from(leavePolicyTable)
      .where(eq(leavePolicyTable.id, 1));
    res.json(
      policy ?? { id: 1, daysPerMonth: 2, daysPerYear: 21, updatedAt: "" },
    );
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// PUT /api/leaves/policy — admin only
router.put("/policy", async (req, res): Promise<void> => {
  try {
    const { daysPerMonth, daysPerYear } = req.body ?? {};
    if (!daysPerMonth || !daysPerYear) {
      res.status(400).json({ error: "daysPerMonth and daysPerYear required" });
      return;
    }
    const [policy] = await db
      .update(leavePolicyTable)
      .set({
        daysPerMonth: Number(daysPerMonth),
        daysPerYear: Number(daysPerYear),
        updatedAt: new Date().toISOString(),
      })
      .where(eq(leavePolicyTable.id, 1))
      .returning();
    res.json(policy);
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /api/leaves/analytics
router.get("/analytics", async (_req, res): Promise<void> => {
  try {
    const employees = await db.select().from(employeesTable);
    const allLeaves = await db
      .select({
        id: leavesTable.id,
        employeeId: leavesTable.employeeId,
        type: leavesTable.type,
        startDate: leavesTable.startDate,
        endDate: leavesTable.endDate,
        days: leavesTable.days,
        status: leavesTable.status,
      })
      .from(leavesTable)
      .where(sql`${leavesTable.status} IN ('approved', 'pending')`);

    const week = currentWeekRange();
    const month = currentMonthRange();
    const year = currentYearRange();

    const [policy] = await db
      .select()
      .from(leavePolicyTable)
      .where(eq(leavePolicyTable.id, 1));
    const daysPerMonth = policy?.daysPerMonth ?? 2;
    const daysPerYear = policy?.daysPerYear ?? 21;

    const result = employees.map((emp) => {
      const empLeaves = allLeaves.filter((l) => l.employeeId === emp.id);
      const weekDays = daysInRange(empLeaves, week.start, week.end);
      const monthDays = daysInRange(empLeaves, month.start, month.end);
      const yearDays = daysInRange(empLeaves, year.start, year.end);
      const pending = empLeaves.filter((l) => l.status === "pending").length;
      return {
        employeeId: emp.id,
        firstName: emp.firstName,
        lastName: emp.lastName,
        position: emp.position,
        departmentId: emp.departmentId,
        status: emp.status,
        takenThisWeek: weekDays,
        takenThisMonth: monthDays,
        takenThisYear: yearDays,
        remainingThisMonth: Math.max(0, daysPerMonth - monthDays),
        remainingThisYear: Math.max(0, daysPerYear - yearDays),
        pendingRequests: pending,
      };
    });

    res.json(result);
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /api/leaves/analytics/:employeeId
router.get("/analytics/:employeeId", async (req, res): Promise<void> => {
  try {
    const empId = parseInt(req.params.employeeId);
    if (isNaN(empId)) {
      res.status(400).json({ error: "Invalid employeeId" });
      return;
    }

    const [emp] = await db
      .select()
      .from(employeesTable)
      .where(eq(employeesTable.id, empId));
    if (!emp) {
      res.status(404).json({ error: "Employee not found" });
      return;
    }

    const leaves = await db
      .select()
      .from(leavesTable)
      .where(eq(leavesTable.employeeId, empId));

    const week = currentWeekRange();
    const month = currentMonthRange();
    const year = currentYearRange();

    const approvedOrPending = leaves.filter(
      (l) => l.status === "approved" || l.status === "pending",
    );

    const [policy] = await db
      .select()
      .from(leavePolicyTable)
      .where(eq(leavePolicyTable.id, 1));
    const daysPerMonth = policy?.daysPerMonth ?? 2;
    const daysPerYear = policy?.daysPerYear ?? 21;

    res.json({
      employee: {
        id: emp.id,
        firstName: emp.firstName,
        lastName: emp.lastName,
        position: emp.position,
        departmentId: emp.departmentId,
        status: emp.status,
      },
      policy: { daysPerMonth, daysPerYear },
      summary: {
        takenThisWeek: daysInRange(approvedOrPending, week.start, week.end),
        takenThisMonth: daysInRange(approvedOrPending, month.start, month.end),
        takenThisYear: daysInRange(approvedOrPending, year.start, year.end),
        remainingThisMonth: Math.max(
          0,
          daysPerMonth - daysInRange(approvedOrPending, month.start, month.end),
        ),
        remainingThisYear: Math.max(
          0,
          daysPerYear - daysInRange(approvedOrPending, year.start, year.end),
        ),
        pendingRequests: leaves.filter((l) => l.status === "pending").length,
        totalAll: leaves.length,
      },
      history: leaves
        .sort((a, b) => b.startDate.localeCompare(a.startDate))
        .map((l) => ({
          id: l.id,
          type: l.type,
          startDate: l.startDate,
          endDate: l.endDate,
          days: l.days,
          reason: l.reason,
          status: l.status,
          createdAt: l.createdAt,
        })),
    });
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

router.get("/", async (req, res) => {
  const { employeeId, status } = req.query as {
    employeeId?: string;
    status?: string;
  };

  const leaves = await db
    .select({
      id: leavesTable.id,
      employeeId: leavesTable.employeeId,
      firstName: employeesTable.firstName,
      lastName: employeesTable.lastName,
      type: leavesTable.type,
      startDate: leavesTable.startDate,
      endDate: leavesTable.endDate,
      days: leavesTable.days,
      reason: leavesTable.reason,
      status: leavesTable.status,
    })
    .from(leavesTable)
    .leftJoin(employeesTable, eq(leavesTable.employeeId, employeesTable.id));

  let filtered = leaves;
  if (status) filtered = filtered.filter((l) => l.status === status);
  if (employeeId)
    filtered = filtered.filter((l) => l.employeeId === parseInt(employeeId));

  res.json(
    filtered.map((l) => ({
      id: l.id,
      employeeId: l.employeeId,
      employeeName: `${l.firstName ?? ""} ${l.lastName ?? ""}`.trim(),
      type: l.type,
      startDate: l.startDate,
      endDate: l.endDate,
      days: l.days,
      reason: l.reason,
      status: l.status,
    })),
  );
});

router.post("/", async (req, res) => {
  const body = CreateLeaveBody.parse(req.body);

  // Enforce leave policy limits
  const [policy] = await db
    .select()
    .from(leavePolicyTable)
    .where(eq(leavePolicyTable.id, 1));
  const daysPerMonth = policy?.daysPerMonth ?? 2;
  const daysPerYear = policy?.daysPerYear ?? 21;

  const newDays = calcDays(body.startDate, body.endDate);
  const month = currentMonthRange();
  const year = currentYearRange();

  const existingLeaves = await db
    .select({
      startDate: leavesTable.startDate,
      days: leavesTable.days,
      status: leavesTable.status,
    })
    .from(leavesTable)
    .where(
      and(
        eq(leavesTable.employeeId, body.employeeId),
        sql`${leavesTable.status} IN ('approved', 'pending')`,
      ),
    );

  const usedThisMonth = daysInRange(existingLeaves, month.start, month.end);
  const usedThisYear = daysInRange(existingLeaves, year.start, year.end);

  if (usedThisMonth + newDays > daysPerMonth) {
    res.status(422).json({
      error: `Monthly leave limit exceeded. Used: ${usedThisMonth}/${daysPerMonth} days this month.`,
      code: "MONTHLY_LIMIT_EXCEEDED",
      used: usedThisMonth,
      limit: daysPerMonth,
    });
    return;
  }
  if (usedThisYear + newDays > daysPerYear) {
    res.status(422).json({
      error: `Yearly leave limit exceeded. Used: ${usedThisYear}/${daysPerYear} days this year.`,
      code: "YEARLY_LIMIT_EXCEEDED",
      used: usedThisYear,
      limit: daysPerYear,
    });
    return;
  }

  const days = calcDays(body.startDate, body.endDate);
  const [leave] = await db
    .insert(leavesTable)
    .values({ ...body, days })
    .returning();

  const [emp] = await db
    .select({
      firstName: employeesTable.firstName,
      lastName: employeesTable.lastName,
    })
    .from(employeesTable)
    .where(eq(employeesTable.id, leave.employeeId));

  res.status(201).json({
    ...leave,
    employeeName: emp ? `${emp.firstName} ${emp.lastName}` : "Unknown",
  });
});

router.put("/:id", async (req, res): Promise<void> => {
  const id = parseInt(req.params.id);
  const body = UpdateLeaveBody.parse(req.body);
  const [leave] = await db
    .update(leavesTable)
    .set(body)
    .where(eq(leavesTable.id, id))
    .returning();
  if (!leave) {
    res.status(404).json({ error: "Not found" });
    return;
  }

  const [emp] = await db
    .select({
      firstName: employeesTable.firstName,
      lastName: employeesTable.lastName,
    })
    .from(employeesTable)
    .where(eq(employeesTable.id, leave.employeeId));

  res.json({
    ...leave,
    employeeName: emp ? `${emp.firstName} ${emp.lastName}` : "Unknown",
  });
});

export default router;
