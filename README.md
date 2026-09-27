# Proyecto_BD_Avanzada_Raymond_Zabala.
E-commerce Database Project
Description

This project implements the core of a relational database for an online store, designed for MySQL 8.0+ (also validated on MariaDB 10.11). It covers the product and category catalog, supplier and customer management, and the complete lifecycle of a sale (header and detail), ensuring data integrity through foreign keys, CHECK constraints and triggers. On top of this schema, an analytics layer is built (20 business queries), reusable logic (20 functions), a role-based security scheme (20 requirements), automation through 20 triggers and 20 scheduled events, and 20 stored procedures for the most important transactional operations of the business.

Team Members
Raymond Javier Zabala Sanchez
Execution Instructions

The scripts must be executed in strict order, since each one depends on objects created by the previous one (tables, functions, roles, etc.).

bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p ecommerce_db < 02_Consultas_Avanzadas.sql
mysql -u root -p ecommerce_db < 03_Funciones.sql
mysql -u root -p ecommerce_db < 04_Seguridad.sql
mysql -u root -p ecommerce_db < 05_Triggers.sql
mysql -u root -p ecommerce_db < 06_Eventos.sql
mysql -u root -p ecommerce_db < 07_Procedimientos_Almacenados.sql
01_Esquema_y_Datos.sql — Creates the ecommerce_db database, all tables (CREATE TABLE) and loads sample data (INSERT INTO) sufficient to test the rest of the scripts.
02_Consultas_Avanzadas.sql — Runs the 20 analytical queries. Only requires step 1. It can be run as a reference; each query is preceded by a comment stating the business question it answers.
03_Funciones.sql — Creates the 20 functions (CREATE FUNCTION) used later by triggers and procedures, so it must be run before 05 and 07.
04_Seguridad.sql — Creates roles, users and permissions (CREATE ROLE, CREATE USER, GRANT). Requires step 1 (uses the tables) and an advance CREATE TABLE IF NOT EXISTS log_cambios_precio statement (see the dependency note below).
05_Triggers.sql — Creates the log_cambios_precio table (formal definition) and the supporting audit tables, plus the 20 triggers. Requires steps 1 and 3 (uses fn_CalcularTotalVenta and fn_ValidarFormatoEmail).
06_Eventos.sql — Creates the reporte_ventas_semanales table and the supporting tables for each event, plus the 20 CREATE EVENT statements, and enables the event_scheduler. Requires step 3 (uses fn_DeterminarEstadoLealtad).
07_Procedimientos_Almacenados.sql — Creates the 20 CREATE PROCEDURE statements and, at the end, the GRANT EXECUTE statements on sp_GenerarReporteMensualVentas and sp_ObtenerDashboardAdmin for the Gerente_Marketing role (security requirement #12), since those permissions can only be granted once the procedures exist.
Engine Requirements
MySQL 8.0.16 or higher (due to CHECK constraints, roles, JSON_TABLE, window functions and CREATE EVENT). It was also successfully validated on MariaDB 10.11.
The user running the scripts needs administrative privileges (CREATE, GRANT OPTION, and permissions to create roles, users and enable the event_scheduler).
Before using this in production, change all sample passwords (Cambiar_Esta_Clave_2026!) defined in 04_Seguridad.sql.
Note on Cross-File Dependencies

Two security requirements reference objects that are formally defined in a later script (log_cambios_precio in 05, and the marketing procedures in 07). MySQL requires a table or routine to exist before a specific privilege can be granted on it, so:

04_Seguridad.sql creates log_cambios_precio in advance (CREATE TABLE IF NOT EXISTS) with the same definition that later appears, also protected with IF NOT EXISTS, in 05_Triggers.sql — no data is duplicated or lost.
The GRANT EXECUTE statements on the marketing procedures are issued at the end of 07_Procedimientos_Almacenados.sql, once the procedures have been created, instead of in 04_Seguridad.sql.

This is also documented as comments inside each script.

File Structure
01_Esquema_y_Datos.sql            Tables + sample data
02_Consultas_Avanzadas.sql        20 analysis and reporting queries
03_Funciones.sql                  20 user-defined functions
04_Seguridad.sql                  Roles, users, permissions and security views
05_Triggers.sql                   log_cambios_precio table + 20 triggers
06_Eventos.sql                    reporte_ventas_semanales table + 20 events
07_Procedimientos_Almacenados.sql 20 stored procedures
README.md                         This file
Design Decisions and Assumptions
Additional supporting tables: several business questions, triggers and events require data that was not part of the six main entities (product views, shopping carts, reviews, discount codes, branches, referral program, audit logs). These tables are created as a natural part of 01_Esquema_y_Datos.sql (the business ones) or in the script where the requirement first introduces them (the audit ones, in 05_Triggers.sql and 06_Eventos.sql), and are documented with comments in the code itself.
sucursales (branches): added to satisfy security requirement #19 (each user should only see sales from their own branch), since the original model did not include branches.
One logical requirement, several physical triggers: MySQL does not allow a single trigger to be created for multiple events (INSERT/UPDATE/DELETE) at once. When a business requirement needs to react to more than one event (for example, "recalculate the sale total when the detail changes" or "keep the product count per category updated"), it was implemented as 2 or 3 physical triggers that together fulfill a single requirement from the list of 20. That is why 05_Triggers.sql contains 27 physical triggers covering the 20 requested requirements.
Row-level security: MySQL does not offer this feature natively. Requirement #19 (only see sales from your own branch) is solved with a mapping table usuario_sucursal and a view (v_ventas_de_mi_sucursal) that filters using CURRENT_USER(). This is an application-level approximation, not a restriction enforced by the engine on the base table.
Server-scope requirements: the security items regarding global password policies (validate_password), the login-audit plugin and restricting root to remote connections depend on server configuration (my.cnf), not solely on SQL statements within a database. In those cases, the script leaves the recommended statements commented out and applies what is actually controllable from SQL (per-account password expiration, removal of root@'%', query-per-hour limits, etc.).
precio_unitario_congelado (frozen unit price): as required by the assignment, it is never calculated from productos.precio at query time; it is copied once when the sale line is inserted (in sp_RealizarNuevaVenta and in the sample data), preserving the historical price even if the catalog price changes afterward.
Backups and materialized views: since no external physical backup tools are available in this environment, evt_backup_critical_tables_daily and evt_refresh_materialized_views_nightly are implemented as a logical copy within the same database (mirror tables backup_* and mv_productos_mas_vendidos), sufficient for demonstration purposes.
Validation Performed

All 7 scripts were executed end-to-end on a clean MySQL/MariaDB server, in the order indicated, with no errors. It was also verified that:

The 20 queries in 02 return results consistent with the sample data.
The 20 triggers, 20 functions, 20 procedures and 20 events are properly registered in information_schema after execution.
A complete functional flow (creating a sale with sp_RealizarNuevaVenta, updating a price, changing an order's status) correctly decreases stock, recalculates the sale total, logs the price change in log_cambios_precio and the status change in log_cambio_estado_pedido.

(Note: SET DEFAULT ROLE ... TO user in 04_Seguridad.sql is valid MySQL 8.0 syntax for assigning an account's default role; MariaDB uses a different syntax for that specific step, which does not affect execution on the project's target engine, MySQL 8.0+.)

Contenido
