-- =====================================================================
-- 08_Extension_Devoluciones.sql
-- EXTENSIÓN del proyecto: Proceso de Devolución Completo.
--
-- Contenido:
--   1) Ajuste al CHECK de ventas.estado para admitir los nuevos estados
--      de devolución ('Devolución Parcial', 'Devuelto Totalmente').
--   2) CREATE TABLE Devoluciones (bitácora/auditoría de cada devolución).
--   3) CREATE PROCEDURE sp_ProcesarDevolucion.
--
-- Prerrequisito: haber ejecutado 01_Esquema_y_Datos.sql (usa las tablas
-- productos, ventas y detalle_ventas ya existentes).
-- Motor objetivo: MySQL 8.0+ (también probado en MariaDB 10.11).
-- =====================================================================
USE ecommerce_db;

-- ---------------------------------------------------------------------
-- 1) Ampliar el CHECK de ventas.estado.
--    La tabla ventas se creó originalmente con un CHECK que solo
--    permitía ('Pendiente de Pago','Procesando','Enviado','Entregado',
--    'Cancelado'). Como esta extensión necesita marcar el pedido como
--    'Devolución Parcial' o 'Devuelto Totalmente', hay que reemplazar
--    esa restricción por una que incluya los dos estados nuevos.
-- ---------------------------------------------------------------------
ALTER TABLE ventas DROP CONSTRAINT chk_estado_venta;

ALTER TABLE ventas ADD CONSTRAINT chk_estado_venta CHECK (
    estado IN (
        'Pendiente de Pago', 'Procesando', 'Enviado', 'Entregado', 'Cancelado',
        'Devolución Parcial', 'Devuelto Totalmente'
    )
);

-- ---------------------------------------------------------------------
-- 2) Tabla Devoluciones: registra cada devolución individual para
--    poder auditarlas y, además, saber cuánto se ha devuelto ya de
--    cada línea de venta (necesario para no permitir devolver más de
--    lo comprado si el procedimiento se llama varias veces sobre la
--    misma línea).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Devoluciones (
    id_devolucion       INT AUTO_INCREMENT PRIMARY KEY,
    id_venta            INT NOT NULL,
    id_producto         INT NOT NULL,
    cantidad_devuelta   INT NOT NULL,
    monto_reembolsado   DECIMAL(12,2) NOT NULL,
    tipo_devolucion     VARCHAR(10) NOT NULL,   -- 'Parcial' o 'Total' (de ESA línea de producto)
    fecha_devolucion    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_cantidad_devuelta_positiva CHECK (cantidad_devuelta > 0),
    CONSTRAINT chk_tipo_devolucion CHECK (tipo_devolucion IN ('Parcial', 'Total')),
    CONSTRAINT fk_devolucion_venta    FOREIGN KEY (id_venta)    REFERENCES ventas(id_venta),
    CONSTRAINT fk_devolucion_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

CREATE INDEX idx_devoluciones_venta ON Devoluciones(id_venta);

DELIMITER $$

-- ---------------------------------------------------------------------
-- 3) sp_ProcesarDevolucion
--
-- Parámetros:
--   p_id_venta          : la venta (encabezado) a la que pertenece la
--                          línea que se está devolviendo.
--   p_id_producto       : el producto devuelto.
--   p_cantidad_devuelta : unidades que el cliente devuelve en esta
--                          operación (puede llamarse varias veces sobre
--                          la misma línea mientras no se exceda el total
--                          comprado).
--
-- Lógica paso a paso:
--   a) Validaciones de entrada (cantidad > 0).
--   b) Bloquea (FOR UPDATE) la línea de detalle_ventas correspondiente,
--      para evitar condiciones de carrera si dos devoluciones del mismo
--      producto se procesaran al mismo tiempo.
--   c) Calcula cuánto se ha devuelto YA de esa línea (sumando
--      Devoluciones previas) y valida que la nueva cantidad no haga que
--      el acumulado supere lo comprado originalmente (requisito #1).
--   d) Incrementa el stock del producto (requisito #2).
--   e) Calcula el monto a reembolsar usando el precio histórico
--      congelado de la venta (detalle_ventas.precio_unitario_congelado),
--      nunca el precio actual del catálogo.
--   f) Inserta el registro de auditoría en Devoluciones (requisito #4),
--      marcando si esta línea quedó 'Parcial' o 'Total'.
--   g) Recalcula el estado de la VENTA completa: si, sumando todas las
--      devoluciones registradas, ya se devolvió el 100% de las unidades
--      de TODOS los productos de la venta, el pedido pasa a
--      'Devuelto Totalmente'; si se devolvió solo una parte, pasa a
--      'Devolución Parcial' (requisito #3).
--   h) Todo corre dentro de una transacción: si cualquier paso falla,
--      se hace ROLLBACK y no queda ningún cambio a medias
--      (requisito #5).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion $$
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta          INT,
    IN p_id_producto       INT,
    IN p_cantidad_devuelta INT
)
sp_body: BEGIN
    DECLARE v_cantidad_comprada     INT;
    DECLARE v_precio_congelado      DECIMAL(12,2);
    DECLARE v_ya_devuelto_linea     INT DEFAULT 0;
    DECLARE v_disponible_devolver   INT;
    DECLARE v_monto_reembolso       DECIMAL(12,2);
    DECLARE v_tipo_linea            VARCHAR(10);
    DECLARE v_total_comprado_venta  INT DEFAULT 0;
    DECLARE v_total_devuelto_venta  INT DEFAULT 0;
    DECLARE v_nuevo_estado_venta    VARCHAR(30);

    -- Si cualquier sentencia dentro de la transacción lanza un error,
    -- se revierte todo y se propaga el error original al llamador.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- a) Validación básica de entrada.
    IF p_cantidad_devuelta IS NULL OR p_cantidad_devuelta <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cantidad a devolver debe ser un entero mayor que cero.';
    END IF;

    START TRANSACTION;

    -- b) Bloquea la línea de detalle_ventas para evitar condiciones de
    --    carrera (dos devoluciones simultáneas sobre la misma línea).
    SELECT cantidad, precio_unitario_congelado
      INTO v_cantidad_comprada, v_precio_congelado
      FROM detalle_ventas
      WHERE id_venta = p_id_venta AND id_producto = p_id_producto
      FOR UPDATE;

    IF v_cantidad_comprada IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El producto indicado no pertenece a esta venta (no existe esa línea en detalle_ventas).';
    END IF;

    -- c) Cuánto se ha devuelto ya de esta línea específica.
    SELECT COALESCE(SUM(cantidad_devuelta), 0)
      INTO v_ya_devuelto_linea
      FROM Devoluciones
      WHERE id_venta = p_id_venta AND id_producto = p_id_producto;

    SET v_disponible_devolver = v_cantidad_comprada - v_ya_devuelto_linea;

    -- Requisito #1: la cantidad a devolver no puede exceder lo comprado
    -- (teniendo en cuenta lo que ya se hubiera devuelto antes).
    IF p_cantidad_devuelta > v_disponible_devolver THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cantidad a devolver excede la cantidad disponible para devolución en esta línea de venta.';
    END IF;

    -- d) Requisito #2: repone el stock del producto devuelto.
    UPDATE productos
       SET stock = stock + p_cantidad_devuelta
       WHERE id_producto = p_id_producto;

    -- e) Monto a reembolsar, usando el precio histórico de la venta
    --    (nunca el precio actual del catálogo, que puede haber cambiado).
    SET v_monto_reembolso = p_cantidad_devuelta * v_precio_congelado;

    -- Determina si esta línea de producto queda totalmente devuelta.
    IF (v_ya_devuelto_linea + p_cantidad_devuelta) >= v_cantidad_comprada THEN
        SET v_tipo_linea = 'Total';
    ELSE
        SET v_tipo_linea = 'Parcial';
    END IF;

    -- f) Requisito #4: inserta el registro de auditoría.
    INSERT INTO Devoluciones (id_venta, id_producto, cantidad_devuelta, monto_reembolsado, tipo_devolucion)
    VALUES (p_id_venta, p_id_producto, p_cantidad_devuelta, v_monto_reembolso, v_tipo_linea);

    -- g) Requisito #3: recalcula el estado de la VENTA completa,
    --    comparando el total de unidades compradas (todas las líneas)
    --    contra el total de unidades devueltas (todas las devoluciones
    --    registradas) para esa misma venta.
    SELECT COALESCE(SUM(cantidad), 0)
      INTO v_total_comprado_venta
      FROM detalle_ventas
      WHERE id_venta = p_id_venta;

    SELECT COALESCE(SUM(cantidad_devuelta), 0)
      INTO v_total_devuelto_venta
      FROM Devoluciones
      WHERE id_venta = p_id_venta;

    IF v_total_devuelto_venta >= v_total_comprado_venta THEN
        SET v_nuevo_estado_venta = 'Devuelto Totalmente';
    ELSE
        SET v_nuevo_estado_venta = 'Devolución Parcial';
    END IF;

    UPDATE ventas
       SET estado = v_nuevo_estado_venta
       WHERE id_venta = p_id_venta;

    -- h) Requisito #5: si se llegó hasta aquí sin errores, se confirma
    --    todo de forma atómica. Si algo hubiera fallado antes, el
    --    EXIT HANDLER ya habría hecho ROLLBACK y ninguno de estos
    --    cambios (stock, Devoluciones, estado de venta) quedaría aplicado.
    COMMIT;
END $$

DELIMITER ;

-- =====================================================================
-- Ejemplo de uso (comentado)
-- =====================================================================
-- Devolver 1 unidad del producto 3 de la venta 1:
-- CALL sp_ProcesarDevolucion(1, 3, 1);
--
-- Verificar el resultado:
-- SELECT * FROM Devoluciones WHERE id_venta = 1;
-- SELECT id_venta, estado, total FROM ventas WHERE id_venta = 1;
-- SELECT id_producto, stock FROM productos WHERE id_producto = 3;
