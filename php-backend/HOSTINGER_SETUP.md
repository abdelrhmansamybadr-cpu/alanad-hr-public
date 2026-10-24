# Hostinger Deployment Guide

## Step 1: Create MySQL Database

1. Log in to your **Hostinger hPanel**
2. Go to **Databases** → **MySQL Databases**
3. Create a new database (e.g., `u123456_hrdb`)
4. Create a database user with a strong password
5. Assign the user to the database with **All Privileges**
6. Note down:
   - Database host: `localhost`
   - Database name: `u123456_hrdb`
   - Database user: `u123456_hruser`
   - Database password: (your chosen password)

---

## Step 2: Import the Database Schema

1. Go to **Databases** → **phpMyAdmin**
2. Select your new database from the left sidebar
3. Click the **Import** tab
4. Click **Choose File** and select `database.sql` from this project
5. Click **Go** to import

This will create all tables and insert:
- Default admin user: `admin@company.com` / `admin123`
- Default leave policy: 2 days/month, 21 days/year
- Default document types

**Important:** Change the admin password immediately after first login.

---

## Step 3: Configure Database Credentials

Open `config/database.php` and update these four lines:

```php
define('DB_HOST', 'localhost');
define('DB_NAME', 'u123456_hrdb');      // your database name
define('DB_USER', 'u123456_hruser');    // your database username
define('DB_PASS', 'YourStrongPass123'); // your database password
```

---

## Step 4: Upload Files to Hostinger

### Option A: Upload to root (yourdomain.com/api/)
1. In hPanel, go to **Files** → **File Manager**
2. Navigate to `public_html/`
3. Create a folder named `api`
4. Upload all PHP backend files into `public_html/api/`

Your API URL will be: `https://yourdomain.com/api/`

### Option B: Upload to root (yourdomain.com/)
1. Upload all files directly into `public_html/`

Your API URL will be: `https://yourdomain.com/`

### Using FTP (Recommended for bulk upload)
1. In hPanel, go to **Files** → **FTP Accounts**
2. Note your FTP credentials
3. Use FileZilla or similar client to connect
4. Upload the entire `php-backend/` contents to your chosen folder

---

## Step 5: Set Directory Permissions

The `uploads/` directory must be writable by the web server:

1. In **File Manager**, right-click the `uploads/` folder
2. Select **Change Permissions**
3. Set to `755` (or `775` if needed)

Alternatively via SSH:
```bash
chmod 755 public_html/api/uploads/
chmod 755 public_html/api/uploads/employees/
```

---

## Step 6: Verify the .htaccess

Make sure `.htaccess` is uploaded (it's a hidden file — enable "Show Hidden Files" in File Manager).

The `.htaccess` file handles URL rewriting so all requests go through `index.php`.

If you uploaded to a subdirectory (e.g., `/api/`), you may need to add `RewriteBase /api/` to the `.htaccess`:

```apache
RewriteEngine On
RewriteBase /api/
...
```

---

## Step 7: Test the API

Open your browser or use a tool like Postman:

```
GET https://yourdomain.com/api/health
```

Expected response:
```json
{
  "status": "ok",
  "timestamp": "2025-01-01 12:00:00",
  "version": "1.0.0"
}
```

---

## Step 8: Test Login

```
POST https://yourdomain.com/api/auth/login
Content-Type: application/json

{
  "email": "admin@company.com",
  "password": "admin123"
}
```

You should receive a `token` in the response. Use this token in subsequent requests:
```
Authorization: Bearer <your-token>
```

**Change the default password immediately after first login.**

---

## Step 9: Update the Flutter App

In your Flutter app, change the base URL to point to your Hostinger server:

```dart
// lib/services/api_service.dart (or wherever your base URL is set)
const String baseUrl = 'https://yourdomain.com/api';
```

---

## Troubleshooting

### 500 Internal Server Error
- Check PHP error logs in hPanel → **Advanced** → **Error Logs**
- Verify database credentials in `config/database.php`
- Ensure PHP version is 7.4 or higher (8.0+ recommended)

### 404 Not Found on all routes
- Ensure `.htaccess` is uploaded
- Check that `mod_rewrite` is enabled (it is on Hostinger by default)
- If in a subdirectory, add `RewriteBase /subdirectory/` to `.htaccess`

### CORS Errors from Flutter app
- The `index.php` sets `Access-Control-Allow-Origin: *` — this should work
- If issues persist, check that `.htaccess` isn't overriding headers

### File Upload Issues
- Ensure `uploads/` directory exists and is writable (chmod 755)
- Check `post_max_size` and `upload_max_filesize` in PHP settings
- Hostinger allows these to be set in `.htaccess` (already configured to 20MB)

### Database Connection Failed
- Double-check DB_HOST, DB_NAME, DB_USER, DB_PASS in `config/database.php`
- On Hostinger, the host is usually `localhost`
- Ensure the database user has privileges on the database

---

## File Structure

```
public_html/api/          (or public_html/ if at root)
├── .htaccess
├── index.php             ← Main router
├── database.sql          ← Import this via phpMyAdmin
├── HOSTINGER_SETUP.md    ← This file
├── config/
│   └── database.php      ← Edit DB credentials here
├── helpers/
│   ├── response.php
│   └── auth.php
├── api/
│   ├── auth.php
│   ├── employees.php
│   ├── departments.php
│   ├── leaves.php
│   ├── attendance.php
│   ├── attendance_rules.php
│   ├── payroll.php
│   ├── recruitment.php
│   ├── talent_pool.php
│   ├── reviews.php
│   ├── announcements.php
│   ├── documents.php
│   ├── shifts.php
│   ├── hr_staff.php
│   └── stats.php
└── uploads/              ← Employee documents stored here
    └── employees/
        └── {employee_id}/
```

---

## API Endpoint Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /health | Health check |
| POST | /auth/login | HR admin/manager login |
| POST | /auth/register | Register new HR staff |
| GET | /auth/me | Get current user |
| POST | /auth/logout | Logout |
| PUT | /auth/profile | Update profile |
| PUT | /auth/password | Change password |
| POST | /auth/employee/check-email | Check employee email |
| POST | /auth/employee/activate | Activate employee account |
| POST | /auth/employee/login | Employee login |
| POST | /auth/employee/forgot-password | Request password reset |
| POST | /auth/employee/reset-password | Reset password |
| GET | /employees | List employees |
| POST | /employees | Create employee |
| GET | /employees/me | My employee record |
| GET | /employees/:id | Get employee |
| PUT | /employees/:id | Update employee |
| DELETE | /employees/:id | Deactivate employee |
| GET | /departments | List departments |
| POST | /departments | Create department |
| GET | /leaves | List leaves |
| POST | /leaves | Create leave request |
| PUT | /leaves/:id | Update leave |
| GET | /leaves/policy | Get leave policy |
| PUT | /leaves/policy | Update leave policy |
| GET | /leaves/analytics | Leave analytics |
| GET | /attendance | List attendance |
| POST | /attendance | Create attendance |
| PUT | /attendance/:id | Update attendance |
| DELETE | /attendance/:id | Delete attendance |
| GET | /attendance-rules | List rules |
| GET | /attendance-rules/active | Get active rule |
| POST | /attendance-rules | Create rule |
| PUT | /attendance-rules/:id | Update rule |
| DELETE | /attendance-rules/:id | Delete rule |
| GET | /payroll | List payroll |
| POST | /payroll | Create payroll |
| PUT | /payroll/:id | Update payroll |
| GET | /jobs | List jobs |
| POST | /jobs | Create job |
| PUT | /jobs/:id | Update job |
| DELETE | /jobs/:id | Close job |
| GET | /applications | List applications |
| POST | /applications | Submit application |
| PUT | /applications/:id | Update application |
| GET | /talent-pool/overview | Talent pool overview |
| GET | /talent-pool/candidates | List talent pool |
| POST | /talent-pool/archive | Archive candidate |
| GET | /reviews | List reviews |
| POST | /reviews | Create review |
| PUT | /reviews/:id | Update review |
| GET | /announcements | List announcements |
| POST | /announcements | Create announcement |
| DELETE | /announcements/:id | Delete announcement |
| GET | /documents/types | List document types |
| POST | /documents/types | Create document type |
| PUT | /documents/types/:id | Update document type |
| DELETE | /documents/types/:id | Delete document type |
| GET | /documents/:employeeId | List employee documents |
| POST | /documents/:employeeId/:typeId | Upload document |
| GET | /shifts | List shifts |
| POST | /shifts | Create shift |
| PUT | /shifts/:id | Update shift |
| DELETE | /shifts/:id | Delete shift |
| POST | /shifts/assign | Assign shift to employee |
| DELETE | /shifts/assign/:employeeId | Remove shift assignment |
| GET | /hr-staff | List HR staff |
| POST | /hr-staff | Create HR staff |
| PUT | /hr-staff/:id | Update HR staff |
| DELETE | /hr-staff/:id | Delete HR staff |
| GET | /stats | Dashboard statistics |
