import { pgTable, serial, text, integer, numeric } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const payrollTable = pgTable("payroll", {
  id: serial("id").primaryKey(),
  employeeId: integer("employee_id").notNull(),
  month: text("month").notNull(),
  year: text("year").notNull(),
  baseSalary: numeric("base_salary").notNull(),
  bonus: numeric("bonus").notNull().default("0"),
  deductions: numeric("deductions").notNull().default("0"),
  netPay: numeric("net_pay").notNull(),
  status: text("status").notNull().default("pending"),
  paidAt: text("paid_at"),
  createdAt: text("created_at")
    .notNull()
    .$defaultFn(() => new Date().toISOString()),
});

export const insertPayrollSchema = createInsertSchema(payrollTable).omit({
  id: true,
});
export type InsertPayroll = z.infer<typeof insertPayrollSchema>;
export type Payroll = typeof payrollTable.$inferSelect;
