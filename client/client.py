import os
import time
import signal

from cassandra.cluster import Cluster
from cassandra.policies import DCAwareRoundRobinPolicy
from cassandra import ConsistencyLevel
from datetime import datetime, timezone
from uuid import uuid4


# Leer la configuracion definida en Docker
hosts = os.getenv(
    "CASSANDRA_HOSTS",
    "172.30.0.11,172.30.0.12,172.30.0.13,172.30.0.14"
).split(",")

keyspace = os.getenv(
    "CASSANDRA_KEYSPACE",
    "logistica_portuaria"
)

datacenter = os.getenv("CASSANDRA_DC") or "datacenter1"

intervalo = float(os.getenv("INTERVALO_SEGUNDOS", "1"))

# Seleccionar el nivel de consistencia desde Docker
consistencia = os.getenv(
    "CONSISTENCIA",
    "QUORUM"
).upper()

if consistencia not in ("ONE", "QUORUM"):
    raise ValueError("La consistencia debe ser ONE o QUORUM")

nivel_consistencia = getattr(ConsistencyLevel, consistencia)


# Crear la conexion con los nodos de Cassandra
cluster = Cluster(
    contact_points=hosts,
    port=9042,
    load_balancing_policy=DCAwareRoundRobinPolicy(
        local_dc=datacenter
    ),
    connect_timeout=10
)

# Conectarse al keyspace de logistica portuaria
session = cluster.connect(keyspace)

print("Conexion establecida con Cassandra")
print("Nodos configurados:", hosts)
print("Keyspace:", keyspace)


# Preparar la insercion de inspecciones
insertar = session.prepare("""
    INSERT INTO inspecciones_por_contenedor
    (id_contenedor, fecha, id_inspeccion,
     tipo_inspeccion, resultado, observaciones)
    VALUES (?, ?, ?, ?, ?, ?)
""")

# Utilizar consistencia
insertar.consistency_level = nivel_consistencia

print(f"Insercion preparada con consistencia {consistencia}")


# Preparar la consulta de inspecciones
consultar = session.prepare("""
    SELECT id_inspeccion, resultado
    FROM inspecciones_por_contenedor
    WHERE id_contenedor = ?
      AND fecha = ?
      AND id_inspeccion = ?
""")

# Utilizar consistencia en las consultas
consultar.consistency_level = nivel_consistencia

print(f"Consulta preparada con consistencia {consistencia}")


# Contenedor que utilizaremos en la demostracion
id_contenedor = "CONT-DEMO"

# Mostrar cuales nodos guardan la particion del contenedor de demostracion
# (equivale a: nodetool getendpoints logistica_portuaria inspecciones_por_contenedor CONT-DEMO)
try:
    replicas = cluster.metadata.get_replicas(
        keyspace, id_contenedor.encode("utf-8")
    )
    print(
        "Replicas de la particion", id_contenedor + ":",
        sorted(h.address for h in replicas)
    )
except Exception as error:
    print("No se pudieron obtener las replicas:", error)

# Contadores para registrar los resultados
exitosas = 0
fallidas = 0

print("Iniciando demostracion automatica...")
print("Contenedor:", id_contenedor)

# Permitir detener el programa desde Docker
def detener_programa(signum, frame):
    raise KeyboardInterrupt

signal.signal(signal.SIGTERM, detener_programa)

# Ejecutar inserciones y consultas continuamente
try:
    while True:
        # Crear datos nuevos para cada inspeccion
        fecha = datetime.now(timezone.utc)
        id_inspeccion = "INS-" + str(uuid4())[:8]

        # Paso 1: insertar una inspeccion
        try:
            session.execute(insertar, (
                id_contenedor,
                fecha,
                id_inspeccion,
                "ADUANERA",
                "APROBADO",
                "Inspeccion generada automaticamente"
            ))
        except Exception as error:
            fallidas += 1
            print(
                f"ERROR ESCRITURA | {id_inspeccion} | "
                f"{type(error).__name__} | {error} | "
                f"Exitosas: {exitosas} | Fallidas: {fallidas}",
                flush=True
            )
            time.sleep(intervalo)
            continue

        # Paso 2: consultar la inspeccion que acabamos de insertar
        try:
            resultado = session.execute(consultar, (
                id_contenedor,
                fecha,
                id_inspeccion
            ))
            registro = resultado.one()
        except Exception as error:
            fallidas += 1
            print(
                f"ERROR LECTURA | {id_inspeccion} | "
                f"(la escritura si se confirmo) | "
                f"{type(error).__name__} | {error} | "
                f"Exitosas: {exitosas} | Fallidas: {fallidas}",
                flush=True
            )
            time.sleep(intervalo)
            continue

        if registro is not None:
            exitosas += 1
            print(
                f"OK | {id_inspeccion} | "
                f"Guardada y consultada | "
                f"Exitosas: {exitosas} | Fallidas: {fallidas}",
                flush=True
            )
        else:
            fallidas += 1
            print(
                f"NO ENCONTRADA | {id_inspeccion} | "
                "La escritura se confirmo, pero la lectura no la vio | "
                f"Exitosas: {exitosas} | Fallidas: {fallidas}",
                flush=True
            )

        # Esperar antes de la siguiente inspeccion
        time.sleep(intervalo)

except KeyboardInterrupt:
    print("Demostracion detenida por el usuario")

finally:
    print(f"RESUMEN | Exitosas: {exitosas} | Fallidas: {fallidas}")
    cluster.shutdown()
