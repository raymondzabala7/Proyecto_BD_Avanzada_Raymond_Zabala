-- =====================================================================
-- 01_Esquema_y_Datos.sql
-- Proyecto: Base de Datos de un E-commerce
-- Contenido: Creación del esquema completo (CREATE TABLE) y carga de
--            datos de ejemplo (INSERT INTO) para poder probar el resto
--            de los scripts (consultas, funciones, seguridad, triggers,
--            eventos y procedimientos almacenados).
-- Motor objetivo: MySQL 8.0+ (usa CHECK constraints, roles, eventos, etc.)
-- =====================================================================

DROP DATABASE IF EXISTS ecommerce_db;
CREATE DATABASE ecommerce_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ecommerce_db;

-- ---------------------------------------------------------------------
-- Tabla: sucursales
-- Nota: se añade para soportar el requisito de seguridad #19
-- (los usuarios solo ven las ventas de su propia sucursal).
-- ---------------------------------------------------------------------
CREATE TABLE sucursales (
    id_sucursal   INT AUTO_INCREMENT PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL,
    ciudad        VARCHAR(100) NOT NULL
);

-- ---------------------------------------------------------------------
-- Tabla: categorias
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria    INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL UNIQUE,
    descripcion     TEXT,
    num_productos   INT NOT NULL DEFAULT 0,          -- mantenido por trigger
    fecha_creacion  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- Tabla: proveedores
-- ---------------------------------------------------------------------
CREATE TABLE proveedores (
    id_proveedor        INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(150) NOT NULL,
    email_contacto      VARCHAR(150) UNIQUE,
    telefono_contacto   VARCHAR(30),
    fecha_registro      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- Tabla: productos
-- ---------------------------------------------------------------------
CREATE TABLE productos (
    id_producto         INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(200) NOT NULL UNIQUE,
    descripcion         TEXT,
    precio              DECIMAL(12,2) NOT NULL,
    costo               DECIMAL(12,2) NOT NULL,
    stock               INT NOT NULL DEFAULT 0,
    stock_minimo        INT NOT NULL DEFAULT 5,
    sku                 VARCHAR(50) NOT NULL UNIQUE,
    peso_kg             DECIMAL(8,3) NOT NULL DEFAULT 0.500,
    id_categoria        INT NULL,
    id_proveedor        INT NULL,
    fecha_creacion      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion  DATETIME NULL,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_precio_positivo    CHECK (precio > 0),
    CONSTRAINT chk_costo_no_negativo  CHECK (costo >= 0),
    CONSTRAINT chk_stock_no_negativo  CHECK (stock >= 0),
    CONSTRAINT fk_producto_categoria  FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria) ON DELETE SET NULL,
    CONSTRAINT fk_producto_proveedor  FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------
-- Tabla: clientes
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente          INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(100) NOT NULL,
    apellido            VARCHAR(100) NOT NULL,
    email               VARCHAR(150) NOT NULL UNIQUE,
    contrasena_hash     VARCHAR(255) NOT NULL,
    direccion_envio     VARCHAR(255),
    ciudad              VARCHAR(100),
    fecha_nacimiento    DATE,
    id_sucursal         INT NULL,
    total_gastado       DECIMAL(14,2) NOT NULL DEFAULT 0,   -- mantenido por trigger
    nivel_lealtad       VARCHAR(20) NOT NULL DEFAULT 'Bronce',
    fecha_registro      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_ultima_compra DATETIME NULL,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_cliente_sucursal FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------
-- Tabla: ventas (encabezado de la orden)
-- ---------------------------------------------------------------------
CREATE TABLE ventas (
    id_venta      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente    INT NOT NULL,
    id_sucursal   INT NULL,
    fecha_venta   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado        VARCHAR(30) NOT NULL DEFAULT 'Pendiente de Pago',
    total         DECIMAL(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_estado_venta CHECK (estado IN ('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado')),
    CONSTRAINT fk_venta_cliente   FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
    CONSTRAINT fk_venta_sucursal  FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
);

-- ---------------------------------------------------------------------
-- Tabla: detalle_ventas (líneas de la orden)
-- ---------------------------------------------------------------------
CREATE TABLE detalle_ventas (
    id_detalle                  INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                    INT NOT NULL,
    id_producto                 INT NOT NULL,
    cantidad                    INT NOT NULL,
    precio_unitario_congelado   DECIMAL(12,2) NOT NULL,
    CONSTRAINT chk_cantidad_positiva CHECK (cantidad > 0),
    CONSTRAINT fk_detalle_venta     FOREIGN KEY (id_venta) REFERENCES ventas(id_venta) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto  FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

-- ---------------------------------------------------------------------
-- Tablas de apoyo para consultas/triggers/eventos avanzados
-- ---------------------------------------------------------------------

-- Carritos de compra (para el análisis de carrito abandonado)
CREATE TABLE carritos (
    id_carrito      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente      INT NOT NULL,
    fecha_creacion  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado          VARCHAR(20) NOT NULL DEFAULT 'Activo',   -- Activo, Abandonado, Convertido
    CONSTRAINT fk_carrito_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

CREATE TABLE carrito_detalle (
    id_carrito_detalle  INT AUTO_INCREMENT PRIMARY KEY,
    id_carrito          INT NOT NULL,
    id_producto         INT NOT NULL,
    cantidad            INT NOT NULL DEFAULT 1,
    fecha_agregado      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_cd_carrito  FOREIGN KEY (id_carrito) REFERENCES carritos(id_carrito) ON DELETE CASCADE,
    CONSTRAINT fk_cd_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

-- Vistas de producto (para comparar "más vistos" vs "más comprados")
CREATE TABLE producto_vistas (
    id_vista     INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    id_cliente   INT NULL,
    fecha_vista  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_vista_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
    CONSTRAINT fk_vista_cliente  FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

-- Reseñas de producto
CREATE TABLE resenas_productos (
    id_resena      INT AUTO_INCREMENT PRIMARY KEY,
    id_producto    INT NOT NULL,
    id_cliente     INT NOT NULL,
    calificacion   TINYINT NOT NULL,
    comentario     TEXT,
    fecha_resena   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_calificacion CHECK (calificacion BETWEEN 1 AND 5),
    CONSTRAINT fk_resena_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
    CONSTRAINT fk_resena_cliente  FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

-- Códigos de descuento / promociones
CREATE TABLE codigos_descuento (
    id_codigo     INT AUTO_INCREMENT PRIMARY KEY,
    codigo        VARCHAR(50) NOT NULL UNIQUE,
    id_producto   INT NULL,
    porcentaje    DECIMAL(5,2) NOT NULL,
    fecha_inicio  DATETIME NOT NULL,
    fecha_fin     DATETIME NOT NULL,
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_codigo_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

-- Programa de referidos (para el trigger anti auto-referencia)
CREATE TABLE programa_referidos (
    id_referido            INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente_referidor   INT NOT NULL,
    id_cliente_referido    INT NOT NULL,
    fecha_referido         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ref_referidor FOREIGN KEY (id_cliente_referidor) REFERENCES clientes(id_cliente),
    CONSTRAINT fk_ref_referido  FOREIGN KEY (id_cliente_referido)  REFERENCES clientes(id_cliente)
);

-- Log de intentos de inicio de sesión (requisito de seguridad #20)
CREATE TABLE log_login_intentos (
    id_log         INT AUTO_INCREMENT PRIMARY KEY,
    usuario        VARCHAR(150),
    exito          BOOLEAN,
    ip_origen      VARCHAR(45),
    fecha_intento  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de permisos a nivel de aplicación (para poder auditar cambios
-- de permisos con un trigger, ya que MySQL no permite triggers sobre
-- mysql.user directamente).
CREATE TABLE permisos_usuarios (
    id_permiso    INT AUTO_INCREMENT PRIMARY KEY,
    usuario_bd    VARCHAR(100) NOT NULL,
    rol_asignado  VARCHAR(100) NOT NULL,
    fecha_asignacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- Índices adicionales recomendados
-- ---------------------------------------------------------------------
CREATE INDEX idx_productos_categoria ON productos(id_categoria);
CREATE INDEX idx_productos_proveedor ON productos(id_proveedor);
CREATE INDEX idx_ventas_cliente ON ventas(id_cliente);
CREATE INDEX idx_ventas_fecha ON ventas(fecha_venta);
CREATE INDEX idx_detalle_venta ON detalle_ventas(id_venta);
CREATE INDEX idx_detalle_producto ON detalle_ventas(id_producto);

-- =====================================================================
-- CARGA DE DATOS DE EJEMPLO
-- =====================================================================

-- Sucursales
INSERT INTO sucursales (nombre, ciudad) VALUES
('Sucursal Bogotá', 'Bogotá'),
('Sucursal Medellín', 'Medellín'),
('Sucursal Bucaramanga', 'Bucaramanga');

-- Categorías (incluye 'General' usada por el trigger de categoría por defecto)
INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica', 'Dispositivos electrónicos, gadgets y accesorios tecnológicos'),
('Ropa', 'Prendas de vestir para hombre, mujer y niños'),
('Hogar', 'Artículos para el hogar y la cocina'),
('Deportes', 'Equipamiento y ropa deportiva'),
('Libros', 'Libros físicos de distintos géneros'),
('General', 'Categoría por defecto para productos sin clasificar');

-- Proveedores
INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TechImport S.A.S', 'ventas@techimport.com', '3001112233'),
('Textiles del Valle', 'contacto@textilesvalle.com', '3002223344'),
('Hogar y Confort Ltda', 'info@hogarconfort.com', '3003334455'),
('Deportes Andinos', 'contacto@deportesandinos.com', '3004445566'),
('Editorial Nacional', 'pedidos@editorialnacional.com', '3005556677');

-- Productos
INSERT INTO productos (nombre, descripcion, precio, costo, stock, stock_minimo, sku, peso_kg, id_categoria, id_proveedor, fecha_creacion, activo) VALUES
('Audífonos Inalámbricos X200', 'Audífonos bluetooth con cancelación de ruido', 249900.00, 140000.00, 50, 10, 'ELEC-AUD-001', 0.250, 1, 1, '2025-11-05 10:00:00', TRUE),
('Smartwatch Fit Pro', 'Reloj inteligente con monitor de ritmo cardiaco', 389900.00, 220000.00, 30, 8, 'ELEC-SW-002', 0.150, 1, 1, '2025-11-10 09:30:00', TRUE),
('Cargador USB-C 65W', 'Cargador rápido compatible con laptops y celulares', 89900.00, 42000.00, 100, 20, 'ELEC-CHG-003', 0.180, 1, 1, '2025-11-12 11:00:00', TRUE),
('Camiseta Algodón Premium', 'Camiseta 100% algodón, varias tallas', 59900.00, 25000.00, 200, 30, 'ROPA-CAM-004', 0.200, 2, 2, '2025-11-15 08:00:00', TRUE),
('Chaqueta Impermeable', 'Chaqueta resistente al agua para clima frío', 179900.00, 90000.00, 40, 10, 'ROPA-CHQ-005', 0.700, 2, 2, '2025-11-18 14:00:00', TRUE),
('Jean Clásico Unisex', 'Jean de corte recto, denim resistente', 129900.00, 60000.00, 80, 15, 'ROPA-JEA-006', 0.600, 2, 2, '2025-11-20 09:00:00', TRUE),
('Juego de Ollas Antiadherentes', 'Set de 5 piezas para cocina', 349900.00, 180000.00, 25, 5, 'HOGAR-OLL-007', 3.500, 3, 3, '2025-11-22 10:00:00', TRUE),
('Set de Toallas Premium', 'Juego de 4 toallas de algodón egipcio', 99900.00, 45000.00, 60, 10, 'HOGAR-TOA-008', 1.200, 3, 3, '2025-11-25 10:00:00', TRUE),
('Lámpara LED de Escritorio', 'Lámpara regulable con puerto USB', 79900.00, 35000.00, 70, 15, 'HOGAR-LAM-009', 0.900, 3, 3, '2025-11-28 10:00:00', TRUE),
('Balón de Fútbol Profesional', 'Balón oficial tamaño 5', 119900.00, 55000.00, 45, 10, 'DEP-BAL-010', 0.450, 4, 4, '2025-12-01 10:00:00', TRUE),
('Bicicleta de Ruta Aero', 'Bicicleta de ruta en aluminio, 21 velocidades', 2499900.00, 1500000.00, 8, 2, 'DEP-BIC-011', 12.000, 4, 4, '2025-12-03 10:00:00', TRUE),
('Mancuernas Ajustables 20kg', 'Par de mancuernas ajustables para gimnasio en casa', 289900.00, 160000.00, 20, 5, 'DEP-MAN-012', 20.000, 4, 4, '2025-12-05 10:00:00', TRUE),
('Novela: El Camino Largo', 'Best-seller de ficción contemporánea', 54900.00, 22000.00, 90, 15, 'LIB-NOV-013', 0.400, 5, 5, '2025-12-08 10:00:00', TRUE),
('Libro de Cocina Saludable', 'Recetario con más de 100 recetas', 64900.00, 28000.00, 55, 10, 'LIB-COC-014', 0.500, 5, 5, '2025-12-10 10:00:00', TRUE),
('Agenda Ejecutiva 2026', 'Agenda anual con tapa de cuero sintético', 39900.00, 15000.00, 3, 10, 'LIB-AGE-015', 0.300, 5, 5, '2025-12-12 10:00:00', TRUE);

-- Clientes
INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio, ciudad, fecha_nacimiento, id_sucursal, fecha_registro) VALUES
('Laura', 'Gómez', 'laura.gomez@correo.com', '$2b$12$hashsimuladoLG001', 'Calle 45 #12-30', 'Bogotá', '1992-04-12', 1, '2025-10-01 09:00:00'),
('Andrés', 'Pérez', 'andres.perez@correo.com', '$2b$12$hashsimuladoAP002', 'Cra 80 #34-10', 'Medellín', '1988-07-23', 2, '2025-10-05 10:00:00'),
('Camila', 'Rodríguez', 'camila.rodriguez@correo.com', '$2b$12$hashsimuladoCR003', 'Calle 100 #15-20', 'Bogotá', '1995-01-30', 1, '2025-10-15 11:30:00'),
('Julián', 'Martínez', 'julian.martinez@correo.com', '$2b$12$hashsimuladoJM004', 'Av. Quebradaseca #20-40', 'Bucaramanga', '1990-09-05', 3, '2025-11-01 08:15:00'),
('Valentina', 'Suárez', 'valentina.suarez@correo.com', '$2b$12$hashsimuladoVS005', 'Cra 45 #10-05', 'Bucaramanga', '1998-12-19', 3, '2025-11-10 14:00:00'),
('Santiago', 'Torres', 'santiago.torres@correo.com', '$2b$12$hashsimuladoST006', 'Calle 7 #8-90', 'Medellín', '1985-03-11', 2, '2025-11-20 09:45:00'),
('Mariana', 'Castro', 'mariana.castro@correo.com', '$2b$12$hashsimuladoMC007', 'Cra 15 #100-50', 'Bogotá', '1993-06-27', 1, '2025-12-01 10:00:00'),
('Diego', 'Ramírez', 'diego.ramirez@correo.com', '$2b$12$hashsimuladoDR008', 'Calle 30 #45-12', 'Bucaramanga', '1991-11-02', 3, '2025-12-15 16:20:00'),
('Isabella', 'Vargas', 'isabella.vargas@correo.com', '$2b$12$hashsimuladoIV009', 'Cra 70 #22-18', 'Medellín', '1997-08-14', 2, '2026-01-05 12:00:00'),
('Sebastián', 'Herrera', 'sebastian.herrera@correo.com', '$2b$12$hashsimuladoSH010', 'Calle 50 #9-60', 'Bogotá', '1989-02-08', 1, '2026-01-20 09:00:00');

-- Ventas (encabezados)
INSERT INTO ventas (id_cliente, id_sucursal, fecha_venta, estado, total) VALUES
(1, 1, '2025-12-02 10:15:00', 'Entregado', 0),
(2, 2, '2025-12-05 15:40:00', 'Entregado', 0),
(1, 1, '2025-12-20 09:10:00', 'Entregado', 0),
(3, 1, '2026-01-03 11:25:00', 'Entregado', 0),
(4, 3, '2026-01-08 16:00:00', 'Enviado', 0),
(5, 3, '2026-01-10 10:30:00', 'Entregado', 0),
(2, 2, '2026-01-15 13:45:00', 'Cancelado', 0),
(6, 2, '2026-01-18 09:00:00', 'Entregado', 0),
(1, 1, '2026-02-02 10:00:00', 'Entregado', 0),
(7, 1, '2026-02-05 14:20:00', 'Procesando', 0),
(3, 1, '2026-02-14 17:30:00', 'Entregado', 0),
(8, 3, '2026-02-20 12:00:00', 'Entregado', 0),
(9, 2, '2026-03-01 09:15:00', 'Enviado', 0),
(4, 3, '2026-03-10 11:00:00', 'Entregado', 0),
(10, 1, '2026-03-15 15:00:00', 'Pendiente de Pago', 0),
(5, 3, '2026-03-20 10:45:00', 'Entregado', 0),
(2, 2, '2026-04-02 09:30:00', 'Entregado', 0),
(1, 1, '2026-04-10 16:15:00', 'Entregado', 0);

-- Detalle de ventas (precio_unitario_congelado = precio del producto en ese momento)
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 249900.00),
(1, 3, 2, 89900.00),
(2, 4, 3, 59900.00),
(2, 6, 1, 129900.00),
(3, 2, 1, 389900.00),
(4, 7, 1, 349900.00),
(4, 9, 1, 79900.00),
(5, 10, 2, 119900.00),
(6, 13, 4, 54900.00),
(6, 14, 1, 64900.00),
(7, 11, 1, 2499900.00),
(8, 5, 1, 179900.00),
(8, 6, 2, 129900.00),
(9, 1, 2, 249900.00),
(10, 8, 1, 99900.00),
(11, 12, 1, 289900.00),
(11, 3, 1, 89900.00),
(12, 15, 5, 39900.00),
(13, 2, 1, 389900.00),
(14, 7, 1, 349900.00),
(15, 4, 2, 59900.00),
(16, 10, 3, 119900.00),
(17, 1, 1, 249900.00),
(17, 13, 2, 54900.00),
(18, 6, 1, 129900.00),
(18, 9, 2, 79900.00);

-- Recalcular el total de cada venta a partir de sus detalles
UPDATE ventas v
SET total = (
    SELECT COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0)
    FROM detalle_ventas d
    WHERE d.id_venta = v.id_venta
);

-- Recalcular total_gastado y fecha_ultima_compra por cliente (ventas no canceladas)
UPDATE clientes c
SET total_gastado = (
        SELECT COALESCE(SUM(v.total), 0)
        FROM ventas v
        WHERE v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    ),
    fecha_ultima_compra = (
        SELECT MAX(v.fecha_venta)
        FROM ventas v
        WHERE v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    );

-- Carritos de ejemplo (uno abandonado, uno reciente)
INSERT INTO carritos (id_cliente, fecha_creacion, estado) VALUES
(9, DATE_SUB(NOW(), INTERVAL 5 DAY), 'Activo'),   -- candidato a "abandonado"
(10, DATE_SUB(NOW(), INTERVAL 2 HOUR), 'Activo'); -- carrito reciente, no abandonado

INSERT INTO carrito_detalle (id_carrito, id_producto, cantidad, fecha_agregado) VALUES
(1, 2, 1, DATE_SUB(NOW(), INTERVAL 5 DAY)),
(1, 3, 1, DATE_SUB(NOW(), INTERVAL 5 DAY)),
(2, 5, 1, DATE_SUB(NOW(), INTERVAL 2 HOUR));

-- Vistas de producto (para comparar vistos vs comprados)
INSERT INTO producto_vistas (id_producto, id_cliente, fecha_vista) VALUES
(1, 1, '2025-12-01 09:00:00'), (1, 3, '2025-12-01 10:00:00'), (1, 9, '2026-01-04 08:00:00'),
(2, 1, '2025-12-18 09:00:00'), (2, 6, '2026-01-14 09:00:00'),
(11, 7, '2026-02-04 09:00:00'), (11, 8, '2026-02-19 09:00:00'), (11, 2, '2025-12-04 09:00:00'),
(15, 8, '2026-02-19 12:00:00');

-- Reseñas de productos
INSERT INTO resenas_productos (id_producto, id_cliente, calificacion, comentario, fecha_resena) VALUES
(1, 1, 5, 'Excelente calidad de sonido', '2025-12-10 12:00:00'),
(4, 2, 4, 'Buena tela, talla algo grande', '2025-12-12 12:00:00'),
(13, 5, 5, 'Muy buen libro, lo recomiendo', '2026-01-12 12:00:00');

-- Códigos de descuento (uno vigente, uno expirado)
INSERT INTO codigos_descuento (codigo, id_producto, porcentaje, fecha_inicio, fecha_fin, activo) VALUES
('VERANO10', 6, 10.00, '2025-12-01 00:00:00', '2025-12-31 23:59:59', TRUE),
('BLACKFRIDAY20', 1, 20.00, DATE_SUB(NOW(), INTERVAL 40 DAY), DATE_SUB(NOW(), INTERVAL 10 DAY), TRUE);

-- Programa de referidos
INSERT INTO programa_referidos (id_cliente_referidor, id_cliente_referido, fecha_referido) VALUES
(1, 9, '2026-01-05 12:00:00'),
(2, 10, '2026-01-20 09:00:00');

-- Log de intentos de login (ejemplo)
INSERT INTO log_login_intentos (usuario, exito, ip_origen, fecha_intento) VALUES
('laura.gomez@correo.com', TRUE, '190.24.10.1', '2026-04-01 08:00:00'),
('andres.perez@correo.com', FALSE, '190.24.10.2', '2026-04-01 08:05:00'),
('andres.perez@correo.com', FALSE, '190.24.10.2', '2026-04-01 08:06:00'),
('andres.perez@correo.com', TRUE, '190.24.10.2', '2026-04-01 08:07:00');

-- Actualizar el contador de productos por categoría (normalmente lo haría un trigger,
-- aquí se hace una vez para que los datos iniciales queden consistentes)
UPDATE categorias c
SET num_productos = (
    SELECT COUNT(*) FROM productos p WHERE p.id_categoria = c.id_categoria
);
