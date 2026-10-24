import { pgTable, serial, integer, text } from "drizzle-orm/pg-core";

export const leavePolicyTable = pgTable("leave_policy", {
  id: serial("id").primaryKey(),
  daysPerMonth: integer("days_per_month").notNull().default(2),
  daysPerYear: integer("days_per_year").notNull().default(21),
  updatedAt: text("updated_at").notNull().default(""),
});
