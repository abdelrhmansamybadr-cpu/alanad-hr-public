import {
  pgTable,
  serial,
  text,
  integer,
  uniqueIndex,
} from "drizzle-orm/pg-core";

export const shiftsTable = pgTable("shifts", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  startTime: text("start_time").notNull(),
  endTime: text("end_time").notNull(),
  color: text("color").notNull().default("blue"),
  description: text("description"),
  days: text("days").notNull().default("mon,tue,wed,thu,fri"),
  createdAt: text("created_at").notNull(),
});

export const employeeShiftsTable = pgTable(
  "employee_shifts",
  {
    id: serial("id").primaryKey(),
    employeeId: integer("employee_id").notNull(),
    shiftId: integer("shift_id").notNull(),
    assignedAt: text("assigned_at").notNull(),
  },
  (t) => [uniqueIndex("employee_shifts_employee_id_unique").on(t.employeeId)],
);
