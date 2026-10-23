# Clúster
## Qué hay en la carpeta
 
- `docker-compose.yml`: levanta 4 nodos de Cassandra y un cliente en Python ( este lo agrege para que este consultando y insertando datos en la demos mientras hacemos la demo).
- `.env`: la versión de Cassandra y la memoria de cada nodo (aquí vi una forma de trabajar sin tener que cambiar los detalles a lo loco en el compose, si no en .env se cambian y el compose ya sabe de donde sacarlos).
- `scripts/`: el script que crea las tablas y carga los datos iniciales.
- `client/`: un script que inserta y lee datos cada segundo, para ver en la demo que todo sigue funcionando aunque se caiga un nodo.
## Cómo prepararse 
 
1. Limitar la memoria de WSL: crear `C:\Users\<usuario>\.wslconfig` con este contenido:
```ini
[wsl2]
memory=10GB
swap=4GB
```
 
en PowerShell ejecutar `wsl --shutdown` y volver a abrir Docker Desktop.
 
2. Descargar Cassandra y construir el cliente:
```bash
docker compose pull
docker compose build client
```
 
## Cómo probarlo
 
Usen dos terminales: una para el cliente y otra para los comandos.
 
**1. Levantar el clúster**
 
```bash
docker compose up -d
docker exec cass1 nodetool status
```
 
✔ Los 4 nodos aparecen con **UN** (arriba y normal). Tarda unos minutos, porque los nodos arrancan uno por uno.
 
**2. Cargar los datos**
 
```bash
docker exec cass1 cqlsh -f /scripts/esquema_y_datos.cql
```
 
✔ Termina sin errores.
 
**3. Ver en qué nodos quedaron los datos del cliente**
 
```bash
docker exec cass1 nodetool getendpoints logistica_portuaria inspecciones_por_contenedor CONT-DEMO
```
 
✔ Salen 3 IPs: esos son los 3 nodos que guardan copia.
 
**4. Arrancar el cliente (en la otra terminal)**
 
```bash
docker compose up client
```
 
✔ Sale una línea con `OK` cada segundo. Déjenlo corriendo.
 
**5. Apagar uno de los nodos del paso 3**
 
```bash
docker stop cass3
docker exec cass1 nodetool status
```
 
✔ El nodo aparece como **DN** (caído) y el cliente sigue mostrando `OK`.
 
**6. Volver a levantarlo**
 
```bash
docker start cass3
docker exec cass1 nodetool status
```
 
✔ Vuelve a **UN** y recibe lo que se escribió mientras estaba apagado.
 
**7. Apagar dos nodos del paso 3**
 
```bash
docker stop cass2
docker stop cass4
```
 
✔ El cliente empieza a mostrar `ERROR`: QUORUM necesita 2 copias y solo queda 1.
 
Para ver la diferencia entre niveles de consistencia:
 
```bash
docker exec -it cass1 cqlsh
```
 
```sql
CONSISTENCY QUORUM;
SELECT * FROM logistica_portuaria.inspecciones_por_contenedor WHERE id_contenedor = 'CONT-DEMO' LIMIT 5;
CONSISTENCY ONE;
SELECT * FROM logistica_portuaria.inspecciones_por_contenedor WHERE id_contenedor = 'CONT-DEMO' LIMIT 5;
```
 
✔ Con QUORUM falla; con ONE responde.
 
Salir de cqlsh con `exit` y levantar los nodos:
 
```bash
docker start cass2
docker start cass4
```
 
**8. Reparar**
 
```bash
docker exec cass1 nodetool repair logistica_portuaria
```
 
✔ Termina sin errores y las copias quedan iguales en todos los nodos.
 
**9. Apagar el nodo semilla**
 
```bash
docker stop cass1
docker exec cass2 nodetool status
docker start cass1
```
 
✔ El cliente sigue en `OK`: `cass1` no es un nodo maestro, solo sirve para que los otros nodos entren al clúster.
 
**10. Detener el cliente**
 
Presionar `Ctrl + C` en la terminal del cliente.
 
✔ El resumen muestra cuántos datos insertó y cuántos hay guardados. Deberían coincidir.
 
**11. Dejar todo en cero para otro ensayo**
 
```bash
docker compose --profile demo down -v
```
 
✔ Borra los contenedores y los datos. Las imágenes se mantienen.