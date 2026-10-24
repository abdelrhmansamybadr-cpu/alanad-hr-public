import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { shiftsTable, employeeShiftsTable, employeesTable } from "@workspace/db/schema";
import { eq } from "drizzle-orm";

const router: IRouter = Router();

async function getShiftEmployees(shiftId: number) {
  const rows = await db
    .select({
      employeeId: employeeShiftsTable.employeeId,
      firstName: employeesTable.firstName,
      lastName: employeesTable.lastName,
      position: employeesTable.position,
      avatar: employeesTable.avatar,
    })
    .from(employeeShiftsTable)
    .leftJoin(employeesTable, eq(employeeShiftsTable.employeeId, employeesTable.id))
    .where(eq(employeeShiftsTable.shiftId, shiftId));

  return rows.map((r) => ({
    id: r.employeeId,
    firstName: r.firstName ?? "",
    lastName: r.lastName ?? "",
    position: r.position ?? "",
    avatar: r.avatar,
  }));
}

// GET /api/shifts
router.get("/", async (req, res) => {
  const shifts = await db.select().from(shiftsTable);
  const enriched = await Promise.all(
    shifts.map(async (s) => ({ ...s, employees: await getShiftEmployees(s.id) }))
  );
  res.json(enriched);
});

// POST /api/shifts
router.post("/", async (req, res) => {
  const { name, startTime, endTime, color, description, days } = req.body as {
    name: string; startTime: string; endTime: string;
    color?: string; description?: string; days: string;
  };
  if (!name || !startTime || !endTime || !days) {
    res.status(400).json({ error: "Missing required fields" }); return;
  }
  const [shift] = await db
    .insert(shiftsTable)
    .values({ name, startTime, endTime, color: color ?? "blue", description, days, createdAt: new Date().toISOString().split("T")[0] })
    .returning();
  res.status(201).json({ ...shift, employees: [] });
});

// PUT /api/shifts/:id
router.put("/:id", async (req, res) => {
  const id = parseInt(req.params["id"] ?? "");
  if (isNaN(id)) { res.status(400).json({ error: "Invalid id" }); return; }

  const { name, startTime, endTime, color, description, days } = req.body as {
    name?: string; startTime?: string; endTime?: string;
    color?: string; description?: string; days?: string;
  };
  const updateData: Partial<typeof shiftsTable.$inferInsert> = {};
  if (name !== undefined) updateData.name = name;
  if (startTime !== undefined) updateData.startTime = startTime;
  if (endTime !== undefined) updateData.endTime = endTime;
  if (color !== undefined) updateData.color = color;
  if (description !== undefined) updateData.description = description;
  if (days !== undefined) updateData.days = days;

  const [updated] = await db.update(shiftsTable).set(updateData).where(eq(shiftsTable.id, id)).returning();
  if (!updated) { res.status(404).json({ error: "Not found" }); return; }
  res.json({ ...updated, employees: await getShiftEmployees(updated.id) });
});

// DELETE /api/shifts/:id
router.delete("/:id", async (req, res) => {
  const id = parseInt(req.params["id"] ?? "");
  if (isNaN(id)) { res.status(400).json({ error: "Invalid id" }); return; }
  await db.delete(employeeShiftsTable).where(eq(employeeShiftsTable.shiftId, id));
  const [deleted] = await db.delete(shiftsTable).where(eq(shiftsTable.id, id)).returning();
  if (!deleted) { res.status(404).json({ error: "Not found" }); return; }
  res.json({ success: true });
});

// POST /api/shifts/assign
router.post("/assign", async (req, res) => {
  const { employeeId, shiftId } = req.body as { employeeId: number; shiftId: number };
  if (!employeeId || !shiftId) { res.status(400).json({ error: "Missing fields" }); return; }
  await db.delete(employeeShiftsTable).where(eq(employeeShiftsTable.employeeId, employeeId));
  await db.insert(employeeShiftsTable).values({ employeeId, shiftId, assignedAt: new Date().toISOString().split("T")[0] });
  res.json({ success: true });
});

// DELETE /api/shifts/assign/:employeeId
router.delete("/assign/:employeeId", async (req, res) => {
  const employeeId = parseInt(req.params["employeeId"] ?? "");
  if (isNaN(employeeId)) { res.status(400).json({ error: "Invalid id" }); return; }
  await db.delete(employeeShiftsTable).where(eq(employeeShiftsTable.employeeId, employeeId));
  res.json({ success: true });
});

export default router;
