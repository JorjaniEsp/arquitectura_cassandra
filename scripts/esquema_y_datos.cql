-- =====================================================================
-- Universidad de Costa Rica
-- Curso: IF0010 - Bases de Datos II
-- Investigación: Apache Cassandra
-- Sistema de Logística Portuaria y Aduanera
-- Script CQL - Esquema y datos iniciales
--
-- Arquitectura:
--   4 nodos Cassandra
--   Factor de replicación (RF): 3
--
-- IMPORTANTE:
-- 'datacenter1' debe coincidir con CASSANDRA_DC del archivo .env
-- =====================================================================


-- =====================================================================
-- 1. CREACIÓN DEL KEYSPACE
-- =====================================================================

CREATE KEYSPACE IF NOT EXISTS logistica_portuaria
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3
};


-- Seleccionar el keyspace
USE logistica_portuaria;


-- =====================================================================
-- 2. TABLA: BUQUES
-- Consulta principal:
-- Buscar la información de un buque por su identificador.
-- =====================================================================

CREATE TABLE IF NOT EXISTS buques (
    id_buque text,
    nombre text,
    naviera text,
    bandera text,
    capacidad_contenedores int,
    estado text,
    PRIMARY KEY (id_buque)
);


-- =====================================================================
-- 3. TABLA: MANIFIESTOS POR BUQUE
-- Consulta principal:
-- Obtener los manifiestos pertenecientes a un determinado buque.
-- =====================================================================

CREATE TABLE IF NOT EXISTS manifiestos_por_buque (
    id_buque text,
    fecha date,
    id_manifiesto text,
    puerto_origen text,
    puerto_destino text,
    estado text,
    PRIMARY KEY (id_buque, fecha, id_manifiesto)
) WITH CLUSTERING ORDER BY (fecha DESC, id_manifiesto ASC);


-- =====================================================================
-- 4. TABLA: CONTENEDORES POR MANIFIESTO
-- Consulta principal:
-- Obtener todos los contenedores de un manifiesto.
-- =====================================================================

CREATE TABLE IF NOT EXISTS contenedores_por_manifiesto (
    id_manifiesto text,
    id_contenedor text,
    tipo text,
    peso_kg decimal,
    estado text,
    terminal text,
    PRIMARY KEY (id_manifiesto, id_contenedor)
);


-- =====================================================================
-- 5. TABLA: INSPECCIONES POR CONTENEDOR
-- Consulta principal:
-- Consultar el historial de inspecciones de un contenedor.
-- =====================================================================

CREATE TABLE IF NOT EXISTS inspecciones_por_contenedor (
    id_contenedor text,
    fecha timestamp,
    id_inspeccion text,
    tipo_inspeccion text,
    resultado text,
    observaciones text,
    PRIMARY KEY (id_contenedor, fecha, id_inspeccion)
) WITH CLUSTERING ORDER BY (fecha DESC, id_inspeccion ASC);


-- =====================================================================
-- 6. TABLA: CONTENEDORES POR ESTADO
-- Consulta principal:
-- Obtener contenedores según su estado.
-- =====================================================================

CREATE TABLE IF NOT EXISTS contenedores_por_estado (
    estado text,
    id_contenedor text,
    id_manifiesto text,
    tipo text,
    terminal text,
    peso_kg decimal,
    PRIMARY KEY (estado, id_contenedor)
);


-- =====================================================================
-- 7. DATOS DE PRUEBA - BUQUES
-- =====================================================================

INSERT INTO buques
(id_buque, nombre, naviera, bandera, capacidad_contenedores, estado)
VALUES
('BUQ-001', 'Caribe Express', 'Naviera del Caribe',
 'Costa Rica', 2500, 'ATRACADO');

INSERT INTO buques
(id_buque, nombre, naviera, bandera, capacidad_contenedores, estado)
VALUES
('BUQ-002', 'Pacific Star', 'Oceanic Shipping',
 'Panama', 3200, 'EN_TRANSITO');


-- =====================================================================
-- 8. DATOS DE PRUEBA - MANIFIESTOS
-- =====================================================================

INSERT INTO manifiestos_por_buque
(id_buque, fecha, id_manifiesto, puerto_origen, puerto_destino, estado)
VALUES
('BUQ-001', '2026-10-18', 'MAN-001',
 'Cartagena', 'Limon', 'RECIBIDO');

INSERT INTO manifiestos_por_buque
(id_buque, fecha, id_manifiesto, puerto_origen, puerto_destino, estado)
VALUES
('BUQ-001', '2026-10-17', 'MAN-002',
 'Colon', 'Limon', 'PROCESADO');

INSERT INTO manifiestos_por_buque
(id_buque, fecha, id_manifiesto, puerto_origen, puerto_destino, estado)
VALUES
('BUQ-002', '2026-10-18', 'MAN-003',
 'Manzanillo', 'Limon', 'EN_TRANSITO');


-- =====================================================================
-- 9. DATOS DE PRUEBA - CONTENEDORES
-- =====================================================================

INSERT INTO contenedores_por_manifiesto
(id_manifiesto, id_contenedor, tipo, peso_kg, estado, terminal)
VALUES
('MAN-001', 'CONT-001', 'REFRIGERADO',
 18500.50, 'EN_INSPECCION', 'Terminal Limon');

INSERT INTO contenedores_por_manifiesto
(id_manifiesto, id_contenedor, tipo, peso_kg, estado, terminal)
VALUES
('MAN-001', 'CONT-002', 'SECO',
 14200.00, 'PENDIENTE', 'Terminal Limon');

INSERT INTO contenedores_por_manifiesto
(id_manifiesto, id_contenedor, tipo, peso_kg, estado, terminal)
VALUES
('MAN-002', 'CONT-003', 'REFRIGERADO',
 20100.75, 'DESPACHADO', 'Terminal Limon');

INSERT INTO contenedores_por_manifiesto
(id_manifiesto, id_contenedor, tipo, peso_kg, estado, terminal)
VALUES
('MAN-003', 'CONT-004', 'SECO',
 16750.25, 'EN_TRANSITO', 'Terminal Limon');


-- =====================================================================
-- 10. DATOS DE PRUEBA - INSPECCIONES
-- =====================================================================

INSERT INTO inspecciones_por_contenedor
(id_contenedor, fecha, id_inspeccion,
 tipo_inspeccion, resultado, observaciones)
VALUES
('CONT-001', '2026-10-18 09:15:00', 'INS-001',
 'ADUANERA', 'PENDIENTE', 'Contenedor en revision');

INSERT INTO inspecciones_por_contenedor
(id_contenedor, fecha, id_inspeccion,
 tipo_inspeccion, resultado, observaciones)
VALUES
('CONT-003', '2026-10-17 14:30:00', 'INS-002',
 'ADUANERA', 'APROBADO', 'Sin irregularidades');


-- =====================================================================
-- 11. DATOS PARA CONSULTA POR ESTADO
-- En Cassandra se mantienen tablas orientadas a las consultas.
-- =====================================================================

INSERT INTO contenedores_por_estado
(estado, id_contenedor, id_manifiesto, tipo, terminal, peso_kg)
VALUES
('EN_INSPECCION', 'CONT-001', 'MAN-001',
 'REFRIGERADO', 'Terminal Limon', 18500.50);

INSERT INTO contenedores_por_estado
(estado, id_contenedor, id_manifiesto, tipo, terminal, peso_kg)
VALUES
('PENDIENTE', 'CONT-002', 'MAN-001',
 'SECO', 'Terminal Limon', 14200.00);

INSERT INTO contenedores_por_estado
(estado, id_contenedor, id_manifiesto, tipo, terminal, peso_kg)
VALUES
('DESPACHADO', 'CONT-003', 'MAN-002',
 'REFRIGERADO', 'Terminal Limon', 20100.75);

INSERT INTO contenedores_por_estado
(estado, id_contenedor, id_manifiesto, tipo, terminal, peso_kg)
VALUES
('EN_TRANSITO', 'CONT-004', 'MAN-003',
 'SECO', 'Terminal Limon', 16750.25);


-- =====================================================================
-- 12. CONSULTAS PARA COMPROBAR EL FUNCIONAMIENTO
-- =====================================================================

SELECT * FROM buques
WHERE id_buque = 'BUQ-001';

SELECT * FROM manifiestos_por_buque
WHERE id_buque = 'BUQ-001';

SELECT * FROM contenedores_por_manifiesto
WHERE id_manifiesto = 'MAN-001';

SELECT * FROM inspecciones_por_contenedor
WHERE id_contenedor = 'CONT-001';

SELECT * FROM contenedores_por_estado
WHERE estado = 'EN_INSPECCION';


-- =====================================================================
-- FIN DEL SCRIPT
-- =====================================================================
