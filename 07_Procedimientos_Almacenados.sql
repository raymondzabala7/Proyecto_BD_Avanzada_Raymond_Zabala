-- =====================================================================
-- 07_Procedimientos_Almacenados.sql
-- 20 procedimientos almacenados para ecommerce_db.
-- Ejecutar después de 01 a 06.
-- =====================================================================
USE ecommerce_db;

-- Tabla de apoyo para el procedimiento de ajuste manual de stock
CREATE TABLE IF NOT EXISTS log_ajustes_stock (
    id_ajuste     INT AUTO_INCREMENT PRIMARY KEY,
    id_producto   INT NOT NULL,
    stock_anterior INT NOT NULL,
    stock_nuevo    INT NOT NULL,
    motivo         VARCHAR(255) NOT NULL,
    fecha_ajuste   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. sp_RealizarNuevaVenta: procesa una venta completa de forma transaccional.
--    p_items_json: arreglo JSON, ej. '[{"id_producto":1,"cantidad":2},{"id_producto":3,"cantidad":1}]'
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta $$
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_sucursal INT,
    IN p_items_json JSON,
    OUT p_id_venta_generada INT
)
proc_body: BEGIN
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio DECIMAL(12,2);
    -- Nota: el cursor NO hace JOIN contra productos; solo lee el JSON de
    -- entrada. Esto evita el error de MySQL "Can't update table 'productos'
    -- in stored function/trigger because it is already used by statement
    -- which invoked this stored function/trigger", ya que los triggers de
    -- detalle_ventas (trg_check_stock_before_insert_venta y
    -- trg_update_stock_after_insert_venta) necesitan leer y modificar
    -- productos, y esa tabla no puede estar ya "en uso" por el INSERT que
    -- disparó el trigger.
    DECLARE cur CURSOR FOR
        SELECT id_producto, cantidad
        FROM JSON_TABLE(
            p_items_json, '$[*]'
            COLUMNS (
                id_producto INT PATH '$.id_producto',
                cantidad    INT PATH '$.cantidad'
            )
        ) AS jt;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO ventas (id_cliente, id_sucursal, estado, total)
    VALUES (p_id_cliente, p_id_sucursal, 'Pendiente de Pago', 0);

    SET p_id_venta_generada = LAST_INSERT_ID();

    OPEN cur;
    items_loop: LOOP
        FETCH cur INTO v_id_producto, v_cantidad;
        IF v_done THEN
            LEAVE items_loop;
        END IF;

        SELECT precio INTO v_precio FROM productos WHERE id_producto = v_id_producto;

        INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
        VALUES (p_id_venta_generada, v_id_producto, v_cantidad, v_precio);
    END LOOP;
    CLOSE cur;

    COMMIT;
END $$

-- ---------------------------------------------------------------------
-- 2. sp_AgregarNuevoProducto
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto $$
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(200),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(12,2),
    IN p_costo DECIMAL(12,2),
    IN p_stock INT,
    IN p_sku VARCHAR(50),
    IN p_id_categoria INT,
    IN p_id_proveedor INT,
    IN p_peso_kg DECIMAL(8,3),
    OUT p_id_producto_generado INT
)
BEGIN
    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor, peso_kg)
    VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock, p_sku, p_id_categoria, p_id_proveedor, p_peso_kg);

    SET p_id_producto_generado = LAST_INSERT_ID();
END $$

-- ---------------------------------------------------------------------
-- 3. sp_ActualizarDireccionCliente
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente $$
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion VARCHAR(255),
    IN p_nueva_ciudad VARCHAR(100)
)
BEGIN
    UPDATE clientes
       SET direccion_envio = p_nueva_direccion,
           ciudad = p_nueva_ciudad
       WHERE id_cliente = p_id_cliente;
END $$

-- ---------------------------------------------------------------------
-- 4. sp_ProcesarDevolucion: repone stock y ajusta el total de la venta.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion $$
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_detalle INT,
    IN p_cantidad_devuelta INT
)
BEGIN
    DECLARE v_id_producto INT;
    DECLARE v_id_venta INT;
    DECLARE v_precio_congelado DECIMAL(12,2);
    DECLARE v_cantidad_original INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT id_producto, id_venta, precio_unitario_congelado, cantidad
      INTO v_id_producto, v_id_venta, v_precio_congelado, v_cantidad_original
      FROM detalle_ventas
      WHERE id_detalle = p_id_detalle
      FOR UPDATE;

    IF p_cantidad_devuelta > v_cantidad_original THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad a devolver excede la cantidad comprada.';
    END IF;

    -- Repone el stock devuelto
    UPDATE productos SET stock = stock + p_cantidad_devuelta WHERE id_producto = v_id_producto;

    -- Reduce la cantidad en el detalle (el crédito equivale a cantidad * precio congelado)
    UPDATE detalle_ventas
       SET cantidad = cantidad - p_cantidad_devuelta
       WHERE id_detalle = p_id_detalle;

    -- El trigger trg_recalc_total_after_update_detalle recalcula automáticamente
    -- el total de la venta.

    COMMIT;
END $$

-- ---------------------------------------------------------------------
-- 5. sp_ObtenerHistorialComprasCliente
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente $$
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT
        v.id_venta, v.fecha_venta, v.estado, v.total,
        p.nombre AS producto, d.cantidad, d.precio_unitario_congelado
    FROM ventas v
    JOIN detalle_ventas d ON d.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = d.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END $$

-- ---------------------------------------------------------------------
-- 6. sp_AjustarNivelStock: ajuste manual con registro de motivo.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock $$
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_nuevo_stock INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_stock_anterior INT;

    IF p_nuevo_stock < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El nuevo stock no puede ser negativo.';
    END IF;

    SELECT stock INTO v_stock_anterior FROM productos WHERE id_producto = p_id_producto;

    UPDATE productos SET stock = p_nuevo_stock WHERE id_producto = p_id_producto;

    INSERT INTO log_ajustes_stock (id_producto, stock_anterior, stock_nuevo, motivo)
    VALUES (p_id_producto, v_stock_anterior, p_nuevo_stock, p_motivo);
END $$

-- ---------------------------------------------------------------------
-- 7. sp_EliminarClienteDeFormaSegura: anonimiza en vez de borrar (soft-delete).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura $$
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
       SET nombre = 'Cliente',
           apellido = CONCAT('Eliminado_', id_cliente),
           email = CONCAT('eliminado_', id_cliente, '@anonimo.local'),
           contrasena_hash = 'ANONIMIZADO',
           direccion_envio = NULL,
           ciudad = NULL,
           fecha_nacimiento = NULL,
           activo = FALSE
       WHERE id_cliente = p_id_cliente;
END $$

-- ---------------------------------------------------------------------
-- 8. sp_AplicarDescuentoPorCategoria
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria $$
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje DECIMAL(5,2)
)
BEGIN
    UPDATE productos
       SET precio = fn_AplicarDescuento(precio, p_porcentaje)
       WHERE id_categoria = p_id_categoria;
END $$

-- ---------------------------------------------------------------------
-- 9. sp_GenerarReporteMensualVentas
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas $$
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_anio INT,
    IN p_mes INT
)
BEGIN
    SELECT
        COUNT(DISTINCT v.id_venta) AS num_ventas,
        COALESCE(SUM(v.total), 0) AS total_vendido,
        ROUND(COALESCE(AVG(v.total), 0), 2) AS ticket_promedio,
        COUNT(DISTINCT v.id_cliente) AS clientes_distintos
    FROM ventas v
    WHERE YEAR(v.fecha_venta) = p_anio
      AND MONTH(v.fecha_venta) = p_mes
      AND v.estado <> 'Cancelado';

    SELECT p.nombre, SUM(d.cantidad) AS unidades, SUM(d.cantidad * d.precio_unitario_congelado) AS ingresos
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    JOIN productos p ON p.id_producto = d.id_producto
    WHERE YEAR(v.fecha_venta) = p_anio AND MONTH(v.fecha_venta) = p_mes AND v.estado <> 'Cancelado'
    GROUP BY p.nombre
    ORDER BY ingresos DESC;
END $$

-- ---------------------------------------------------------------------
-- 10. sp_CambiarEstadoPedido
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido $$
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(30)
)
BEGIN
    IF p_nuevo_estado NOT IN ('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado de pedido no válido.';
    END IF;

    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
    -- El trigger trg_log_order_status_change registra el cambio automáticamente,
    -- y aquí es donde, en un sistema real, se notificaría a otros sistemas
    -- (ej. mediante una cola de mensajes o un webhook desde la capa de aplicación).
END $$

-- ---------------------------------------------------------------------
-- 11. sp_RegistrarNuevoCliente: valida que el email no exista.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente $$
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100),
    IN p_apellido VARCHAR(100),
    IN p_email VARCHAR(150),
    IN p_contrasena_hash VARCHAR(255),
    IN p_direccion VARCHAR(255),
    IN p_ciudad VARCHAR(100),
    IN p_fecha_nacimiento DATE,
    IN p_id_sucursal INT,
    OUT p_id_cliente_generado INT
)
BEGIN
    IF EXISTS (SELECT 1 FROM clientes WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un cliente registrado con ese correo electrónico.';
    END IF;

    INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio, ciudad, fecha_nacimiento, id_sucursal)
    VALUES (p_nombre, p_apellido, p_email, p_contrasena_hash, p_direccion, p_ciudad, p_fecha_nacimiento, p_id_sucursal);

    SET p_id_cliente_generado = LAST_INSERT_ID();
END $$

-- ---------------------------------------------------------------------
-- 12. sp_ObtenerDetallesProductoCompleto
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto $$
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT
        p.*,
        cat.nombre AS nombre_categoria,
        prov.nombre AS nombre_proveedor,
        prov.email_contacto AS email_proveedor
    FROM productos p
    LEFT JOIN categorias cat ON cat.id_categoria = p.id_categoria
    LEFT JOIN proveedores prov ON prov.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END $$

-- ---------------------------------------------------------------------
-- 13. sp_FusionarCuentasCliente: mueve las ventas de la cuenta duplicada
--     a la cuenta principal y desactiva la duplicada.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente $$
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_principal INT,
    IN p_id_cliente_duplicado INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_id_cliente_principal = p_id_cliente_duplicado THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede fusionar una cuenta consigo misma.';
    END IF;

    START TRANSACTION;

    UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    UPDATE carritos SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    UPDATE resenas_productos SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;

    UPDATE clientes
       SET total_gastado = (
               SELECT COALESCE(SUM(total), 0) FROM ventas
               WHERE id_cliente = p_id_cliente_principal AND estado <> 'Cancelado'
           )
       WHERE id_cliente = p_id_cliente_principal;

    UPDATE clientes
       SET activo = FALSE,
           email = CONCAT('fusionado_', id_cliente, '@anonimo.local')
       WHERE id_cliente = p_id_cliente_duplicado;

    COMMIT;
END $$

-- ---------------------------------------------------------------------
-- 14. sp_AsignarProductoAProveedor
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor $$
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT
)
BEGIN
    UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
END $$

-- ---------------------------------------------------------------------
-- 15. sp_BuscarProductos: búsqueda avanzada con filtros opcionales.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_BuscarProductos $$
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(200),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(12,2),
    IN p_precio_max DECIMAL(12,2)
)
BEGIN
    SELECT p.*, cat.nombre AS categoria
    FROM productos p
    LEFT JOIN categorias cat ON cat.id_categoria = p.id_categoria
    WHERE p.activo = TRUE
      AND (p_nombre IS NULL OR p.nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
      AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
    ORDER BY p.nombre;
END $$

-- ---------------------------------------------------------------------
-- 16. sp_ObtenerDashboardAdmin
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin $$
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ventas_hoy,
        (SELECT COALESCE(SUM(total), 0) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ingresos_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE()) AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM productos WHERE stock < stock_minimo AND activo = TRUE) AS productos_bajo_stock,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Procesando') AS pedidos_en_proceso;
END $$

-- ---------------------------------------------------------------------
-- 17. sp_ProcesarPago: simula el procesamiento de un pago para una venta.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarPago $$
CREATE PROCEDURE sp_ProcesarPago(IN p_id_venta INT)
BEGIN
    DECLARE v_estado_actual VARCHAR(30);
    SELECT estado INTO v_estado_actual FROM ventas WHERE id_venta = p_id_venta;

    IF v_estado_actual <> 'Pendiente de Pago' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden procesar pagos de ventas Pendientes de Pago.';
    END IF;

    UPDATE ventas SET estado = 'Procesando' WHERE id_venta = p_id_venta;
END $$

-- ---------------------------------------------------------------------
-- 18. sp_AñadirReseñaProducto: valida que el cliente haya comprado el producto.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto $$
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_cliente INT,
    IN p_id_producto INT,
    IN p_calificacion TINYINT,
    IN p_comentario TEXT
)
BEGIN
    DECLARE v_compro INT DEFAULT 0;

    SELECT COUNT(*) INTO v_compro
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    WHERE v.id_cliente = p_id_cliente AND d.id_producto = p_id_producto AND v.estado <> 'Cancelado';

    IF v_compro = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente debe haber comprado el producto para poder reseñarlo.';
    END IF;

    IF p_calificacion NOT BETWEEN 1 AND 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La calificación debe estar entre 1 y 5.';
    END IF;

    INSERT INTO resenas_productos (id_producto, id_cliente, calificacion, comentario)
    VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
END $$

-- ---------------------------------------------------------------------
-- 19. sp_ObtenerProductosRelacionados: productos comprados junto al dado.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados $$
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT p2.id_producto, p2.nombre, COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas d1
    JOIN detalle_ventas d2 ON d1.id_venta = d2.id_venta AND d1.id_producto <> d2.id_producto
    JOIN productos p2 ON p2.id_producto = d2.id_producto
    WHERE d1.id_producto = p_id_producto
    GROUP BY p2.id_producto, p2.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END $$

-- ---------------------------------------------------------------------
-- 20. sp_MoverProductosEntreCategorias
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias $$
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_id_categoria_origen INT,
    IN p_id_categoria_destino INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM categorias WHERE id_categoria = p_id_categoria_destino) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La categoría destino no existe.';
    END IF;

    START TRANSACTION;
    UPDATE productos
       SET id_categoria = p_id_categoria_destino
       WHERE id_categoria = p_id_categoria_origen;
    COMMIT;
END $$

DELIMITER ;

-- =====================================================================
-- Permisos que dependían de que estos procedimientos existieran
-- (requisito de seguridad #12 de 04_Seguridad.sql: Gerente_Marketing
-- puede ejecutar los procedimientos de reportes de marketing).
-- =====================================================================
GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';
GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_ObtenerDashboardAdmin TO 'Gerente_Marketing';

-- =====================================================================
-- Ejemplos de uso (comentados)
-- =====================================================================
-- CALL sp_RealizarNuevaVenta(1, 1, '[{"id_producto":3,"cantidad":1}]', @id_venta);
-- SELECT @id_venta;
-- CALL sp_ObtenerHistorialComprasCliente(1);
-- CALL sp_BuscarProductos('Camiseta', NULL, NULL, NULL);
-- CALL sp_ObtenerDashboardAdmin();
