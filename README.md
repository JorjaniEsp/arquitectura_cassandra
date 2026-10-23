# Clúster de Cassandra – Anticitera

## La idea en corto

Tenemos **4 nodos de Cassandra** (4 servidores de base de datos, cada uno en su contenedor) que funcionan como una sola base de datos. Ninguno es el jefe: a cualquiera se le puede preguntar o pedir que guarde algo.

Además hay un **cliente en Python** que se porta como una aplicación real: cada segundo guarda una inspección de contenedor y la vuelve a leer. Así, en la demo se ve en vivo si la base sigue respondiendo mientras apagamos nodos.

## Cómo se reparten y se protegen los datos

**Fragmentación (repartir).** Los datos no están todos en un solo nodo. Cassandra toma la clave de cada fila (por ejemplo, el `id_contenedor`), la convierte en un número y, según ese número, decide qué nodo le toca. Así, cada nodo se queda con una parte.

**Replicación (copias).** Cada dato se guarda en **3 de los 4 nodos** (factor de replicación 3, definido en el keyspace del script). Si un nodo se cae, el dato sigue existiendo en los otros dos.

**QUORUM (mayoría).** Cuando el cliente guarda o lee, Cassandra espera que respondan **2 de las 3 copias**. Por eso:

- Con **1 copia caída**, todo sigue funcionando (quedan 2).
- Con **2 copias caídas**, QUORUM falla (queda 1). Si bajamos la exigencia a **ONE** (con 1 basta), vuelve a responder. Ese es el Teorema CAP en vivo: nosotros escogemos entre más consistencia o más disponibilidad.

**Recuperación.** Cassandra tiene tres mecanismos para que un nodo que estuvo caído se ponga al día, y los tres aparecen en las pruebas:

- ***Hinted handoff* (entrega de pendientes):** mientras un nodo está caído, los demás guardan notas (*hints*, pistas) con lo que le tocaba recibir, y se lo entregan cuando vuelve. → Pruebas 2 y 3.
- ***Read repair* (reparación al leer):** si al leer se nota que una copia está atrasada, Cassandra la corrige en ese momento. → Prueba 7.
- ***Anti-entropy repair* (reparación completa):** `nodetool repair` compara todas las copias y sincroniza las diferencias. → Prueba 7.

## Qué hay en la carpeta

- `docker-compose.yml`: los 4 nodos, la red con IPs fijas, la carga inicial y el cliente.
- `.env`: versión de Cassandra, nombre del clúster y memoria de cada nodo. Si algo se cambia, se cambia aquí.
- `scripts/esquema_y_datos.cql`: crea el keyspace, las tablas y los datos de ejemplo.
- `client/`: el cliente en Python (`client.py`, su `Dockerfile` y `requirements.txt`).

| Nodo | IP |
|---|---|
| cass1 (semilla) | 172.30.0.11 |
| cass2 | 172.30.0.12 |
| cass3 | 172.30.0.13 |
| cass4 | 172.30.0.14 |

## Qué demuestra cada prueba

| Prueba | Qué se ve | Punto de la rúbrica |
|---|---|---|
| 1 · Sincronización | Se guarda en un nodo y se lee en otro | Replicación en tiempo real |
| 2 · Cae una copia | El cliente sigue en OK; se acumulan *hints* | Desconexión de un nodo |
| 3 · Vuelve la copia | Los *hints* se entregan | Mecanismo de recuperación |
| 4 · Se pierde la mayoría | QUORUM falla, ONE responde | Teorema CAP |
| 5 · El cliente baja a ONE | La aplicación vuelve a funcionar | Teorema CAP en la aplicación |
| 6 · Cae la semilla | El cliente sigue en OK | Arquitectura sin maestro |
| 7 · Verificación final | Las 3 copias de acuerdo; no se perdió nada | Recuperación y consistencia |

---

## Antes de empezar (laptop de 16 GB)

Para que los 4 nodos no se coman la RAM, hay que limitar WSL:

1. En PowerShell: `notepad $env:USERPROFILE\.wslconfig`
2. Pegar esto y guardar (que no quede como `.txt`):

```ini
[wsl2]
memory=10GB
swap=4GB
```

3. Cerrar Docker Desktop, ejecutar `wsl --shutdown`, esperar 10 segundos y volver a abrir Docker Desktop.

La primera vez se necesita internet para descargar Cassandra y construir el cliente.

**Todos los comandos son para PowerShell**, abierto en esta carpeta. Usen **siempre la misma ventana** para los comandos: el cambio de consistencia (prueba 5) se guarda en esa ventana.

---

## Paso 1 · Levantar todo

Empezar siempre desde cero (borra datos de ensayos anteriores):

```powershell
docker compose down -v
docker compose up --build -d
```

**Qué va a pasar, en orden** (tarda varios minutos):

1. Arranca `cass1`, la semilla.
2. Cuando `cass1` está listo, arranca `cass2`; luego `cass3`; luego `cass4`. Van de uno en uno a propósito, porque Cassandra se enreda si varios entran al mismo tiempo.
3. Con los 4 listos, `init-db` corre el script `.cql` (tablas y datos de ejemplo) y se apaga solo.
4. Por último arranca el `client` y empieza a escribir y leer, con consistencia **QUORUM**.

**Verificar:**

```powershell
docker compose ps
docker exec cass1 nodetool status
```

✔ En `ps`, los 4 nodos dicen `healthy` (sanos) y el cliente `running` (corriendo). `init-db` aparece como terminado: es normal.
✔ En `nodetool status`, los 4 nodos aparecen con **UN** (arriba y normal).

## Paso 2 · Ver el cliente en vivo

Abrir **otra terminal** y dejarla visible durante todas las pruebas:

```powershell
docker compose logs -f client
```

✔ Al inicio dice `Insercion preparada con consistencia QUORUM` y después sale una línea por segundo con `OK`. Esa terminal es "la aplicación": si ahí sigue saliendo OK, el usuario no se enteró de nada.

**Cómo leer el cliente:**

| Mensaje | Qué significa |
|---|---|
| `OK` | Guardó la inspección y la volvió a leer. |
| `ERROR ESCRITURA` | No pudo guardar. El tipo de error dice por qué; con nodos caídos lo normal es `Unavailable` (no hay suficientes copias vivas para la consistencia pedida). |
| `ERROR LECTURA` | Guardó, pero no pudo leer. El dato **sí** está en la base. |
| `NO ENCONTRADA` | Guardó y la lectura respondió, pero no vio el dato. Puede pasar con ONE si la lectura cae en una copia atrasada. |
| `RESUMEN` | Aparece cuando el cliente se detiene: total de exitosas y fallidas **de esa corrida**. |

> Cada vez que el cliente se recrea, sus contadores empiezan en cero. Si la terminal de logs se detiene, vuelvan a correr `docker compose logs -f client`.

## Paso 3 · Ver dónde están los datos del cliente

El cliente guarda todo en el contenedor `CONT-DEMO`, así que esas inspecciones viven en 3 nodos fijos. El cliente los imprime al arrancar, en la línea `Replicas de la particion CONT-DEMO: [...]`. Lo confirmamos con Cassandra:

```powershell
docker exec cass1 nodetool getendpoints logistica_portuaria inspecciones_por_contenedor CONT-DEMO
```

✔ Salen **3 IPs**, las mismas que imprimió el cliente: esas son las 3 copias. Con la tabla de IPs, anoten qué nodos son. El nodo que **no** sale es el que no tiene copia.

En las pruebas los llamamos así:

- **Copia A, Copia B, Copia C:** los 3 nodos que salieron.
- **Nodo libre:** el que no salió. Desde ese hacemos las consultas a mano.

> Hay que hacer este paso **cada vez** que se levante desde cero: si se borran los volúmenes, las copias pueden quedar en otros nodos.

---

## Las pruebas

### Prueba 1 · Sincronización: guardo en un nodo, leo en otro

```powershell
docker exec cass1 cqlsh -e "INSERT INTO logistica_portuaria.contenedores_por_manifiesto (id_manifiesto, id_contenedor, tipo, peso_kg, estado, terminal) VALUES ('MAN-001', 'CONT-099', 'SECO', 12000.00, 'PENDIENTE', 'Terminal Limon');"

docker exec cass4 cqlsh -e "SELECT * FROM logistica_portuaria.contenedores_por_manifiesto WHERE id_manifiesto = 'MAN-001';"
```

✔ `CONT-099` se guardó entrando por `cass1` y aparece al consultar por `cass4`.

### Prueba 2 · Botar una copia

```powershell
docker stop <Copia A>
docker exec <Nodo libre> nodetool status
```

✔ La Copia A aparece como **DN** (caída).
✔ El cliente **sigue en OK**: quedan 2 copias y QUORUM necesita 2.

Dejarla apagada unos 30 segundos, para que el cliente escriba datos mientras no está. Luego:

```powershell
docker exec <Nodo libre> nodetool listpendinghints
```

✔ Aparece una fila con el ID de la Copia A y una cantidad de *hints*: son las escrituras que los demás nodos le están guardando.

### Prueba 3 · Levantar la copia

```powershell
docker start <Copia A>
docker exec <Nodo libre> nodetool status
```

✔ La Copia A vuelve a **UN**. Esperar unos segundos y revisar los pendientes:

```powershell
docker exec <Nodo libre> nodetool listpendinghints
```

✔ Ya no aparece la Copia A (o dice que no hay *hints* pendientes): los otros nodos **ya le entregaron** lo que se escribió mientras estaba apagada. Si todavía aparece, esperar y repetir; **no pasar a la prueba 4 hasta que esté vacío**.

### Prueba 4 · Botar las otras dos copias

Ojo: se apagan **B y C**, no la A que acabamos de levantar.

```powershell
docker stop <Copia B>
docker stop <Copia C>
```

✔ El cliente empieza a mostrar **ERROR ESCRITURA | Unavailable**: solo queda 1 copia y QUORUM necesita 2.

Ahora consultamos a mano desde el nodo libre:

```powershell
docker exec -it <Nodo libre> cqlsh
```

```sql
CONSISTENCY QUORUM;
SELECT * FROM logistica_portuaria.inspecciones_por_contenedor WHERE id_contenedor = 'CONT-DEMO' LIMIT 5;

CONSISTENCY ONE;
SELECT * FROM logistica_portuaria.inspecciones_por_contenedor WHERE id_contenedor = 'CONT-DEMO' LIMIT 40;
exit
```

✔ Con **QUORUM** falla (no hay mayoría).
✔ Con **ONE** responde. La única copia viva es la A. Si en el resultado aparecen las inspecciones escritas mientras A estaba apagada, es la segunda prueba de que **sí se puso al día** en la prueba 3.

### Prueba 5 · La aplicación elige disponibilidad (ONE)

Con B y C **todavía apagadas**, cambiamos el cliente a ONE, en la ventana de comandos:

```powershell
$env:CONSISTENCIA="ONE"
docker compose up -d --no-deps --force-recreate client
```

Al recrearse, en la terminal de logs sale el `RESUMEN` de la corrida anterior: **anoten el número de exitosas**. Si la terminal de logs se detuvo, vuelvan a correr ahí `docker compose logs -f client`.

✔ El cliente arranca diciendo `consistencia ONE` y vuelve a **OK** con una sola copia viva. Es el Teorema CAP: ganamos disponibilidad, pero perdemos la garantía de que cada lectura vea lo último que se escribió.

Levantar las dos copias y esperar a que estén en **UN**:

```powershell
docker start <Copia B>
docker start <Copia C>
docker exec <Nodo libre> nodetool status
```

Volver el cliente a QUORUM (otra vez, anotar las exitosas del `RESUMEN` que sale en la terminal de logs):

```powershell
$env:CONSISTENCIA="QUORUM"
docker compose up -d --no-deps --force-recreate client
```

✔ El cliente arranca diciendo `consistencia QUORUM` y sigue en **OK**.

### Prueba 6 · Botar la semilla

```powershell
docker stop cass1
docker exec cass2 nodetool status
docker start cass1
```

✔ El cliente sigue en OK. `cass1` solo sirve para que los otros nodos entren al clúster; no es un nodo maestro.

> El segundo comando se puede correr en cualquier nodo encendido; `cass2` es solo un ejemplo.

### Prueba 7 · ¿Se perdió algo?

Detener el cliente y anotar las exitosas de su último `RESUMEN`:

```powershell
docker compose stop client
docker compose logs --tail 5 client
```

Reparar las copias y contar las inspecciones pidiendo respuesta de **las 3**:

```powershell
docker exec <Copia A> nodetool repair logistica_portuaria
docker exec -it <Nodo libre> cqlsh
```

```sql
CONSISTENCY ALL;
SELECT count(*) FROM logistica_portuaria.inspecciones_por_contenedor WHERE id_contenedor = 'CONT-DEMO';
exit
```

✔ La consulta responde con **ALL**: las 3 copias están vivas y tienen lo mismo.
✔ El conteo es **igual o mayor** que la suma de las exitosas de todas las corridas del cliente (las 3 que anotaron). Puede ser mayor porque algunas escrituras marcadas como error sí llegaron a guardarse; lo importante es que **ninguna confirmada se perdió**.

---

## Dejar todo en cero

```powershell
docker compose down -v
```

Borra los contenedores y los datos (`-v`). Las imágenes se quedan, así que la próxima vez arranca sin internet. Hagan esto antes de cada ensayo y antes de la presentación.

## Si algo falla

- **Se cambió `client/client.py` y el cliente sigue igual:** el código va dentro de la imagen, hay que reconstruirla con `docker compose up -d --build client`.
- **El cliente se reinicia solo al arrancar:** normal si Cassandra todavía no acepta conexiones; Docker lo reintenta (`restart: on-failure`).
- **Un nodo se queda en `UJ` (uniéndose) por varios minutos:** `docker compose down -v` y volver a levantar.
- **Un contenedor se cierra con código 137:** se quedó sin memoria. Bajen `MAX_HEAP` en `.env` a `768M`.
- **Error de que la red ya existe o se cruza con otra:** cambien la subred `172.30.0.0/24` y las IPs en el compose.
- **Ver qué pasó en un nodo:** `docker logs cass2 --tail 50`.
- **Plan B (3 nodos):** borrar `cass4` y su volumen del compose, quitar su IP de `CASSANDRA_HOSTS` del cliente y cambiar el `depends_on` de `init-db` a `cass3`. Con 3 nodos y RF 3 no hay nodo libre: las consultas a mano se hacen desde la Copia A.
