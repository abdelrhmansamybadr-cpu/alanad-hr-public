import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { employeesTable, departmentsTable, shiftsTable, employeeShiftsTable, usersTable } from "@workspace/db/schema";
import { eq, sql } from "drizzle-orm";
import {
  CreateEmployeeBody,
  UpdateEmployeeBody,
} from "@workspace/api-zod";

const router: IRouter = Router();

router.get("/", async (req, res) => {
  const { department, status } = req.query as { department?: string; status?: string };

  const employees = await db
    .select({
      id: employeesTable.id,
      firstName: employeesTable.firstName,
      lastName: employeesTable.lastName,
      email: employeesTable.email,
      phone: employeesTable.phone,
      position: employeesTable.position,
      departmentId: employeesTable.departmentId,
      departmentName: departmentsTable.name,
      status: employeesTable.status,
      startDate: employeesTable.startDate,
      salary: employeesTable.salary,
      avatar: employeesTable.avatar,
    })
    .from(employeesTable)
    .leftJoin(departmentsTable, eq(employeesTable.departmentId, departmentsTable.id));

  let filtered = employees;
  if (status) filtered = filtered.filter((e) => e.status === status);
  if (department) filtered = filtered.filter((e) => e.departmentId === parseInt(department));

  res.json(filtered.map((e) => ({ ...e, salary: e.salary ? parseFloat(e.salary) : null })));
});

router.post("/", async (req, res): Promise<void> => {
  try {
    const body = CreateEmployeeBody.parse(req.body);
    const [employee] = await db.insert(employeesTable).values({
      ...body,
      salary: body.salary !== undefined ? String(body.salary) : undefined,
    }).returning();
    res.status(201).json({ ...employee, salary: employee.salary ? parseFloat(employee.salary) : null });
  } catch (err: any) {
    const msg: string = err?.message ?? "";
    if (msg.includes("unique") || msg.includes("duplicate") || msg.includes("email")) {
      res.status(409).json({ error: "An employee with this email already exists" });
    } else if (err?.name === "ZodError") {
      res.status(400).json({ error: "Invalid data", details: err.errors });
    } else {
      console.error("Create employee error:", err);
      res.status(500).json({ error: msg || "Failed to create employee" });
    }
  }
});

// GET /api/employees/me - MUST be before /:id so Express doesn't treat "me" as an id
router.get("/me", async (req, res): Promise<void> => {
  try {
    const authHeader = req.headers.authorization as string | undefined;
    if (!authHeader?.startsWith("Bearer ")) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
    const token = authHeader.slice(7);

    const { sessions } = await import("./auth");
    const userId = sessions.get(token);

    if (!userId) {
      res.status(401).json({ error: "Invalid or expired session" });
      return;
    }

    const [user] = await db
      .select({ employeeId: usersTable.employeeId })
      .from(usersTable)
      .where(eq(usersTable.id, userId));

    if (!user?.employeeId) {
      res.status(404).json({ error: "Employee profile not found" });
      return;
    }

    const [employee] = await db
      .select({
        id: employeesTable.id,
        firstName: employeesTable.firstName,
        lastName: employeesTable.lastName,
        email: employeesTable.email,
        phone: employeesTable.phone,
        position: employeesTable.position,
        departmentId: employeesTable.departmentId,
        departmentName: departmentsTable.name,
        status: employeesTable.status,
        startDate: employeesTable.startDate,
        salary: employeesTable.salary,
        avatar: employeesTable.avatar,
        shiftId: employeesTable.shiftId,
      })
      .from(employeesTable)
      .leftJoin(departmentsTable, eq(employeesTable.departmentId, departmentsTable.id))
      .where(eq(employeesTable.id, user.employeeId));

    if (!employee) {
      res.status(404).json({ error: "Employee not found" });
      return;
    }

    let shift = null;
    if (employee.shiftId) {
      const [shiftData] = await db
        .select()
        .from(shiftsTable)
        .where(eq(shiftsTable.id, employee.shiftId));
      if (shiftData) shift = shiftData;
    }

    res.json({
      ...employee,
      salary: employee.salary ? parseFloat(employee.salary) : null,
      shift,
    });
  } catch (err) {
    console.error("Get employee me error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.get("/:id", async (req, res): Promise<void> => {
  const id = parseInt(req.params.id);
  const [employee] = await db
    .select({
      id: employeesTable.id,
      firstName: employeesTable.firstName,
      lastName: employeesTable.lastName,
      email: employeesTable.email,
      phone: employeesTable.phone,
      position: employeesTable.position,
      departmentId: employeesTable.departmentId,
      departmentName: departmentsTable.name,
      status: employeesTable.status,
      startDate: employeesTable.startDate,
      salary: employeesTable.salary,
      avatar: employeesTable.avatar,
    })
    .from(employeesTable)
    .leftJoin(departmentsTable, eq(employeesTable.departmentId, departmentsTable.id))
    .where(eq(employeesTable.id, id));

  if (!employee) { res.status(404).json({ error: "Not found" }); return; }
  res.json({ ...employee, salary: employee.salary ? parseFloat(employee.salary) : null });
});

router.put("/:id", async (req, res): Promise<void> => {
  try {
    const id = parseInt(req.params.id);
    const body = UpdateEmployeeBody.parse(req.body);
    const [employee] = await db
      .update(employeesTable)
      .set({
        ...body,
        salary: body.salary !== undefined ? String(body.salary) : undefined,
      })
      .where(eq(employeesTable.id, id))
      .returning();
    if (!employee) { res.status(404).json({ error: "Not found" }); return; }
    res.json({ ...employee, salary: employee.salary ? parseFloat(employee.salary) : null });
  } catch (err: any) {
    const msg: string = err?.message ?? "";
    if (msg.includes("unique") || msg.includes("duplicate") || msg.includes("email")) {
      res.status(409).json({ error: "An employee with this email already exists" });
    } else if (err?.name === "ZodError") {
      res.status(400).json({ error: "Invalid data", details: err.errors });
    } else {
      console.error("Update employee error:", err);
      res.status(500).json({ error: msg || "Failed to update employee" });
    }
  }
});

router.delete("/:id", async (req, res) => {
  const id = parseInt(req.params.id);
  await db.delete(employeesTable).where(eq(employeesTable.id, id));
  res.status(204).end();
});

export default router;
