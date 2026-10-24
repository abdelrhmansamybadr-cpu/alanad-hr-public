import { pgTable, serial, text, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const reviewsTable = pgTable("reviews", {
  id: serial("id").primaryKey(),
  employeeId: integer("employee_id").notNull(),
  reviewerId: integer("reviewer_id"),
  period: text("period").notNull(),
  rating: integer("rating").notNull(),
  goals: text("goals"),
  achievements: text("achievements"),
  feedback: text("feedback"),
  status: text("status").notNull().default("draft"),
  reviewedAt: text("reviewed_at").notNull(),
});

export const insertReviewSchema = createInsertSchema(reviewsTable).omit({
  id: true,
});
export type InsertReview = z.infer<typeof insertReviewSchema>;
export type Review = typeof reviewsTable.$inferSelect;
