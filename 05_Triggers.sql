-- =====================================================================
-- 05_Triggers.sql
-- Tabla de auditoría de precios + 20 triggers para ecommerce_db.
-- Ejecutar después de 01_Esquema_y_Datos.sql, 03_Funciones.sql y
-- 04_Seguridad.sql.
-- =====================================================================
USE ecommerce_db;

-- ---------------------------------------------------------------------
-- Tabla de auditoría: log_cambios_precio
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log         INT AUTO_INCREMENT PRIMARY KEY,
    id_producto    INT NOT NULL,
    precio_anterior DECIMAL(12,2) NOT NULL,
    precio_nuevo    DECIMAL(12,2) NOT NULL,
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_logprecio_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

-- Tablas de auditoría adicionales requeridas por los triggers de este archivo
CREATE TABLE IF NOT EXISTS log_nuevos_clientes (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    email       VARCHAR(150) NOT NULL,
    fecha_alta  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_cambio_estado_pedido (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    id_venta      INT NOT NULL,
    estado_anterior VARCHAR(30) NOT NULL,
    estado_nuevo    VARCHAR(30) NOT NULL,
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertas_stock (
    id_alerta    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    stock_actual INT NOT NULL,
    stock_minimo INT NOT NULL,
    fecha_alerta DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ventas_archivadas (
    id_archivo     INT AUTO_INCREMENT PRIMARY KEY,
    id_venta       INT NOT NULL,
    id_cliente     INT NOT NULL,
    fecha_venta    DATETIME NOT NULL,
    estado         VARCHAR(30) NOT NULL,
    total          DECIMAL(14,2) NOT NULL,
    fecha_archivado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_permisos (
    id_log         INT AUTO_INCREMENT PRIMARY KEY,
    usuario_bd     VARCHAR(100) NOT NULL,
    rol_asignado   VARCHAR(100) NOT NULL,
    fecha_cambio   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. trg_audit_precio_producto_after_update
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update $$
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio);
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 2. trg_check_stock_before_insert_venta (sobre detalle_ventas)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta $$
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_disponible INT;
    SELECT stock INTO v_stock_disponible FROM productos WHERE id_producto = NEW.id_producto;
    IF v_stock_disponible IS NULL OR v_stock_disponible < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock insuficiente para registrar esta línea de venta.';
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 3. trg_update_stock_after_insert_venta (sobre detalle_ventas)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta $$
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
       SET stock = stock - NEW.cantidad
       WHERE id_producto = NEW.id_producto;
END $$

-- ---------------------------------------------------------------------
-- 4. trg_prevent_delete_categoria_with_products
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products $$
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    IF OLD.num_productos > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar una categoría que tiene productos asociados.';
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 5. trg_log_new_customer_after_insert
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert $$
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_nuevos_clientes (id_cliente, email) VALUES (NEW.id_cliente, NEW.email);
END $$

-- ---------------------------------------------------------------------
-- 6. trg_update_total_gastado_cliente (AFTER INSERT y AFTER UPDATE en ventas)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente_ins $$
CREATE TRIGGER trg_update_total_gastado_cliente_ins
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
       SET total_gastado = (
               SELECT COALESCE(SUM(total), 0) FROM ventas
               WHERE id_cliente = NEW.id_cliente AND estado <> 'Cancelado'
           )
       WHERE id_cliente = NEW.id_cliente;
END $$

DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente_upd $$
CREATE TRIGGER trg_update_total_gastado_cliente_upd
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.total <> OLD.total OR NEW.estado <> OLD.estado THEN
        UPDATE clientes
           SET total_gastado = (
                   SELECT COALESCE(SUM(total), 0) FROM ventas
                   WHERE id_cliente = NEW.id_cliente AND estado <> 'Cancelado'
               )
           WHERE id_cliente = NEW.id_cliente;
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 7. trg_set_fecha_modificacion_producto
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto $$
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END $$

-- ---------------------------------------------------------------------
-- 8. trg_prevent_negative_stock
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_negative_stock $$
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El stock de un producto no puede ser negativo.';
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 9. trg_capitalize_nombre_cliente
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente $$
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre, 1)), LOWER(SUBSTRING(NEW.nombre, 2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END $$

-- ---------------------------------------------------------------------
-- 10. trg_recalculate_total_venta_on_detalle_change (INSERT/UPDATE/DELETE)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_recalc_total_after_insert_detalle $$
CREATE TRIGGER trg_recalc_total_after_insert_detalle
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
       SET total = fn_CalcularTotalVenta(NEW.id_venta)
       WHERE id_venta = NEW.id_venta;
END $$

DROP TRIGGER IF EXISTS trg_recalc_total_after_update_detalle $$
CREATE TRIGGER trg_recalc_total_after_update_detalle
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
       SET total = fn_CalcularTotalVenta(NEW.id_venta)
       WHERE id_venta = NEW.id_venta;
END $$

DROP TRIGGER IF EXISTS trg_recalc_total_after_delete_detalle $$
CREATE TRIGGER trg_recalc_total_after_delete_detalle
AFTER DELETE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
       SET total = fn_CalcularTotalVenta(OLD.id_venta)
       WHERE id_venta = OLD.id_venta;
END $$

-- ---------------------------------------------------------------------
-- 11. trg_log_order_status_change
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_order_status_change $$
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO log_cambio_estado_pedido (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 12. trg_prevent_price_zero_or_less (INSERT y UPDATE)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less_ins $$
CREATE TRIGGER trg_prevent_price_zero_or_less_ins
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero.';
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less_upd $$
CREATE TRIGGER trg_prevent_price_zero_or_less_upd
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero.';
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 13. trg_send_stock_alert_on_low_stock
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock $$
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < NEW.stock_minimo AND (OLD.stock >= OLD.stock_minimo OR OLD.stock <> NEW.stock) THEN
        INSERT INTO alertas_stock (id_producto, stock_actual, stock_minimo)
        VALUES (NEW.id_producto, NEW.stock, NEW.stock_minimo);
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 14. trg_archive_deleted_venta
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_archive_deleted_venta $$
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total);
END $$

-- ---------------------------------------------------------------------
-- 15. trg_validate_email_format_on_customer (INSERT y UPDATE)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_validate_email_format_ins $$
CREATE TRIGGER trg_validate_email_format_ins
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El formato del correo electrónico no es válido.';
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_validate_email_format_upd $$
CREATE TRIGGER trg_validate_email_format_upd
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El formato del correo electrónico no es válido.';
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 16. trg_update_last_order_date_customer
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer $$
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
       SET fecha_ultima_compra = NEW.fecha_venta
       WHERE id_cliente = NEW.id_cliente
         AND (fecha_ultima_compra IS NULL OR NEW.fecha_venta > fecha_ultima_compra);
END $$

-- ---------------------------------------------------------------------
-- 17. trg_prevent_self_referral
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_self_referral $$
CREATE TRIGGER trg_prevent_self_referral
BEFORE INSERT ON programa_referidos
FOR EACH ROW
BEGIN
    IF NEW.id_cliente_referidor = NEW.id_cliente_referido THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Un cliente no puede referirse a sí mismo.';
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 18. trg_log_permission_changes (sobre la tabla de aplicación permisos_usuarios)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_permission_changes $$
CREATE TRIGGER trg_log_permission_changes
AFTER INSERT ON permisos_usuarios
FOR EACH ROW
BEGIN
    INSERT INTO log_permisos (usuario_bd, rol_asignado)
    VALUES (NEW.usuario_bd, NEW.rol_asignado);
END $$

-- ---------------------------------------------------------------------
-- 19. trg_assign_default_category_on_null
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null $$
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    DECLARE v_id_general INT;
    IF NEW.id_categoria IS NULL THEN
        SELECT id_categoria INTO v_id_general FROM categorias WHERE nombre = 'General' LIMIT 1;
        SET NEW.id_categoria = v_id_general;
    END IF;
END $$

-- ---------------------------------------------------------------------
-- 20. trg_update_producto_count_in_categoria (INSERT/UPDATE/DELETE)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_prod_count_after_insert $$
CREATE TRIGGER trg_update_prod_count_after_insert
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NOT NULL THEN
        UPDATE categorias SET num_productos = num_productos + 1 WHERE id_categoria = NEW.id_categoria;
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_update_prod_count_after_update $$
CREATE TRIGGER trg_update_prod_count_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NOT (OLD.id_categoria <=> NEW.id_categoria) THEN
        IF OLD.id_categoria IS NOT NULL THEN
            UPDATE categorias SET num_productos = num_productos - 1 WHERE id_categoria = OLD.id_categoria;
        END IF;
        IF NEW.id_categoria IS NOT NULL THEN
            UPDATE categorias SET num_productos = num_productos + 1 WHERE id_categoria = NEW.id_categoria;
        END IF;
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_update_prod_count_after_delete $$
CREATE TRIGGER trg_update_prod_count_after_delete
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
    IF OLD.id_categoria IS NOT NULL THEN
        UPDATE categorias SET num_productos = num_productos - 1 WHERE id_categoria = OLD.id_categoria;
    END IF;
END $$

DELIMITER ;
