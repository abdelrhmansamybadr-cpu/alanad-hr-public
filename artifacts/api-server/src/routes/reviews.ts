import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { reviewsTable, employeesTable } from "@workspace/db/schema";
import { eq } from "drizzle-orm";
import { CreateReviewBody } from "@workspace/api-zod";

const router: IRouter = Router();

router.get("/", async (req, res) => {
  const { employeeId } = req.query as { employeeId?: string };

  const reviews = await db.select().from(reviewsTable);

  const enriched = await Promise.all(
    reviews.map(async (r) => {
      const [emp] = await db
        .select({ firstName: employeesTable.firstName, lastName: employeesTable.lastName })
        .from(employeesTable)
        .where(eq(employeesTable.id, r.employeeId));

      let reviewerName: string | null = null;
      if (r.reviewerId) {
        const [rev] = await db
          .select({ firstName: employeesTable.firstName, lastName: employeesTable.lastName })
          .from(employeesTable)
          .where(eq(employeesTable.id, r.reviewerId));
        if (rev) reviewerName = `${rev.firstName} ${rev.lastName}`;
      }

      return {
        ...r,
        employeeName: emp ? `${emp.firstName} ${emp.lastName}` : "Unknown",
        reviewerName,
      };
    })
  );

  let filtered = enriched;
  if (employeeId) filtered = filtered.filter((r) => r.employeeId === parseInt(employeeId));

  res.json(filtered);
});

router.post("/", async (req, res) => {
  const body = CreateReviewBody.parse(req.body);
  const reviewedAt = new Date().toISOString().split("T")[0];
  const [review] = await db.insert(reviewsTable).values({ ...body, reviewedAt }).returning();

  const [emp] = await db
    .select({ firstName: employeesTable.firstName, lastName: employeesTable.lastName })
    .from(employeesTable)
    .where(eq(employeesTable.id, review.employeeId));

  res.status(201).json({
    ...review,
    employeeName: emp ? `${emp.firstName} ${emp.lastName}` : "Unknown",
    reviewerName: null,
  });
});

export default router;
