# Al Anad HR

Multi-company HR platform: Flutter mobile app, React web portal and a PHP 8 + MySQL REST API.

- `mobile_app/` Flutter app (employee + HR), English and Arabic
- `artifacts/hr-portal/` React + Vite web portal
- `php-backend/` PHP REST API, MySQL schema (`database.sql`) and migrations
- `scripts/` deploy helpers (set `HR_FTP_HOST`, `HR_FTP_USER`, `HR_FTP_PASS` yourself)

Set your own database credentials in `php-backend/config/database.php`. Never commit real credentials.
