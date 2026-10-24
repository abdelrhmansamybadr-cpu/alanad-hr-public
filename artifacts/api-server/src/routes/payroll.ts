import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { payrollTable, employeesTable } from "@workspace/db/schema";
import { eq } from "drizzle-orm";
import { CreatePayrollBody } from "@workspace/api-zod";

const router: IRouter = Router();

async function enrichRecord(p: typeof payrollTable.$inferSelect) {
  const [emp] = await db
    .select({
      firstName: employeesTable.firstName,
      lastName: employeesTable.lastName,
    })
    .from(employeesTable)
    .where(eq(employeesTable.id, p.employeeId));
  return {
    ...p,
    employeeName: emp ? `${emp.firstName} ${emp.lastName}` : "Unknown",
    baseSalary: parseFloat(p.baseSalary),
    bonus: parseFloat(p.bonus ?? "0"),
    deductions: parseFloat(p.deductions ?? "0"),
    netPay: parseFloat(p.netPay),
  };
}

router.get("/", async (req, res) => {
  const { employeeId, month } = req.query as {
    employeeId?: string;
    month?: string;
  };

  const records = await db.select().from(payrollTable);
  const enriched = await Promise.all(records.map(enrichRecord));

  let filtered = enriched;
  if (employeeId)
    filtered = filtered.filter((p) => p.employeeId === parseInt(employeeId));
  if (month) filtered = filtered.filter((p) => p.month === month);

  res.json(filtered);
});

router.post("/", async (req, res) => {
  const body = CreatePayrollBody.parse(req.body);
  const netPay = body.baseSalary + (body.bonus ?? 0) - (body.deductions ?? 0);
  const [record] = await db
    .insert(payrollTable)
    .values({
      employeeId: body.employeeId,
      month: body.month,
      year: body.year || new Date().getFullYear().toString(),
      baseSalary: body.baseSalary.toString(),
      bonus: (body.bonus ?? 0).toString(),
      deductions: (body.deductions ?? 0).toString(),
      netPay: netPay.toString(),
      status: "pending",
    })
    .returning();

  res.status(201).json(await enrichRecord(record));
});

router.put("/:id", async (req, res) => {
  const id = parseInt(req.params["id"] ?? "");
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid id" });
    return;
  }

  const { status, baseSalary, bonus, deductions, paidAt } = req.body as {
    status?: string;
    baseSalary?: number;
    bonus?: number;
    deductions?: number;
    paidAt?: string | null;
  };

  const updateData: Partial<typeof payrollTable.$inferInsert> = {};
  if (status !== undefined) updateData.status = status;
  if (paidAt !== undefined) updateData.paidAt = paidAt;
  if (baseSalary !== undefined) {
    const b = bonus !== undefined ? bonus : 0;
    const d = deductions !== undefined ? deductions : 0;
    updateData.baseSalary = baseSalary.toString();
    updateData.bonus = b.toString();
    updateData.deductions = d.toString();
    updateData.netPay = (baseSalary + b - d).toString();
  }

  const [updated] = await db
    .update(payrollTable)
    .set(updateData)
    .where(eq(payrollTable.id, id))
    .returning();

  if (!updated) {
    res.status(404).json({ error: "Not found" });
    return;
  }
  res.json(await enrichRecord(updated));
});

router.delete("/:id", async (req, res) => {
  const id = parseInt(req.params["id"] ?? "");
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid id" });
    return;
  }

  const [deleted] = await db
    .delete(payrollTable)
    .where(eq(payrollTable.id, id))
    .returning();
  if (!deleted) {
    res.status(404).json({ error: "Not found" });
    return;
  }
  res.json({ success: true });
});

export default router;
