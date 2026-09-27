-- =====================================================================
-- 04_Seguridad.sql
-- Esquema de seguridad: roles, usuarios, permisos, vistas de seguridad
-- y políticas para ecommerce_db.
-- Ejecutar después de 01_Esquema_y_Datos.sql (MySQL 8.0+).
--
-- NOTA IMPORTANTE: algunos requisitos de seguridad (15, 16, 18, 20)
-- dependen de la configuración global del servidor MySQL (my.cnf) y
-- de plugins de auditoría, no solo de sentencias SQL dentro de una
-- base de datos. En esos casos se documenta la sentencia recomendada
-- y su alcance real.
-- =====================================================================
USE ecommerce_db;

-- ---------------------------------------------------------------------
-- 1. Rol Administrador_Sistema: todos los privilegios sobre la BD.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Administrador_Sistema';
CREATE ROLE 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'Administrador_Sistema';

-- ---------------------------------------------------------------------
-- 2. Rol Gerente_Marketing: solo lectura sobre ventas y clientes.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Gerente_Marketing';
CREATE ROLE 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'Gerente_Marketing';

-- ---------------------------------------------------------------------
-- 3. Rol Analista_Datos: solo lectura a todas las tablas, excepto auditoría.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Analista_Datos';
CREATE ROLE 'Analista_Datos';
GRANT SELECT ON ecommerce_db.productos          TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.categorias         TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedores        TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.clientes           TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.ventas             TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.detalle_ventas     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.sucursales         TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.carritos           TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.carrito_detalle    TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.producto_vistas    TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.resenas_productos  TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.codigos_descuento  TO 'Analista_Datos';
-- Explícitamente NO se otorga acceso a las tablas de auditoría/log:
-- log_cambios_precio, log_nuevos_clientes, log_cambio_estado_pedido,
-- log_login_intentos, log_permisos.

-- ---------------------------------------------------------------------
-- 4. Rol Empleado_Inventario: solo puede modificar productos (stock y
--    atributos de inventario), no precios.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Empleado_Inventario';
CREATE ROLE 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.productos TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.categorias TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.proveedores TO 'Empleado_Inventario';
GRANT UPDATE (stock, stock_minimo, activo, fecha_modificacion) ON ecommerce_db.productos TO 'Empleado_Inventario';

-- ---------------------------------------------------------------------
-- 5. Rol Atencion_Cliente: ve clientes y ventas, no modifica precios.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Atencion_Cliente';
CREATE ROLE 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.clientes TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Atencion_Cliente';
GRANT UPDATE (estado) ON ecommerce_db.ventas TO 'Atencion_Cliente'; -- puede cambiar el estado del pedido
GRANT SELECT (id_producto, nombre, sku, stock) ON ecommerce_db.productos TO 'Atencion_Cliente';
-- Explícitamente NO se otorga UPDATE sobre productos.precio ni productos.costo.

-- ---------------------------------------------------------------------
-- 6. Rol Auditor_Financiero: solo lectura a ventas, productos y logs de precios.
--    (La tabla log_cambios_precio se crea en 05_Triggers.sql; MySQL permite
--     otorgar el privilegio antes de que la tabla exista.)
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Auditor_Financiero';
CREATE ROLE 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.productos TO 'Auditor_Financiero';

-- MySQL exige que la tabla exista para otorgar un privilegio a nivel de
-- tabla. log_cambios_precio se define formalmente en 05_Triggers.sql;
-- aquí se crea de forma adelantada (IF NOT EXISTS) solo para poder
-- otorgar el permiso sin error. La definición de 05 es idéntica y no
-- duplicará ni sobrescribirá la tabla.
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT NOT NULL,
    precio_anterior DECIMAL(12,2) NOT NULL,
    precio_nuevo    DECIMAL(12,2) NOT NULL,
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_logprecio_producto_sec FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);
GRANT SELECT ON ecommerce_db.log_cambios_precio TO 'Auditor_Financiero';

-- ---------------------------------------------------------------------
-- 7-10. Creación de usuarios y asignación de roles.
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'admin_user'@'localhost';
CREATE USER 'admin_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2026!';
GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';

DROP USER IF EXISTS 'marketing_user'@'localhost';
CREATE USER 'marketing_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2026!';
GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
SET DEFAULT ROLE 'Gerente_Marketing' TO 'marketing_user'@'localhost';

DROP USER IF EXISTS 'inventory_user'@'localhost';
CREATE USER 'inventory_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2026!';
GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
SET DEFAULT ROLE 'Empleado_Inventario' TO 'inventory_user'@'localhost';

DROP USER IF EXISTS 'support_user'@'localhost';
CREATE USER 'support_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2026!';
GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';
SET DEFAULT ROLE 'Atencion_Cliente' TO 'support_user'@'localhost';

-- Registrar la asignación de roles en la tabla de auditoría de permisos.
INSERT INTO permisos_usuarios (usuario_bd, rol_asignado) VALUES
('admin_user@localhost', 'Administrador_Sistema'),
('marketing_user@localhost', 'Gerente_Marketing'),
('inventory_user@localhost', 'Empleado_Inventario'),
('support_user@localhost', 'Atencion_Cliente');

-- ---------------------------------------------------------------------
-- 11. Impedir que Analista_Datos ejecute DELETE o TRUNCATE.
--     El rol solo recibió privilegios SELECT (ver punto 3), por lo que
--     DELETE y DROP/TRUNCATE ya están implícitamente denegados: MySQL no
--     permite REVOCAR un privilegio que nunca fue otorgado en ese ámbito
--     (haría fallar el script), así que la restricción se garantiza por
--     "denegación por defecto" en lugar de un REVOKE explícito.
-- ---------------------------------------------------------------------
-- (Verificación) los privilegios efectivos del rol se pueden auditar con:
-- SHOW GRANTS FOR 'Analista_Datos';

-- ---------------------------------------------------------------------
-- 12. Otorgar a Gerente_Marketing permiso de ejecución de procedimientos
--     de reportes de marketing. Los procedimientos (sp_GenerarReporteMensualVentas,
--     sp_ObtenerDashboardAdmin) se definen en 07_Procedimientos_Almacenados.sql,
--     que se ejecuta después de este script; MySQL exige que el objeto exista
--     para otorgar EXECUTE sobre él, así que estos GRANT se emiten al final
--     de 07_Procedimientos_Almacenados.sql, una vez creados los procedimientos.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 13. Vista v_info_clientes_basica: oculta información sensible.
--     Acceso otorgado al rol Atencion_Cliente.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT
    id_cliente,
    nombre,
    apellido,
    ciudad,
    nivel_lealtad,
    fecha_registro,
    activo
FROM clientes;
-- No incluye: email, contrasena_hash, direccion_envio, fecha_nacimiento, total_gastado

GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Atencion_Cliente';

-- ---------------------------------------------------------------------
-- 14. Revocar UPDATE sobre la columna precio de productos al rol
--     Empleado_Inventario. El GRANT UPDATE del punto 4 ya se otorgó
--     únicamente sobre (stock, stock_minimo, activo, fecha_modificacion),
--     por lo que precio/costo quedan fuera del privilegio por diseño.
--     MySQL no permite revocar un privilegio de columna que nunca fue
--     otorgado, así que aquí se deja constancia explícita de la
--     restricción mediante una comprobación de auditoría:
-- ---------------------------------------------------------------------
-- SHOW GRANTS FOR 'Empleado_Inventario'; -- confirma que precio/costo no aparecen

-- ---------------------------------------------------------------------
-- 15. Política de contraseñas seguras para todos los usuarios.
--     Requiere el componente/plugin validate_password instalado en el
--     servidor (alcance global, no solo de esta base de datos).
-- ---------------------------------------------------------------------
-- INSTALL COMPONENT 'file://component_validate_password';
-- SET GLOBAL validate_password.policy = 'STRONG';
-- SET GLOBAL validate_password.length = 12;
-- SET GLOBAL validate_password.mixed_case_count = 1;
-- SET GLOBAL validate_password.number_count = 1;
-- SET GLOBAL validate_password.special_char_count = 1;
-- Adicionalmente, se exige el cambio de contraseña cada 90 días a nivel
-- de cuenta para todos los usuarios creados en este script:
ALTER USER 'admin_user'@'localhost'      PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'marketing_user'@'localhost'  PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'inventory_user'@'localhost'  PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'support_user'@'localhost'    PASSWORD EXPIRE INTERVAL 90 DAY;

-- ---------------------------------------------------------------------
-- 16. Asegurar que 'root' no pueda usarse desde conexiones remotas.
--     Esto se controla con el host asociado a la cuenta, no con GRANT.
-- ---------------------------------------------------------------------
-- Verificar que solo exista 'root'@'localhost' (y no 'root'@'%'):
-- SELECT user, host FROM mysql.user WHERE user = 'root';
DROP USER IF EXISTS 'root'@'%';
-- Si se requiere administración remota, usar 'admin_user' con un host
-- específico (ej. 'admin_user'@'10.0.0.%') en lugar de exponer 'root'.

-- ---------------------------------------------------------------------
-- 17. Rol Visitante: solo puede ver la tabla productos (catálogo público,
--     solo productos activos).
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Visitante';
CREATE ROLE 'Visitante';
CREATE OR REPLACE VIEW v_catalogo_publico AS
SELECT id_producto, nombre, descripcion, precio, sku
FROM productos
WHERE activo = TRUE AND stock > 0;
GRANT SELECT ON ecommerce_db.v_catalogo_publico TO 'Visitante';

-- ---------------------------------------------------------------------
-- 18. Limitar el número de consultas por hora para Analista_Datos.
--     Los límites de recursos en MySQL se definen por usuario, no por rol.
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'analista_user'@'localhost';
CREATE USER 'analista_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2026!'
    WITH MAX_QUERIES_PER_HOUR 500;
GRANT 'Analista_Datos' TO 'analista_user'@'localhost';
SET DEFAULT ROLE 'Analista_Datos' TO 'analista_user'@'localhost';

-- ---------------------------------------------------------------------
-- 19. Restringir que cada usuario solo vea las ventas de su sucursal.
--     Se implementa a nivel de aplicación/vista, ya que MySQL no ofrece
--     seguridad de fila nativa (row-level security). Se usa una tabla de
--     mapeo usuario -> sucursal y una vista que filtra según el usuario
--     conectado (CURRENT_USER()).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuario_sucursal (
    usuario_bd  VARCHAR(100) PRIMARY KEY,
    id_sucursal INT NOT NULL,
    CONSTRAINT fk_us_sucursal FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
);

INSERT INTO usuario_sucursal (usuario_bd, id_sucursal) VALUES
('support_user@localhost', 1);

CREATE OR REPLACE VIEW v_ventas_de_mi_sucursal AS
SELECT v.*
FROM ventas v
JOIN usuario_sucursal us
  ON us.id_sucursal = v.id_sucursal
 AND us.usuario_bd = CURRENT_USER();

GRANT SELECT ON ecommerce_db.v_ventas_de_mi_sucursal TO 'Atencion_Cliente';

-- ---------------------------------------------------------------------
-- 20. Auditar los intentos de inicio de sesión fallidos.
--     La tabla log_login_intentos (creada en 01) se alimenta desde la
--     capa de aplicación en cada intento de login. Para auditoría a
--     nivel de servidor MySQL, se recomienda habilitar el plugin de
--     auditoría (Enterprise) o el log general filtrado por errores 1045:
-- ---------------------------------------------------------------------
-- INSTALL PLUGIN audit_log SONAME 'audit_log.so';
-- SET GLOBAL audit_log_policy = 'LOGINS';
-- Como alternativa portable dentro de la propia base de datos, se puede
-- consultar el histórico ya almacenado por la aplicación:
-- SELECT * FROM log_login_intentos WHERE exito = FALSE ORDER BY fecha_intento DESC;

FLUSH PRIVILEGES;
