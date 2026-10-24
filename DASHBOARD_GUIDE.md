# NexusHR Dashboard Guide

## Overview

The Dashboard is the first screen you see after logging in. It gives you a real-time snapshot of your organization's HR status at a glance.

---

## Section 1: Greeting & Date (Top Header)

**What it shows:** Your name, a time-appropriate greeting (Good morning / afternoon / evening), and today's full date.
**Why it exists:** Provides a personalized welcome and confirms the current date.
**Data source:** User name from your login session. Date from your device's clock.

---

## Section 2: KPI Cards (8 metric tiles)

Each card is clickable and navigates to the relevant module.

| Card             | What it means                                     | How calculated                    | Navigates to |
| ---------------- | ------------------------------------------------- | --------------------------------- | ------------ |
| Total Employees  | All employee records in system                    | COUNT all employees               | /employees   |
| Active Employees | Staff currently working (not terminated/on leave) | COUNT where status = 'active'     | /employees   |
| On Leave         | Staff with approved leave status                  | COUNT where status = 'on_leave'   | /leaves      |
| Open Positions   | Jobs currently accepting applications             | COUNT where status = 'open'       | /recruitment |
| Pending Leaves   | Leave requests awaiting approval                  | COUNT where status = 'pending'    | /leaves      |
| New Applications | Job applications not yet reviewed                 | COUNT where status = 'new'        | /recruitment |
| Upcoming Reviews | Performance reviews in draft state                | COUNT where status = 'draft'      | /reviews     |
| Total Payroll    | Sum of all paid payroll net amounts               | SUM net_pay where status = 'paid' | /payroll     |

---

## Section 3: Recent Activity Feed (left panel, middle row)

**What it shows:** The 10 most recent HR events across leaves, job applications, announcements, and payroll.
**Why it exists:** Lets HR managers quickly see what's happened recently without visiting each module.
**Data source:** `/api/stats/activity` — queries the last 5 leaves, 5 applications, 3 announcements, 3 payroll records, sorted by date descending.
**Status badges:** Color-coded — yellow=pending/draft, green=approved/paid, red=rejected, blue=new.
**"View all" button:** Navigates to the Leaves module.

---

## Section 4: Company News (right panel, middle row)

**What it shows:** The 3 most recent company announcements with title, priority badge, summary, and date.
**Why it exists:** Keeps staff informed of important company communications from a single place.
**Data source:** `/api/announcements` — returns all announcements sorted by date.
**Clicking a card:** Navigates to the full Announcements page.
**Priority colors:** HIGH = orange, URGENT = red, others = blue.

---

## Section 5: Quick Stats (3 bottom cards)

| Card             | What it means                                   | How calculated                                       |
| ---------------- | ----------------------------------------------- | ---------------------------------------------------- |
| Departments      | Total number of active departments              | COUNT all departments                                |
| Attendance Today | % of employees marked present or half-day today | (present + half-day today) ÷ total employees × 100   |
| Talent Pool      | Total candidates archived in the talent pool    | SUM of talent_pool status candidates across all jobs |

**Attendance Today** uses real check-in data from the Attendance module. If no attendance has been recorded today, it shows 0%.

---

## Data Refresh

- Dashboard stats refresh automatically every time you load the page.
- Recent activity refreshes every 60 seconds automatically.
- To force a refresh, reload the browser page (F5).

---

## Common Questions

**Q: Why does Attendance Today show 0%?**
A: No attendance records have been entered for today yet. Go to the Attendance module to record check-ins.

**Q: Why does Total Payroll only count some employees?**
A: It only sums payroll records with status "paid". Pending payroll is not included.

**Q: What is the Talent Pool count?**
A: Candidates who applied for jobs and were moved to the talent pool (archived for future consideration) instead of being hired or rejected.

**Q: Can I click the KPI cards?**
A: Yes — all 8 KPI cards are clickable and navigate directly to the relevant module.

---

## For Non-Technical Admins

- All numbers on the dashboard update from the real database — there is no fake/sample data.
- Numbers will be 0 if no records have been added yet.
- The system uses Arabic or English based on your language preference (toggle in the top-right corner).
