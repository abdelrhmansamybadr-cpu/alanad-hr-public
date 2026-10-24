import { pgTable, serial, text, boolean, numeric } from "drizzle-orm/pg-core";

export const attendanceRulesTable = pgTable("attendance_rules", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  locationEnabled: boolean("location_enabled").notNull().default(false),
  locationLat: numeric("location_lat"),
  locationLng: numeric("location_lng"),
  locationRadiusKm: numeric("location_radius_km"),
  wifiEnabled: boolean("wifi_enabled").notNull().default(false),
  wifiSsid: text("wifi_ssid"),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: text("created_at").notNull(),
});

export type AttendanceRule = typeof attendanceRulesTable.$inferSelect;
