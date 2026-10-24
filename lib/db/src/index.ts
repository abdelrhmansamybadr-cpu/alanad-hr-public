import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import * as schema from "./schema";
import path from "path";
import crypto from "crypto";

const dataDir = path.resolve(process.cwd(), ".pgdata");
const client = new PGlite(dataDir);
export const db = drizzle(client, { schema });

const CREATE_TABLES_SQL = `
CREATE TABLE IF NOT EXISTS departments (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  manager_id INTEGER
);

CREATE TABLE IF NOT EXISTS employees (
  id SERIAL PRIMARY KEY,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  position TEXT NOT NULL,
  department_id INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  start_date TEXT NOT NULL,
  salary NUMERIC,
  avatar TEXT
);

CREATE TABLE IF NOT EXISTS leaves (
  id SERIAL PRIMARY KEY,
  employee_id INTEGER NOT NULL,
  type TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  days INTEGER NOT NULL DEFAULT 1,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS jobs (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  department_id INTEGER NOT NULL,
  location TEXT NOT NULL,
  type TEXT NOT NULL,
  description TEXT NOT NULL,
  requirements TEXT,
  salary TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  posted_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS applications (
  id SERIAL PRIMARY KEY,
  job_id INTEGER NOT NULL,
  applicant_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  resume_url TEXT,
  cover_letter TEXT,
  status TEXT NOT NULL DEFAULT 'new',
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reviews (
  id SERIAL PRIMARY KEY,
  employee_id INTEGER NOT NULL,
  reviewer_id INTEGER,
  period TEXT NOT NULL,
  rating INTEGER NOT NULL,
  goals TEXT,
  achievements TEXT,
  feedback TEXT,
  status TEXT NOT NULL DEFAULT 'draft',
  reviewed_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS payroll (
  id SERIAL PRIMARY KEY,
  employee_id INTEGER NOT NULL,
  month TEXT NOT NULL,
  year TEXT NOT NULL DEFAULT '',
  base_salary NUMERIC NOT NULL,
  bonus NUMERIC NOT NULL DEFAULT 0,
  deductions NUMERIC NOT NULL DEFAULT 0,
  net_pay NUMERIC NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  paid_at TEXT,
  created_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS announcements (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  author_id INTEGER,
  author_name TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'medium',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS attendance (
  id SERIAL PRIMARY KEY,
  employee_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  check_in TEXT,
  check_out TEXT,
  status TEXT NOT NULL DEFAULT 'present',
  hours_worked NUMERIC
);

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'hr_admin',
  avatar TEXT,
  title TEXT,
  phone TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS shifts (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT 'blue',
  description TEXT,
  days TEXT NOT NULL DEFAULT 'mon,tue,wed,thu,fri',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS employee_shifts (
  id SERIAL PRIMARY KEY,
  employee_id INTEGER NOT NULL,
  shift_id INTEGER NOT NULL,
  assigned_at TEXT NOT NULL,
  UNIQUE(employee_id)
);

CREATE TABLE IF NOT EXISTS webauthn_credentials (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL,
  credential_id TEXT NOT NULL UNIQUE,
  public_key TEXT NOT NULL,
  counter INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS required_document_types (
  id SERIAL PRIMARY KEY,
  label TEXT NOT NULL,
  order_num INTEGER NOT NULL DEFAULT 0,
  created_at TEXT
);

CREATE TABLE IF NOT EXISTS employee_documents (
  id SERIAL PRIMARY KEY,
  employee_id INTEGER NOT NULL,
  document_type_id INTEGER NOT NULL,
  file_name TEXT,
  file_path TEXT,
  mime_type TEXT,
  uploaded_at TEXT
);

CREATE TABLE IF NOT EXISTS candidate_documents (
  id SERIAL PRIMARY KEY,
  application_id INTEGER NOT NULL,
  file_name TEXT,
  file_path TEXT,
  mime_type TEXT,
  uploaded_at TEXT
);

CREATE TABLE IF NOT EXISTS leave_policy (
  id SERIAL PRIMARY KEY,
  days_per_month INTEGER NOT NULL DEFAULT 2,
  days_per_year INTEGER NOT NULL DEFAULT 21,
  updated_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS user_permissions (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL,
  module TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT true,
  UNIQUE(user_id, module)
);
`;

const SEED_SQL = `
INSERT INTO departments (name, description) VALUES
  ('Engineering', 'Software development and infrastructure'),
  ('Human Resources', 'People operations and culture'),
  ('Sales', 'Revenue generation and client relations'),
  ('Marketing', 'Brand, content and growth'),
  ('Finance', 'Financial planning and accounting'),
  ('Operations', 'Business operations and logistics')
ON CONFLICT DO NOTHING;

INSERT INTO employees (first_name, last_name, email, phone, position, department_id, status, start_date, salary) VALUES
  ('Sarah', 'Jenkins', 'sarah.jenkins@hrportal.com', '+1-555-0101', 'Senior Software Engineer', 1, 'active', '2021-03-15', 95000),
  ('Michael', 'Chen', 'michael.chen@hrportal.com', '+1-555-0102', 'Product Manager', 1, 'on_leave', '2020-07-01', 105000),
  ('Emily', 'Rodriguez', 'emily.rodriguez@hrportal.com', '+1-555-0103', 'UX Designer', 4, 'active', '2022-01-10', 82000),
  ('James', 'Wilson', 'james.wilson@hrportal.com', '+1-555-0104', 'Sales Executive', 3, 'active', '2021-09-05', 75000),
  ('Aisha', 'Patel', 'aisha.patel@hrportal.com', '+1-555-0105', 'HR Manager', 2, 'active', '2019-11-20', 88000),
  ('Carlos', 'Gomez', 'carlos.gomez@hrportal.com', '+1-555-0106', 'DevOps Engineer', 1, 'active', '2022-05-01', 90000),
  ('Mia', 'Thompson', 'mia.thompson@hrportal.com', '+1-555-0107', 'Marketing Specialist', 4, 'active', '2023-02-14', 68000),
  ('Daniel', 'Kim', 'daniel.kim@hrportal.com', '+1-555-0108', 'Financial Analyst', 5, 'active', '2020-08-15', 80000),
  ('Priya', 'Sharma', 'priya.sharma@hrportal.com', '+1-555-0109', 'Backend Engineer', 1, 'active', '2021-06-01', 92000),
  ('Tom', 'Brown', 'tom.brown@hrportal.com', '+1-555-0110', 'Sales Manager', 3, 'terminated', '2018-04-10', 98000)
ON CONFLICT (email) DO NOTHING;

INSERT INTO leaves (employee_id, type, start_date, end_date, days, reason, status) VALUES
  (2, 'annual', '2025-04-01', '2025-04-10', 10, 'Family vacation', 'approved'),
  (3, 'sick', '2025-03-25', '2025-03-26', 2, 'Flu', 'approved'),
  (4, 'annual', '2025-05-05', '2025-05-09', 5, 'Personal trip', 'pending'),
  (1, 'maternity', '2025-06-01', '2025-08-30', 90, 'Maternity leave', 'pending'),
  (6, 'sick', '2025-03-20', '2025-03-20', 1, 'Doctor appointment', 'approved')
ON CONFLICT DO NOTHING;

INSERT INTO jobs (title, department_id, location, type, description, requirements, salary, status, posted_at) VALUES
  ('Frontend Engineer', 1, 'Remote', 'full-time', 'Build modern web UIs with React and TypeScript', 'React, TypeScript, 3+ years', '$80k-$110k', 'open', '2025-03-01'),
  ('Sales Representative', 3, 'New York', 'full-time', 'Drive revenue through client acquisition', 'CRM experience, communication skills', '$60k-$85k + commission', 'open', '2025-03-05'),
  ('Content Writer', 4, 'Remote', 'part-time', 'Create engaging content for our blog and social media', 'Writing, SEO, 2+ years', '$35k-$50k', 'open', '2025-03-10'),
  ('Data Analyst', 5, 'Chicago', 'full-time', 'Analyze business data and build dashboards', 'SQL, Excel, Python preferred', '$70k-$90k', 'closed', '2025-02-01')
ON CONFLICT DO NOTHING;

INSERT INTO applications (job_id, applicant_name, email, phone, status, applied_at) VALUES
  (1, 'Alex Turner', 'alex.turner@email.com', '+1-555-2001', 'new', '2025-03-15'),
  (1, 'Zoe Adams', 'zoe.adams@email.com', '+1-555-2002', 'interview', '2025-03-16'),
  (2, 'Ravi Gupta', 'ravi.gupta@email.com', '+1-555-2003', 'new', '2025-03-18'),
  (3, 'Lily Nguyen', 'lily.nguyen@email.com', '+1-555-2004', 'offered', '2025-03-12'),
  (1, 'Mark Spencer', 'mark.spencer@email.com', '+1-555-2005', 'rejected', '2025-03-10')
ON CONFLICT DO NOTHING;

INSERT INTO reviews (employee_id, reviewer_id, period, rating, goals, achievements, feedback, status, reviewed_at) VALUES
  (1, 5, 'Q4 2024', 5, 'Improve code quality, mentor juniors', 'Delivered 3 major features, mentored 2 engineers', 'Outstanding performance this quarter', 'completed', '2025-01-15'),
  (3, 5, 'Q4 2024', 4, 'Ship design system components', 'Completed 80% of design system', 'Great work on UX improvements', 'completed', '2025-01-18'),
  (4, 5, 'Q4 2024', 3, 'Hit quarterly sales target', 'Reached 90% of target', 'Good effort, focus on closing deals', 'completed', '2025-01-20'),
  (6, 5, 'Q1 2025', 4, 'Improve CI/CD pipelines', 'Reduced deployment time by 40%', 'Excellent technical contributions', 'draft', '2025-03-01')
ON CONFLICT DO NOTHING;

INSERT INTO payroll (employee_id, month, base_salary, bonus, deductions, net_pay, status, paid_at) VALUES
  (1, '2025-02', 95000, 5000, 12000, 88000, 'paid', '2025-02-28'),
  (2, '2025-02', 105000, 0, 13500, 91500, 'paid', '2025-02-28'),
  (3, '2025-02', 82000, 2000, 10500, 73500, 'paid', '2025-02-28'),
  (4, '2025-02', 75000, 8000, 9800, 73200, 'paid', '2025-02-28'),
  (5, '2025-02', 88000, 3000, 11400, 79600, 'paid', '2025-02-28'),
  (1, '2025-03', 95000, 0, 12000, 83000, 'pending', null),
  (2, '2025-03', 105000, 0, 13500, 91500, 'pending', null),
  (3, '2025-03', 82000, 0, 10500, 71500, 'pending', null)
ON CONFLICT DO NOTHING;

INSERT INTO announcements (title, content, author_name, priority, created_at) VALUES
  ('Q1 2025 All-Hands Meeting', 'Join us for the quarterly all-hands on April 5th at 10am. We will review Q1 results and share the roadmap ahead.', 'Aisha Patel', 'high', '2025-03-20'),
  ('New Health Benefits Package', 'We are excited to announce enhanced health benefits starting May 1st. Check your email for details.', 'Aisha Patel', 'high', '2025-03-15'),
  ('Office Renovation Notice', 'The 3rd floor will be renovated April 10-14. Please use floors 2 and 4 during this period.', 'Tom Brown', 'medium', '2025-03-10'),
  ('Happy Ramadan!', 'Wishing all our Muslim colleagues a blessed Ramadan Kareem.', 'Aisha Patel', 'low', '2025-03-01')
ON CONFLICT DO NOTHING;

INSERT INTO attendance (employee_id, date, check_in, check_out, status, hours_worked) VALUES
  (1, '2025-03-27', '09:02', '17:30', 'present', 8.5),
  (2, '2025-03-27', null, null, 'absent', 0),
  (3, '2025-03-27', '08:55', '17:10', 'present', 8.2),
  (4, '2025-03-27', '09:30', '14:00', 'half-day', 4.5),
  (5, '2025-03-27', '08:45', '17:45', 'present', 9),
  (6, '2025-03-27', '10:00', '18:00', 'present', 8),
  (1, '2025-03-28', '09:00', '17:30', 'present', 8.5),
  (3, '2025-03-28', '09:05', '17:15', 'present', 8.2),
  (5, '2025-03-28', '08:50', '18:00', 'present', 9.2)
ON CONFLICT DO NOTHING;

INSERT INTO shifts (name, start_time, end_time, color, description, days, created_at) VALUES
  ('Morning Shift', '08:00', '16:00', 'blue', 'Standard morning work hours', 'mon,tue,wed,thu,fri', '2024-01-01'),
  ('Evening Shift', '14:00', '22:00', 'purple', 'Afternoon to evening hours', 'mon,tue,wed,thu,fri', '2024-01-01'),
  ('Night Shift', '22:00', '06:00', 'indigo', 'Overnight work hours', 'mon,tue,wed,thu,fri,sat,sun', '2024-01-01')
ON CONFLICT DO NOTHING;

INSERT INTO employee_shifts (employee_id, shift_id, assigned_at) VALUES
  (1, 1, '2024-01-01'),
  (6, 1, '2024-01-01'),
  (9, 1, '2024-01-01'),
  (2, 2, '2024-01-01'),
  (3, 2, '2024-01-01'),
  (7, 2, '2024-01-01'),
  (8, 3, '2024-01-01')
ON CONFLICT (employee_id) DO NOTHING;

INSERT INTO required_document_types (label, order_num) VALUES
  ('اصل شهادة الميلاد', 1),
  ('اصل المؤهل الدراسي', 2),
  ('اصل شهادة الجيش', 3),
  ('صحيفة الحالة الجنائية "فيش جنائي حديث"', 4),
  ('عدد 8 صور شخصية', 5),
  ('عدد 4 صور من البطاقة الشخصية', 6),
  ('كعب عمل', 7),
  ('شهادة قياس المهارات للفنيين', 8),
  ('برنت تأمينات "غير مؤمن عليه"', 9),
  ('نموذج الكشف الطبي 111 تأمين صحي', 10)
ON CONFLICT DO NOTHING;

INSERT INTO leave_policy (id, days_per_month, days_per_year, updated_at) VALUES
  (1, 2, 21, '')
ON CONFLICT (id) DO NOTHING;
`;

export async function initDb(): Promise<void> {
  await client.waitReady;
  await client.exec(CREATE_TABLES_SQL);

  // Ensure unique index exists on users.email (may be missing if table was created early)
  await client.exec(
    `CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique ON users(email)`,
  );

  // Add notes column if it doesn't exist
  await client.exec(
    `ALTER TABLE applications ADD COLUMN IF NOT EXISTS notes TEXT`,
  );

  // Make job_id nullable and add direct talent bank columns
  await client.exec(
    `ALTER TABLE applications ALTER COLUMN job_id DROP NOT NULL`,
  );
  await client.exec(
    `ALTER TABLE applications ADD COLUMN IF NOT EXISTS direct_department_id INTEGER`,
  );
  await client.exec(
    `ALTER TABLE applications ADD COLUMN IF NOT EXISTS direct_job_title TEXT`,
  );

  // Add missing columns for leaves (Drizzle schema has these, old DB tables may not)
  await client.exec(
    `ALTER TABLE leaves ADD COLUMN IF NOT EXISTS created_at TEXT NOT NULL DEFAULT ''`,
  );

  // Add missing columns for payroll
  await client.exec(
    `ALTER TABLE payroll ADD COLUMN IF NOT EXISTS year TEXT NOT NULL DEFAULT ''`,
  );
  await client.exec(
    `ALTER TABLE payroll ADD COLUMN IF NOT EXISTS created_at TEXT NOT NULL DEFAULT ''`,
  );

  // Add status and created_by columns to users if not exist
  await client.exec(
    `ALTER TABLE users ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'`,
  );
  await client.exec(
    `ALTER TABLE users ADD COLUMN IF NOT EXISTS created_by INTEGER`,
  );

  // Migrate existing hr_admin to hr_manager
  await client.exec(
    `UPDATE users SET role = 'hr_manager' WHERE role = 'hr_admin'`,
  );

  // Ensure default manager exists with proper status
  const managerResult = await client.query<{ id: number }>(
    "SELECT id FROM users WHERE role = 'hr_manager' LIMIT 1",
  );
  if (managerResult.rows.length === 0) {
    // Create default manager if none exists
    await client.exec(
      `INSERT INTO users (name, email, password_hash, role, status, created_at)
       VALUES ('HR Manager', 'admin@hrportal.com', '${crypto.createHash("sha256").update("admin123").digest("hex")}', 'hr_manager', 'active', '${new Date().toISOString()}')`,
    );
  } else {
    // Ensure existing manager has active status
    await client.exec(
      `UPDATE users SET status = 'active' WHERE role = 'hr_manager'`,
    );
  }

  // Add shift_id column to employees if not exists (employee mobile app)
  await client.exec(
    `ALTER TABLE employees ADD COLUMN IF NOT EXISTS shift_id INTEGER`,
  );

  // Add employee_id column to users if not exists (employee mobile app)
  await client.exec(
    `ALTER TABLE users ADD COLUMN IF NOT EXISTS employee_id INTEGER`,
  );

  // Create attendance_rules table if not exists (employee mobile app)
  await client.exec(`
    CREATE TABLE IF NOT EXISTS attendance_rules (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      location_enabled BOOLEAN NOT NULL DEFAULT false,
      location_lat NUMERIC,
      location_lng NUMERIC,
      location_radius_km NUMERIC,
      wifi_enabled BOOLEAN NOT NULL DEFAULT false,
      wifi_ssid TEXT,
      is_active BOOLEAN NOT NULL DEFAULT true,
      created_at TEXT NOT NULL
    )
  `);

  // Seed departments/employees/etc only if fresh
  const deptResult = await client.query<{ count: string }>(
    "SELECT COUNT(*)::text AS count FROM departments",
  );
  const deptCount = parseInt(deptResult.rows[0]?.count ?? "0", 10);
  if (deptCount === 0) {
    await client.exec(SEED_SQL);
  }

  // Seed default leave policy if not exists
  await client.exec(
    `INSERT INTO leave_policy (id, days_per_month, days_per_year, updated_at)
     VALUES (1, 2, 21, '')
     ON CONFLICT (id) DO NOTHING`,
  );
}

// Called from api-server after initDb() — needs crypto which is only in the server
export { client as pgClient };

export * from "./schema";
