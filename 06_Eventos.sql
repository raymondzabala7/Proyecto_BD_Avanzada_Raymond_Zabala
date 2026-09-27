-- =====================================================================
-- 06_Eventos.sql
-- Tabla de reportes semanales + 20 eventos programados para ecommerce_db.
-- Ejecutar después de 01 a 05.
-- Requiere que el event_scheduler de MySQL esté activo.
-- =====================================================================
USE ecommerce_db;

-- ---------------------------------------------------------------------
-- Tabla requerida: reporte_ventas_semanales
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte      INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio   DATE NOT NULL,
    semana_fin      DATE NOT NULL,
    num_ventas      INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL,
    fecha_generado  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- Tablas de apoyo para los demás eventos
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_archivo_general (
    id_log       INT AUTO_INCREMENT PRIMARY KEY,
    origen       VARCHAR(100) NOT NULL,
    contenido    TEXT,
    fecha_evento DATETIME NOT NULL,
    fecha_archivado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS lista_reabastecimiento (
    id_lista       INT AUTO_INCREMENT PRIMARY KEY,
    id_producto    INT NOT NULL,
    stock_actual   INT NOT NULL,
    stock_minimo   INT NOT NULL,
    fecha_generado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS resumen_ventas_diario (
    fecha           DATE PRIMARY KEY,
    num_ventas      INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL,
    fecha_calculado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_inconsistencias (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    descripcion   VARCHAR(255) NOT NULL,
    id_referencia INT,
    fecha_deteccion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cupones_cumpleanos (
    id_cupon      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente    INT NOT NULL,
    codigo_cupon  VARCHAR(30) NOT NULL,
    fecha_generado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ranking_productos (
    id_producto    INT PRIMARY KEY,
    unidades_30d   INT NOT NULL,
    ingresos_30d   DECIMAL(14,2) NOT NULL,
    fecha_calculado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS backup_productos (LIKE productos);
CREATE TABLE IF NOT EXISTS backup_clientes (LIKE clientes);
CREATE TABLE IF NOT EXISTS backup_ventas (LIKE ventas);

CREATE TABLE IF NOT EXISTS kpis_mensuales (
    anio            INT NOT NULL,
    mes             INT NOT NULL,
    num_ventas      INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL,
    nuevos_clientes INT NOT NULL,
    ticket_promedio DECIMAL(14,2) NOT NULL,
    fecha_calculado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (anio, mes)
);

CREATE TABLE IF NOT EXISTS mv_productos_mas_vendidos (
    id_producto   INT PRIMARY KEY,
    nombre        VARCHAR(200),
    unidades_totales INT,
    ingresos_totales DECIMAL(14,2),
    fecha_calculado  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_tamano_bd (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    tamano_mb     DECIMAL(12,2) NOT NULL,
    fecha_medicion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertas_fraude (
    id_alerta     INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente    INT NOT NULL,
    motivo        VARCHAR(255) NOT NULL,
    fecha_alerta  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reporte_proveedores_mensual (
    id_reporte     INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor   INT NOT NULL,
    anio           INT NOT NULL,
    mes            INT NOT NULL,
    ingresos_generados DECIMAL(14,2) NOT NULL,
    fecha_generado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Activar el planificador de eventos de MySQL (requiere privilegios SUPER
-- o SYSTEM_VARIABLES_ADMIN; en algunos entornos gestionados se activa
-- desde el panel de administración en vez de por SQL).
SET GLOBAL event_scheduler = ON;

DELIMITER $$

-- 1. evt_generate_weekly_sales_report: cada lunes a la 01:00 am
DROP EVENT IF EXISTS evt_generate_weekly_sales_report $$
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 HOUR)
DO
BEGIN
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, num_ventas, total_vendido)
    SELECT
        DATE_SUB(CURDATE(), INTERVAL 7 DAY),
        DATE_SUB(CURDATE(), INTERVAL 1 DAY),
        COUNT(*),
        COALESCE(SUM(total), 0)
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND fecha_venta < CURDATE()
      AND estado <> 'Cancelado';
END $$

-- 2. evt_cleanup_temp_tables_daily: elimina tablas temporales cuyo nombre inicia con 'tmp_'
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily $$
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 2 HOUR)
DO
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_tabla VARCHAR(200);
    DECLARE cur CURSOR FOR
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'ecommerce_db' AND table_name LIKE 'tmp\_%';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_tabla;
        IF done THEN
            LEAVE read_loop;
        END IF;
        SET @sql_drop = CONCAT('DROP TABLE IF EXISTS `', v_tabla, '`');
        PREPARE stmt FROM @sql_drop;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END LOOP;
    CLOSE cur;
END $$

-- 3. evt_archive_old_logs_monthly: mueve logs de más de 6 meses a log_archivo_general
DROP EVENT IF EXISTS evt_archive_old_logs_monthly $$
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (TIMESTAMP(CURDATE()) + INTERVAL 3 HOUR)
DO
BEGIN
    INSERT INTO log_archivo_general (origen, contenido, fecha_evento)
    SELECT 'log_login_intentos',
           CONCAT('usuario=', usuario, ' exito=', exito, ' ip=', ip_origen),
           fecha_intento
    FROM log_login_intentos
    WHERE fecha_intento < DATE_SUB(NOW(), INTERVAL 6 MONTH);

    DELETE FROM log_login_intentos WHERE fecha_intento < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END $$

-- 4. evt_deactivate_expired_promotions_hourly
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly $$
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
DO
    UPDATE codigos_descuento
       SET activo = FALSE
       WHERE fecha_fin < NOW() AND activo = TRUE $$

-- 5. evt_recalculate_customer_loyalty_tiers_nightly
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly $$
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 23 HOUR)
DO
BEGIN
    UPDATE clientes
       SET nivel_lealtad = fn_DeterminarEstadoLealtad(id_cliente);
END $$

-- 6. evt_generate_reorder_list_daily
DROP EVENT IF EXISTS evt_generate_reorder_list_daily $$
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 4 HOUR)
DO
    INSERT INTO lista_reabastecimiento (id_producto, stock_actual, stock_minimo)
    SELECT id_producto, stock, stock_minimo
    FROM productos
    WHERE stock < stock_minimo AND activo = TRUE $$

-- 7. evt_rebuild_indexes_weekly
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly $$
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (TIMESTAMP(CURDATE()) + INTERVAL 5 HOUR)
DO
BEGIN
    OPTIMIZE TABLE productos, ventas, detalle_ventas, clientes;
END $$

-- 8. evt_suspend_inactive_accounts_quarterly
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly $$
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH STARTS (TIMESTAMP(CURDATE()) + INTERVAL 6 HOUR)
DO
    UPDATE clientes
       SET activo = FALSE
       WHERE (fecha_ultima_compra IS NULL OR fecha_ultima_compra < DATE_SUB(NOW(), INTERVAL 1 YEAR))
         AND fecha_registro < DATE_SUB(NOW(), INTERVAL 1 YEAR)
         AND activo = TRUE $$

-- 9. evt_aggregate_daily_sales_data
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data $$
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 30 MINUTE)
DO
    INSERT INTO resumen_ventas_diario (fecha, num_ventas, total_vendido)
    SELECT CURDATE() - INTERVAL 1 DAY, COUNT(*), COALESCE(SUM(total), 0)
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE() - INTERVAL 1 DAY AND estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE
        num_ventas = VALUES(num_ventas),
        total_vendido = VALUES(total_vendido),
        fecha_calculado = NOW() $$

-- 10. evt_check_data_consistency_nightly
DROP EVENT IF EXISTS evt_check_data_consistency_nightly $$
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 2 HOUR + INTERVAL 30 MINUTE)
DO
    INSERT INTO log_inconsistencias (descripcion, id_referencia)
    SELECT 'Venta sin líneas de detalle', v.id_venta
    FROM ventas v
    LEFT JOIN detalle_ventas d ON d.id_venta = v.id_venta
    WHERE d.id_detalle IS NULL $$

-- 11. evt_send_birthday_greetings_daily
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily $$
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 7 HOUR)
DO
    INSERT INTO cupones_cumpleanos (id_cliente, codigo_cupon)
    SELECT id_cliente, CONCAT('CUMPLE', id_cliente, '-', YEAR(CURDATE()))
    FROM clientes
    WHERE MONTH(fecha_nacimiento) = MONTH(CURDATE())
      AND DAY(fecha_nacimiento) = DAY(CURDATE())
      AND activo = TRUE $$

-- 12. evt_update_product_rankings_hourly
DROP EVENT IF EXISTS evt_update_product_rankings_hourly $$
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    DELETE FROM ranking_productos;
    INSERT INTO ranking_productos (id_producto, unidades_30d, ingresos_30d)
    SELECT d.id_producto, SUM(d.cantidad), SUM(d.cantidad * d.precio_unitario_congelado)
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    WHERE v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 30 DAY) AND v.estado <> 'Cancelado'
    GROUP BY d.id_producto;
END $$

-- 13. evt_backup_critical_tables_daily (backup lógico dentro de la misma BD)
DROP EVENT IF EXISTS evt_backup_critical_tables_daily $$
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 HOUR + INTERVAL 30 MINUTE)
DO
BEGIN
    TRUNCATE TABLE backup_productos;
    INSERT INTO backup_productos SELECT * FROM productos;
    TRUNCATE TABLE backup_clientes;
    INSERT INTO backup_clientes SELECT * FROM clientes;
    TRUNCATE TABLE backup_ventas;
    INSERT INTO backup_ventas SELECT * FROM ventas;
END $$

-- 14. evt_clear_abandoned_carts_daily: marca como 'Abandonado' carritos activos hace más de 72h
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily $$
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 3 HOUR + INTERVAL 30 MINUTE)
DO
    UPDATE carritos
       SET estado = 'Abandonado'
       WHERE estado = 'Activo' AND fecha_creacion < DATE_SUB(NOW(), INTERVAL 72 HOUR) $$

-- 15. evt_calculate_monthly_kpis: se ejecuta el primer día de cada mes
DROP EVENT IF EXISTS evt_calculate_monthly_kpis $$
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH STARTS (TIMESTAMP(CURDATE()) + INTERVAL 4 HOUR + INTERVAL 30 MINUTE)
DO
    INSERT INTO kpis_mensuales (anio, mes, num_ventas, total_vendido, nuevos_clientes, ticket_promedio)
    SELECT
        YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        COUNT(DISTINCT v.id_venta),
        COALESCE(SUM(v.total), 0),
        (SELECT COUNT(*) FROM clientes
          WHERE YEAR(fecha_registro) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
            AND MONTH(fecha_registro) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))),
        ROUND(COALESCE(SUM(v.total), 0) / NULLIF(COUNT(DISTINCT v.id_venta), 0), 2)
    FROM ventas v
    WHERE YEAR(v.fecha_venta) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
      AND MONTH(v.fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
      AND v.estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE
        num_ventas = VALUES(num_ventas),
        total_vendido = VALUES(total_vendido),
        nuevos_clientes = VALUES(nuevos_clientes),
        ticket_promedio = VALUES(ticket_promedio),
        fecha_calculado = NOW() $$

-- 16. evt_refresh_materialized_views_nightly (refresca la tabla-resumen que actúa como vista materializada)
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly $$
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 HOUR)
DO
BEGIN
    TRUNCATE TABLE mv_productos_mas_vendidos;
    INSERT INTO mv_productos_mas_vendidos (id_producto, nombre, unidades_totales, ingresos_totales)
    SELECT p.id_producto, p.nombre, SUM(d.cantidad), SUM(d.cantidad * d.precio_unitario_congelado)
    FROM productos p
    JOIN detalle_ventas d ON d.id_producto = p.id_producto
    JOIN ventas v ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
    GROUP BY p.id_producto, p.nombre;
END $$

-- 17. evt_log_database_size_weekly
DROP EVENT IF EXISTS evt_log_database_size_weekly $$
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (TIMESTAMP(CURDATE()) + INTERVAL 6 HOUR)
DO
    INSERT INTO log_tamano_bd (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables
    WHERE table_schema = 'ecommerce_db' $$

-- 18. evt_detect_fraudulent_activity_hourly: clientes con más de 3 ventas canceladas en 24h
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly $$
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
DO
    INSERT INTO alertas_fraude (id_cliente, motivo)
    SELECT id_cliente, CONCAT('Más de 3 pedidos cancelados en 24h (', COUNT(*), ')')
    FROM ventas
    WHERE estado = 'Cancelado' AND fecha_venta >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    GROUP BY id_cliente
    HAVING COUNT(*) > 3 $$

-- 19. evt_generate_supplier_performance_report_monthly
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly $$
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (TIMESTAMP(CURDATE()) + INTERVAL 5 HOUR + INTERVAL 30 MINUTE)
DO
    INSERT INTO reporte_proveedores_mensual (id_proveedor, anio, mes, ingresos_generados)
    SELECT
        prov.id_proveedor,
        YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0)
    FROM proveedores prov
    LEFT JOIN productos p ON p.id_proveedor = prov.id_proveedor
    LEFT JOIN detalle_ventas d ON d.id_producto = p.id_producto
    LEFT JOIN ventas v ON v.id_venta = d.id_venta
        AND YEAR(v.fecha_venta) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
        AND MONTH(v.fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
        AND v.estado <> 'Cancelado'
    GROUP BY prov.id_proveedor $$

-- 20. evt_purge_soft_deleted_records_weekly: elimina definitivamente clientes
--     desactivados (soft-deleted) hace más de 30 días
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly $$
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (TIMESTAMP(CURDATE()) + INTERVAL 7 HOUR)
DO
    DELETE FROM clientes
    WHERE activo = FALSE
      AND fecha_ultima_compra < DATE_SUB(NOW(), INTERVAL 30 DAY)
      AND NOT EXISTS (SELECT 1 FROM ventas v WHERE v.id_cliente = clientes.id_cliente) $$

DELIMITER ;
