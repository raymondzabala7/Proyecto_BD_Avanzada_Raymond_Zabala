-- =====================================================================
-- 02_Consultas_Avanzadas.sql
-- 20 consultas de análisis y reporteo sobre la base ecommerce_db.
-- Ejecutar después de 01_Esquema_y_Datos.sql
-- =====================================================================
USE ecommerce_db;

-- 1. Top 10 Productos Más Vendidos (por ingresos generados)
SELECT
    p.id_producto,
    p.nombre,
    SUM(d.cantidad) AS unidades_vendidas,
    SUM(d.cantidad * d.precio_unitario_congelado) AS ingresos_generados
FROM detalle_ventas d
JOIN productos p ON p.id_producto = d.id_producto
JOIN ventas v ON v.id_venta = d.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_generados DESC
LIMIT 10;

-- 2. Productos con Bajas Ventas (10% inferior por unidades vendidas, incluyendo los que no se han vendido)
WITH ventas_por_producto AS (
    SELECT p.id_producto, p.nombre,
           COALESCE(SUM(d.cantidad), 0) AS unidades_vendidas
    FROM productos p
    LEFT JOIN detalle_ventas d ON d.id_producto = p.id_producto
    LEFT JOIN ventas v ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
    GROUP BY p.id_producto, p.nombre
),
ranked AS (
    SELECT *, PERCENT_RANK() OVER (ORDER BY unidades_vendidas ASC) AS pr
    FROM ventas_por_producto
)
SELECT id_producto, nombre, unidades_vendidas
FROM ranked
WHERE pr <= 0.10
ORDER BY unidades_vendidas ASC;

-- 3. Clientes VIP: Top 5 por valor de vida (LTV = gasto total histórico en ventas no canceladas)
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    SUM(v.total) AS ltv_total
FROM clientes c
JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
GROUP BY c.id_cliente, cliente
ORDER BY ltv_total DESC
LIMIT 5;

-- 4. Análisis de Ventas Mensuales (agrupadas por año y mes)
SELECT
    YEAR(v.fecha_venta) AS anio,
    MONTH(v.fecha_venta) AS mes,
    COUNT(DISTINCT v.id_venta) AS num_ventas,
    SUM(v.total) AS total_vendido
FROM ventas v
WHERE v.estado <> 'Cancelado'
GROUP BY YEAR(v.fecha_venta), MONTH(v.fecha_venta)
ORDER BY anio, mes;

-- 5. Crecimiento de Clientes: nuevos clientes registrados por trimestre
SELECT
    YEAR(fecha_registro) AS anio,
    QUARTER(fecha_registro) AS trimestre,
    COUNT(*) AS nuevos_clientes
FROM clientes
GROUP BY YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY anio, trimestre;

-- 6. Tasa de Compra Repetida: % de clientes con más de una compra (no canceladas)
SELECT
    ROUND(
        100.0 * SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END) / COUNT(*), 2
    ) AS porcentaje_clientes_recurrentes
FROM (
    SELECT c.id_cliente, COUNT(v.id_venta) AS num_compras
    FROM clientes c
    LEFT JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    GROUP BY c.id_cliente
) t;

-- 7. Productos Comprados Juntos Frecuentemente (pares de productos en la misma venta)
SELECT
    p1.nombre AS producto_a,
    p2.nombre AS producto_b,
    COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas d1
JOIN detalle_ventas d2 ON d1.id_venta = d2.id_venta AND d1.id_producto < d2.id_producto
JOIN productos p1 ON p1.id_producto = d1.id_producto
JOIN productos p2 ON p2.id_producto = d2.id_producto
GROUP BY p1.nombre, p2.nombre
ORDER BY veces_comprados_juntos DESC
LIMIT 10;

-- 8. Rotación de Inventario por Categoría (unidades vendidas / stock actual promedio)
SELECT
    cat.id_categoria,
    cat.nombre AS categoria,
    COALESCE(SUM(d.cantidad), 0) AS unidades_vendidas,
    SUM(p.stock) AS stock_actual_total,
    ROUND(COALESCE(SUM(d.cantidad), 0) / NULLIF(SUM(p.stock), 0), 2) AS tasa_rotacion
FROM categorias cat
JOIN productos p ON p.id_categoria = cat.id_categoria
LEFT JOIN detalle_ventas d ON d.id_producto = p.id_producto
LEFT JOIN ventas v ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
GROUP BY cat.id_categoria, cat.nombre
ORDER BY tasa_rotacion DESC;

-- 9. Productos que Necesitan Reabastecimiento (stock por debajo del umbral mínimo)
SELECT id_producto, nombre, stock, stock_minimo
FROM productos
WHERE stock < stock_minimo AND activo = TRUE
ORDER BY (stock_minimo - stock) DESC;

-- 10. Análisis de Carrito Abandonado: carritos activos sin conversión a venta hace más de 24h
SELECT
    ca.id_carrito,
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    ca.fecha_creacion,
    TIMESTAMPDIFF(HOUR, ca.fecha_creacion, NOW()) AS horas_desde_creacion,
    COUNT(cd.id_carrito_detalle) AS productos_en_carrito
FROM carritos ca
JOIN clientes c ON c.id_cliente = ca.id_cliente
JOIN carrito_detalle cd ON cd.id_carrito = ca.id_carrito
WHERE ca.estado = 'Activo'
  AND ca.fecha_creacion < DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY ca.id_carrito, c.id_cliente, cliente, ca.fecha_creacion;

-- 11. Rendimiento de Proveedores (ranking por ingresos generados por sus productos)
SELECT
    prov.id_proveedor,
    prov.nombre AS proveedor,
    COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0) AS ingresos_generados,
    RANK() OVER (ORDER BY COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0) DESC) AS ranking
FROM proveedores prov
LEFT JOIN productos p ON p.id_proveedor = prov.id_proveedor
LEFT JOIN detalle_ventas d ON d.id_producto = p.id_producto
LEFT JOIN ventas v ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
GROUP BY prov.id_proveedor, prov.nombre
ORDER BY ingresos_generados DESC;

-- 12. Análisis Geográfico de Ventas (por ciudad del cliente)
SELECT
    c.ciudad,
    COUNT(DISTINCT v.id_venta) AS num_ventas,
    SUM(v.total) AS total_vendido
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.ciudad
ORDER BY total_vendido DESC;

-- 13. Ventas por Hora del Día (para identificar horas pico)
SELECT
    HOUR(fecha_venta) AS hora_del_dia,
    COUNT(*) AS num_ventas,
    SUM(total) AS total_vendido
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY HOUR(fecha_venta)
ORDER BY num_ventas DESC;

-- 14. Impacto de Promociones: ventas de un producto antes/durante/después de una campaña
-- (usa el código 'VERANO10' sobre el producto 6, vigente del 2025-12-01 al 2025-12-31)
SELECT
    CASE
        WHEN v.fecha_venta < promo.fecha_inicio THEN 'Antes'
        WHEN v.fecha_venta BETWEEN promo.fecha_inicio AND promo.fecha_fin THEN 'Durante'
        ELSE 'Después'
    END AS periodo,
    SUM(d.cantidad) AS unidades_vendidas,
    SUM(d.cantidad * d.precio_unitario_congelado) AS ingresos
FROM codigos_descuento promo
JOIN detalle_ventas d ON d.id_producto = promo.id_producto
JOIN ventas v ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
WHERE promo.codigo = 'VERANO10'
GROUP BY periodo
ORDER BY FIELD(periodo, 'Antes', 'Durante', 'Después');

-- 15. Análisis de Cohort: retención de clientes mes a mes desde su primera compra
WITH primera_compra AS (
    SELECT id_cliente, MIN(DATE_FORMAT(fecha_venta, '%Y-%m-01')) AS mes_cohort
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
),
actividad AS (
    SELECT v.id_cliente,
           DATE_FORMAT(v.fecha_venta, '%Y-%m-01') AS mes_actividad,
           pc.mes_cohort
    FROM ventas v
    JOIN primera_compra pc ON pc.id_cliente = v.id_cliente
    WHERE v.estado <> 'Cancelado'
)
SELECT
    mes_cohort,
    TIMESTAMPDIFF(MONTH, mes_cohort, mes_actividad) AS mes_relativo,
    COUNT(DISTINCT id_cliente) AS clientes_activos
FROM actividad
GROUP BY mes_cohort, mes_relativo
ORDER BY mes_cohort, mes_relativo;

-- 16. Margen de Beneficio por Producto (precio de venta vs costo del proveedor)
SELECT
    id_producto,
    nombre,
    precio,
    costo,
    (precio - costo) AS margen_absoluto,
    ROUND(100.0 * (precio - costo) / precio, 2) AS margen_porcentual
FROM productos
ORDER BY margen_porcentual DESC;

-- 17. Tiempo Promedio Entre Compras (por cliente, en días, y promedio general)
WITH compras_ordenadas AS (
    SELECT id_cliente, fecha_venta,
           LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS compra_anterior
    FROM ventas
    WHERE estado <> 'Cancelado'
)
SELECT
    id_cliente,
    ROUND(AVG(TIMESTAMPDIFF(DAY, compra_anterior, fecha_venta)), 1) AS promedio_dias_entre_compras
FROM compras_ordenadas
WHERE compra_anterior IS NOT NULL
GROUP BY id_cliente
ORDER BY promedio_dias_entre_compras ASC;

-- 18. Productos Más Vistos vs. Comprados
SELECT
    p.id_producto,
    p.nombre,
    COALESCE(vistas.total_vistas, 0) AS total_vistas,
    COALESCE(compras.total_comprados, 0) AS total_comprados,
    ROUND(COALESCE(compras.total_comprados, 0) / NULLIF(vistas.total_vistas, 0), 3) AS tasa_conversion
FROM productos p
LEFT JOIN (
    SELECT id_producto, COUNT(*) AS total_vistas
    FROM producto_vistas GROUP BY id_producto
) vistas ON vistas.id_producto = p.id_producto
LEFT JOIN (
    SELECT d.id_producto, SUM(d.cantidad) AS total_comprados
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
    GROUP BY d.id_producto
) compras ON compras.id_producto = p.id_producto
WHERE vistas.total_vistas IS NOT NULL OR compras.total_comprados IS NOT NULL
ORDER BY total_vistas DESC;

-- 19. Segmentación de Clientes (RFM: Recencia, Frecuencia, Monetario)
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    DATEDIFF(NOW(), MAX(v.fecha_venta)) AS recencia_dias,
    COUNT(v.id_venta) AS frecuencia_compras,
    SUM(v.total) AS monetario_total,
    NTILE(4) OVER (ORDER BY DATEDIFF(NOW(), MAX(v.fecha_venta)) DESC) AS score_recencia,
    NTILE(4) OVER (ORDER BY COUNT(v.id_venta) ASC) AS score_frecuencia,
    NTILE(4) OVER (ORDER BY SUM(v.total) ASC) AS score_monetario
FROM clientes c
JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
GROUP BY c.id_cliente, cliente
ORDER BY monetario_total DESC;

-- 20. Predicción de Demanda Simple: proyección del próximo mes para una categoría
-- (promedio móvil de las ventas mensuales de la categoría 'Electrónica')
WITH ventas_mensuales_categoria AS (
    SELECT
        DATE_FORMAT(v.fecha_venta, '%Y-%m') AS mes,
        SUM(d.cantidad) AS unidades_vendidas
    FROM detalle_ventas d
    JOIN productos p ON p.id_producto = d.id_producto
    JOIN categorias cat ON cat.id_categoria = p.id_categoria
    JOIN ventas v ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
    WHERE cat.nombre = 'Electrónica'
    GROUP BY DATE_FORMAT(v.fecha_venta, '%Y-%m')
)
SELECT
    mes,
    unidades_vendidas,
    ROUND(AVG(unidades_vendidas) OVER (
        ORDER BY mes
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1) AS promedio_movil_3_meses,
    -- Proyección simple: el promedio móvil de los últimos 3 meses se usa como
    -- estimado ingenuo de la demanda del mes siguiente.
    ROUND(AVG(unidades_vendidas) OVER (
        ORDER BY mes
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1) AS proyeccion_unidades_prox_mes
FROM ventas_mensuales_categoria
ORDER BY mes;
