import { pgTable, serial, text, integer, numeric } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const departmentsTable = pgTable("departments", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  description: text("description"),
  managerId: integer("manager_id"),
});

export const insertDepartmentSchema = createInsertSchema(departmentsTable).omit(
  { id: true },
);
export type InsertDepartment = z.infer<typeof insertDepartmentSchema>;
export type Department = typeof departmentsTable.$inferSelect;

export const employeesTable = pgTable("employees", {
  id: serial("id").primaryKey(),
  firstName: text("first_name").notNull(),
  lastName: text("last_name").notNull(),
  email: text("email").notNull().unique(),
  phone: text("phone"),
  position: text("position").notNull(),
  departmentId: integer("department_id").notNull(),
  status: text("status").notNull().default("active"),
  startDate: text("start_date").notNull(),
  salary: numeric("salary"),
  avatar: text("avatar"),
  shiftId: integer("shift_id"),
});

export const insertEmployeeSchema = createInsertSchema(employeesTable).omit({
  id: true,
});
export type InsertEmployee = z.infer<typeof insertEmployeeSchema>;
export type Employee = typeof employeesTable.$inferSelect;
