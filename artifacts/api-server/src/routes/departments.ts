import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { departmentsTable, employeesTable } from "@workspace/db/schema";
import { eq, sql } from "drizzle-orm";
import { CreateDepartmentBody } from "@workspace/api-zod";

const router: IRouter = Router();

router.get("/", async (_req, res) => {
  const departments = await db.select().from(departmentsTable);
  const counts = await db
    .select({
      departmentId: employeesTable.departmentId,
      count: sql<number>`count(*)::int`,
    })
    .from(employeesTable)
    .groupBy(employeesTable.departmentId);

  const countMap = Object.fromEntries(counts.map((c) => [c.departmentId, c.count]));

  const result = await Promise.all(
    departments.map(async (dept) => {
      let managerName: string | null = null;
      if (dept.managerId) {
        const [mgr] = await db
          .select({ firstName: employeesTable.firstName, lastName: employeesTable.lastName })
          .from(employeesTable)
          .where(eq(employeesTable.id, dept.managerId));
        if (mgr) managerName = `${mgr.firstName} ${mgr.lastName}`;
      }
      return {
        ...dept,
        managerName,
        employeeCount: countMap[dept.id] ?? 0,
      };
    })
  );

  res.json(result);
});

router.post("/", async (req, res) => {
  const body = CreateDepartmentBody.parse(req.body);
  const [dept] = await db.insert(departmentsTable).values(body).returning();
  res.status(201).json({ ...dept, managerName: null, employeeCount: 0 });
});

export default router;
