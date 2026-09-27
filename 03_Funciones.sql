-- =====================================================================
-- 03_Funciones.sql
-- 20 funciones definidas por el usuario (UDFs) para ecommerce_db.
-- Ejecutar después de 01_Esquema_y_Datos.sql
-- =====================================================================
USE ecommerce_db;

DELIMITER $$

-- 1. fn_CalcularTotalVenta: calcula el total de una venta sumando sus detalles.
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta $$
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(14,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2);
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
      INTO v_total
      FROM detalle_ventas
      WHERE id_venta = p_id_venta;
    RETURN v_total;
END $$

-- 2. fn_VerificarDisponibilidadStock: valida si hay stock suficiente.
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock $$
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    RETURN (v_stock IS NOT NULL AND v_stock >= p_cantidad);
END $$

-- 3. fn_ObtenerPrecioProducto: devuelve el precio actual (vigente) de un producto.
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto $$
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(12,2);
    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
    RETURN v_precio;
END $$

-- 4. fn_CalcularEdadCliente: calcula la edad a partir de la fecha de nacimiento.
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente $$
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha_nac DATE;
    SELECT fecha_nacimiento INTO v_fecha_nac FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_fecha_nac IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());
END $$

-- 5. fn_FormatearNombreCompleto: nombre y apellido en formato estandarizado.
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto $$
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(210)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre VARCHAR(100);
    DECLARE v_apellido VARCHAR(100);
    SELECT nombre, apellido INTO v_nombre, v_apellido FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_nombre IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN CONCAT(
        UPPER(LEFT(v_apellido, 1)), LOWER(SUBSTRING(v_apellido, 2)), ', ',
        UPPER(LEFT(v_nombre, 1)), LOWER(SUBSTRING(v_nombre, 2))
    );
END $$

-- 6. fn_EsClienteNuevo: TRUE si su primera compra fue en los últimos 30 días.
DROP FUNCTION IF EXISTS fn_EsClienteNuevo $$
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN (DATEDIFF(NOW(), v_primera_compra) <= 30);
END $$

-- 7. fn_CalcularCostoEnvio: calcula el costo de envío según el peso total de una venta.
--    Tarifa base $8.000 + $3.000 por kg.
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio $$
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(10,3);
    DECLARE v_tarifa_base DECIMAL(10,2) DEFAULT 8000.00;
    DECLARE v_tarifa_kg DECIMAL(10,2) DEFAULT 3000.00;

    SELECT COALESCE(SUM(d.cantidad * p.peso_kg), 0)
      INTO v_peso_total
      FROM detalle_ventas d
      JOIN productos p ON p.id_producto = d.id_producto
      WHERE d.id_venta = p_id_venta;

    IF v_peso_total = 0 THEN
        RETURN 0;
    END IF;

    RETURN v_tarifa_base + (v_peso_total * v_tarifa_kg);
END $$

-- 8. fn_AplicarDescuento: aplica un porcentaje de descuento a un monto.
DROP FUNCTION IF EXISTS fn_AplicarDescuento $$
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(14,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(14,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_porcentaje < 0 OR p_porcentaje > 100 THEN
        RETURN p_monto;
    END IF;
    RETURN ROUND(p_monto - (p_monto * p_porcentaje / 100), 2);
END $$

-- 9. fn_ObtenerUltimaFechaCompra: última compra de un cliente.
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra $$
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_fecha;
END $$

-- 10. fn_ValidarFormatoEmail: valida el formato básico de un correo electrónico.
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail $$
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    RETURN (p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');
END $$

-- 11. fn_ObtenerNombreCategoria: devuelve la categoría de un producto.
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria $$
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre_categoria VARCHAR(100);
    SELECT cat.nombre INTO v_nombre_categoria
      FROM productos p
      JOIN categorias cat ON cat.id_categoria = p.id_categoria
      WHERE p.id_producto = p_id_producto;
    RETURN v_nombre_categoria;
END $$

-- 12. fn_ContarVentasCliente: número total de compras de un cliente (no canceladas).
DROP FUNCTION IF EXISTS fn_ContarVentasCliente $$
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_conteo INT;
    SELECT COUNT(*) INTO v_conteo
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_conteo;
END $$

-- 13. fn_CalcularDiasDesdeUltimaCompra: días transcurridos desde la última compra.
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra $$
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_ultima_fecha
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_ultima_fecha IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(NOW(), v_ultima_fecha);
END $$

-- 14. fn_DeterminarEstadoLealtad: asigna Bronce/Plata/Oro según el gasto total del cliente.
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad $$
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_gastado DECIMAL(14,2);
    SELECT total_gastado INTO v_total_gastado FROM clientes WHERE id_cliente = p_id_cliente;

    IF v_total_gastado IS NULL THEN
        RETURN 'Bronce';
    ELSEIF v_total_gastado >= 1000000 THEN
        RETURN 'Oro';
    ELSEIF v_total_gastado >= 300000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END $$

-- 15. fn_GenerarSKU: genera un SKU único a partir del nombre del producto y la categoría.
DROP FUNCTION IF EXISTS fn_GenerarSKU $$
CREATE FUNCTION fn_GenerarSKU(p_nombre_producto VARCHAR(200), p_id_categoria INT)
RETURNS VARCHAR(50)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_prefijo_categoria VARCHAR(10);
    DECLARE v_prefijo_nombre VARCHAR(10);
    DECLARE v_sufijo INT;

    SELECT UPPER(LEFT(REPLACE(nombre, ' ', ''), 4)) INTO v_prefijo_categoria
      FROM categorias WHERE id_categoria = p_id_categoria;

    IF v_prefijo_categoria IS NULL THEN
        SET v_prefijo_categoria = 'GEN';
    END IF;

    SET v_prefijo_nombre = UPPER(LEFT(REPLACE(p_nombre_producto, ' ', ''), 3));
    SET v_sufijo = FLOOR(100 + RAND() * 900);

    RETURN CONCAT(v_prefijo_categoria, '-', v_prefijo_nombre, '-', v_sufijo);
END $$

-- 16. fn_CalcularIVA: calcula el IVA (19%) sobre un monto.
DROP FUNCTION IF EXISTS fn_CalcularIVA $$
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(14,2))
RETURNS DECIMAL(14,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_tasa_iva DECIMAL(5,4) DEFAULT 0.19;
    RETURN ROUND(p_monto * v_tasa_iva, 2);
END $$

-- 17. fn_ObtenerStockTotalPorCategoria: suma el stock de todos los productos de una categoría.
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria $$
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock_total INT;
    SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
      FROM productos WHERE id_categoria = p_id_categoria;
    RETURN v_stock_total;
END $$

-- 18. fn_EstimarFechaEntrega: fecha estimada de entrega según la ciudad del cliente.
--     Bogotá/Medellín/Bucaramanga: 2 días hábiles simulados; otras ciudades: 5 días.
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega $$
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_dias_entrega INT;

    SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;

    IF v_ciudad IN ('Bogotá', 'Medellín', 'Bucaramanga') THEN
        SET v_dias_entrega = 2;
    ELSE
        SET v_dias_entrega = 5;
    END IF;

    RETURN DATE_ADD(CURDATE(), INTERVAL v_dias_entrega DAY);
END $$

-- 19. fn_ConvertirMoneda: convierte un monto usando una tasa de cambio fija.
DROP FUNCTION IF EXISTS fn_ConvertirMoneda $$
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(14,2), p_tasa_cambio DECIMAL(12,6))
RETURNS DECIMAL(14,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_tasa_cambio IS NULL OR p_tasa_cambio <= 0 THEN
        RETURN NULL;
    END IF;
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END $$

-- 20. fn_ValidarComplejidadContraseña: valida longitud mínima, mayúscula, minúscula,
--     número y carácter especial.
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena $$
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    IF p_contrasena IS NULL OR CHAR_LENGTH(p_contrasena) < 8 THEN
        RETURN FALSE;
    END IF;
    IF p_contrasena NOT REGEXP '[A-Z]' THEN RETURN FALSE; END IF;
    IF p_contrasena NOT REGEXP '[a-z]' THEN RETURN FALSE; END IF;
    IF p_contrasena NOT REGEXP '[0-9]' THEN RETURN FALSE; END IF;
    IF p_contrasena NOT REGEXP '[^A-Za-z0-9]' THEN RETURN FALSE; END IF;
    RETURN TRUE;
END $$

DELIMITER ;

-- =====================================================================
-- Ejemplos de uso (comentados)
-- =====================================================================
-- SELECT fn_CalcularTotalVenta(1);
-- SELECT fn_VerificarDisponibilidadStock(1, 5);
-- SELECT fn_FormatearNombreCompleto(1);
-- SELECT fn_DeterminarEstadoLealtad(1);
-- SELECT fn_ValidarComplejidadContrasena('Clave$2026');
