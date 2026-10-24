-- HR Management System Database Schema
-- Import this file via phpMyAdmin

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Sessions table
CREATE TABLE IF NOT EXISTS `sessions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `token` VARCHAR(255) NOT NULL UNIQUE,
    `user_id` INT NOT NULL,
    `expires_at` DATETIME NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Users table
CREATE TABLE IF NOT EXISTS `users` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(255) NOT NULL,
    `email` VARCHAR(255) NOT NULL UNIQUE,
    `password_hash` VARCHAR(255) NOT NULL,
    `role` ENUM('hr_admin','hr_manager','employee') NOT NULL DEFAULT 'employee',
    `avatar` TEXT,
    `title` VARCHAR(255),
    `phone` VARCHAR(50),
    `status` ENUM('active','pending','suspended','disabled') NOT NULL DEFAULT 'active',
    `employee_id` INT NULL,
    `created_by` INT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- User permissions table
CREATE TABLE IF NOT EXISTS `user_permissions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL,
    `module` VARCHAR(100) NOT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY `unique_user_module` (`user_id`, `module`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Password reset tokens
CREATE TABLE IF NOT EXISTS `password_reset_tokens` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL,
    `token` VARCHAR(255) NOT NULL UNIQUE,
    `expires_at` DATETIME NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Departments table
CREATE TABLE IF NOT EXISTS `departments` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(255) NOT NULL,
    `description` TEXT,
    `manager_id` INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Shifts table
CREATE TABLE IF NOT EXISTS `shifts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(255) NOT NULL,
    `start_time` TIME NOT NULL,
    `end_time` TIME NOT NULL,
    `color` VARCHAR(50) NOT NULL DEFAULT '#3B82F6',
    `description` TEXT,
    `days` VARCHAR(100) NOT NULL DEFAULT 'mon,tue,wed,thu,fri',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Employees table
CREATE TABLE IF NOT EXISTS `employees` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `first_name` VARCHAR(100) NOT NULL,
    `last_name` VARCHAR(100) NOT NULL,
    `email` VARCHAR(255) NOT NULL UNIQUE,
    `phone` VARCHAR(50),
    `position` VARCHAR(255),
    `department_id` INT NULL,
    `shift_id` INT NULL,
    `status` ENUM('active','on_leave','inactive') NOT NULL DEFAULT 'active',
    `start_date` DATE,
    `salary` DECIMAL(10,2),
    `avatar` TEXT,
    CONSTRAINT `fk_employees_department` FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE SET NULL,
    CONSTRAINT `fk_employees_shift` FOREIGN KEY (`shift_id`) REFERENCES `shifts`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Employee shifts table (assignment)
CREATE TABLE IF NOT EXISTS `employee_shifts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `employee_id` INT NOT NULL UNIQUE,
    `shift_id` INT NOT NULL,
    `assigned_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_emp_shifts_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_emp_shifts_shift` FOREIGN KEY (`shift_id`) REFERENCES `shifts`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Attendance table
CREATE TABLE IF NOT EXISTS `attendance` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `employee_id` INT NOT NULL,
    `date` DATE NOT NULL,
    `check_in` TIME,
    `check_out` TIME,
    `status` ENUM('present','absent','half_day','late') NOT NULL DEFAULT 'present',
    `hours_worked` DECIMAL(5,2),
    CONSTRAINT `fk_attendance_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Attendance rules table
CREATE TABLE IF NOT EXISTS `attendance_rules` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(255) NOT NULL,
    `is_active` TINYINT(1) NOT NULL DEFAULT 0,
    `location_enabled` TINYINT(1) NOT NULL DEFAULT 0,
    `location_lat` DECIMAL(10,8),
    `location_lng` DECIMAL(11,8),
    `location_radius_km` DECIMAL(10,4),
    `wifi_enabled` TINYINT(1) NOT NULL DEFAULT 0,
    `wifi_ssid` VARCHAR(255),
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Leaves table
CREATE TABLE IF NOT EXISTS `leaves` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `employee_id` INT NOT NULL,
    `type` VARCHAR(100) NOT NULL,
    `start_date` DATE NOT NULL,
    `end_date` DATE NOT NULL,
    `days` INT NOT NULL DEFAULT 1,
    `reason` TEXT,
    `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_leaves_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Leave policy table
CREATE TABLE IF NOT EXISTS `leave_policy` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `days_per_month` INT NOT NULL DEFAULT 2,
    `days_per_year` INT NOT NULL DEFAULT 21,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Payroll table
CREATE TABLE IF NOT EXISTS `payroll` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `employee_id` INT NOT NULL,
    `month` INT NOT NULL,
    `year` INT NOT NULL,
    `base_salary` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `bonus` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `deductions` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `net_pay` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `status` ENUM('pending','paid','cancelled') NOT NULL DEFAULT 'pending',
    `paid_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_payroll_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Jobs table
CREATE TABLE IF NOT EXISTS `jobs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(255) NOT NULL,
    `department_id` INT NULL,
    `location` VARCHAR(255),
    `type` VARCHAR(100),
    `description` TEXT,
    `requirements` TEXT,
    `salary` VARCHAR(255),
    `status` ENUM('open','closed') NOT NULL DEFAULT 'open',
    `posted_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_jobs_department` FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Applications table
CREATE TABLE IF NOT EXISTS `applications` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `job_id` INT NULL,
    `applicant_name` VARCHAR(255) NOT NULL,
    `email` VARCHAR(255),
    `phone` VARCHAR(50),
    `resume_url` TEXT,
    `cover_letter` TEXT,
    `status` ENUM('new','screening','interview','offer','hired','rejected','talent_pool') NOT NULL DEFAULT 'new',
    `applied_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `direct_department_id` INT NULL,
    `direct_job_title` VARCHAR(255),
    CONSTRAINT `fk_applications_job` FOREIGN KEY (`job_id`) REFERENCES `jobs`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Candidate documents table
CREATE TABLE IF NOT EXISTS `candidate_documents` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `application_id` INT NOT NULL,
    `file_name` VARCHAR(255) NOT NULL,
    `file_path` TEXT NOT NULL,
    `mime_type` VARCHAR(100),
    `uploaded_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_candidate_docs_application` FOREIGN KEY (`application_id`) REFERENCES `applications`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Reviews table
CREATE TABLE IF NOT EXISTS `reviews` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `employee_id` INT NOT NULL,
    `reviewer_id` INT NOT NULL,
    `period` VARCHAR(100),
    `rating` INT,
    `goals` TEXT,
    `achievements` TEXT,
    `feedback` TEXT,
    `status` ENUM('draft','submitted','approved') NOT NULL DEFAULT 'draft',
    `reviewed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_reviews_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_reviews_reviewer` FOREIGN KEY (`reviewer_id`) REFERENCES `employees`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Announcements table
CREATE TABLE IF NOT EXISTS `announcements` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(255) NOT NULL,
    `content` TEXT,
    `author_id` INT,
    `author_name` VARCHAR(255),
    `priority` ENUM('low','medium','high') NOT NULL DEFAULT 'medium',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Required document types table
CREATE TABLE IF NOT EXISTS `required_document_types` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `label` VARCHAR(255) NOT NULL,
    `order_num` INT NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Employee documents table
CREATE TABLE IF NOT EXISTS `employee_documents` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `employee_id` INT NOT NULL,
    `document_type_id` INT NOT NULL,
    `file_name` VARCHAR(255) NOT NULL,
    `file_path` TEXT NOT NULL,
    `mime_type` VARCHAR(100),
    `uploaded_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_emp_docs_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_emp_docs_type` FOREIGN KEY (`document_type_id`) REFERENCES `required_document_types`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================
-- Default data inserts
-- =============================================

-- Default HR Admin user
-- Password: admin123
-- Hash generated with: password_hash('admin123', PASSWORD_BCRYPT)
-- IMPORTANT: After import, run seed_admin.php to regenerate the hash with your PHP version,
--            then change the password via the app. Delete seed_admin.php afterwards.
INSERT INTO `users` (`name`, `email`, `password_hash`, `role`, `status`, `created_at`)
VALUES (
    'HR Admin',
    'admin@company.com',
    '$2y$10$TKh8H1.PfbuNDMg5e0MX5uTPIPrDdZiZOXJOBEHJrFFfvRLyA2LNm',
    'hr_admin',
    'active',
    NOW()
) ON DUPLICATE KEY UPDATE id=id;

-- Default leave policy
INSERT INTO `leave_policy` (`days_per_month`, `days_per_year`, `updated_at`)
SELECT 2, 21, NOW()
WHERE NOT EXISTS (SELECT 1 FROM `leave_policy` LIMIT 1);

-- Default document types
INSERT INTO `required_document_types` (`label`, `order_num`) VALUES
('National ID', 1),
('Resume / CV', 2),
('Educational Certificates', 3),
('Experience Letters', 4),
('Medical Certificate', 5)
ON DUPLICATE KEY UPDATE id=id;
