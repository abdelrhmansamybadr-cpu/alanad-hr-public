import { pgTable, serial, text, integer } from "drizzle-orm/pg-core";

export const usersTable = pgTable("users", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  role: text("role").notNull().default("hr_admin"),
  avatar: text("avatar"),
  title: text("title"),
  phone: text("phone"),
  createdAt: text("created_at").notNull(),
  status: text("status").notNull().default("active"),
  createdBy: integer("created_by"),
  employeeId: integer("employee_id"),
});

export type User = typeof usersTable.$inferSelect;
