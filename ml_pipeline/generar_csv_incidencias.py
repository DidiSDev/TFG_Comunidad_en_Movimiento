import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
import numpy as np
from datetime import datetime
from geopy.distance import geodesic

import os
import json

# Parámetros geográficos (coinciden con entrenar_modelo.py)
lat_min, lat_max = 40.9, 41.0
lng_min, lng_max = -5.7, -5.6

# Tamaño de cuadrícula ~300m
tamano_cuadricula_lat = 0.0027
tamano_cuadricula_lng = 0.0035

# Puntos de Interés (POIs)
POIs = [
    {'nombre': 'Estación de Policía', 'lat': 40.9680, 'lng': -5.6630},
    {'nombre': 'Hospital', 'lat': 40.9740, 'lng': -5.6550},
]

def conectar_firebase():
    """Conecta a Firebase con tu serviceAccountKey.json."""
    cred_path = "serviceAccountKey.json" # Ruta de mi cuenta de fb
    if not os.path.exists(cred_path):
        raise FileNotFoundError("No se encontró el archivo de credenciales Firebase (serviceAccountKey.json).")
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)
    print("Conexión a Firebase correcta!")

def normalizar_lat_lng(lat, lng):
    """Normaliza lat/lng a [0..1] usando los min/max."""
    lat_norm = (lat - lat_min) / (lat_max - lat_min)
    lng_norm = (lng - lng_min) / (lng_max - lng_min)
    return lat_norm, lng_norm

def asignar_zona(lat, lng):
    """Asigna zona_x_y según cuadrícula."""
    x = int((lng - lng_min) / tamano_cuadricula_lng)
    y = int((lat - lat_min) / tamano_cuadricula_lat)
    return f"zona_{x}_{y}"

def calcular_distancia_pois(lat, lng, POIs):
    """Calcula la distancia mínima a un POI (en metros)."""
    punto = (lat, lng)
    distancias = [geodesic(punto, (poi['lat'], poi['lng'])).meters for poi in POIs]
    return min(distancias) if distancias else 0.0

def cargar_zona_mapping():
    """Carga el mapeo de zonas desde zona_mapping.json."""
    mapping_path = os.path.join("..", "assets", "zona_mapping.json")
    if not os.path.exists(mapping_path):
        print(f"Advertencia: No se encontró {mapping_path}. 'zona_cod' se asignará como -1.")
        return {}
    with open(mapping_path, "r", encoding="utf-8") as f:
        zona_mapping = json.load(f)
    return zona_mapping

def generar_negativos(df_pos, zona_mapping, num_neg_por_pos=5, radius_m=300):
    """
    Genera puntos 'negativos' (peligro=0) en la región lat_min..lat_max, lng_min..lng_max.
    Solo si están a >= radius_m de cualquier incidencia = 1 => Son 0.
    """
    negatives = []
    size = len(df_pos) * num_neg_por_pos
    np.random.seed(42)

    lat_rand = np.random.uniform(lat_min, lat_max, size)
    lng_rand = np.random.uniform(lng_min, lng_max, size)
    month_rand = np.random.randint(1, 13, size)
    weekday_rand = np.random.randint(0, 7, size)
    cat_acc_default = 1  # Asumimos cat_acc = 1 (accesible) por defecto, tiene mucho peso en el entrenamiento

    pos_coords = df_pos[['lat', 'lng']].values

    for i in range(size):
        nlat = lat_rand[i]
        nlng = lng_rand[i]
        lat_norm, lng_norm = normalizar_lat_lng(nlat, nlng)
        zona = asignar_zona(nlat, nlng)
        zona_cod = zona_mapping.get(zona, -1)
        densidad_zona = 0.0  # Inicialmente 0.0, será actualizado posteriormente

        # Dist al POI (poli, hospital, etc.)
        dist_min_poi = calcular_distancia_pois(nlat, nlng, POIs)

        # Verificamos si hay una incidencia 1 cerca
        distances = [geodesic((nlat, nlng), (plat, plng)).meters for plat, plng in pos_coords]
        peligro = 1 if min(distances) < radius_m else 0

        if peligro == 0:
            # Guardar
            negatives.append([
                nlat,
                nlng,
                lat_norm,
                lng_norm,
                cat_acc_default,
                month_rand[i],
                weekday_rand[i],
                zona,
                zona_cod,
                dist_min_poi,
                peligro,
                densidad_zona
            ])

    # el df
    df_neg = pd.DataFrame(
        negatives, 
        columns=[
            'lat','lng','lat_norm','lng_norm','cat_acc','month','weekday','zona','zona_cod','dist_min_poi','peligro','densidad_zona'
        ]
    )
    return df_neg

def main():
    # Cargar mapeo de zonas
    zona_mapping = cargar_zona_mapping()

    # Conectar a Firebase
    conectar_firebase()
    db = firestore.client()

    # Leer incidencias de 2 colecciones
    colecciones = ['incidencias', 'total_incidencias']
    data = []
    for col in colecciones:
        docs = db.collection(col).stream()
        for doc in docs:
            d = doc.to_dict()
            # Comproba campos necesarios
            required = ['latitude','longitude','fecha_informe','peligro','categoria_accesibilidad']
            if not all(r in d for r in required):
                continue
            
            lat = d['latitude']
            lng = d['longitude']
            if not(lat_min <= lat <= lat_max and lng_min <= lng <= lng_max):
                continue  # Filtra fuera de rango

            # Filtro fecha
            try:
                dt = datetime.strptime(d['fecha_informe'], '%Y-%m-%d %H:%M:%S')
            except:
                continue

            month = dt.month
            weekday = dt.weekday()

            peligro = d.get('peligro', np.nan)
            if peligro not in [0,1]:
                continue

            cat_acc = d['categoria_accesibilidad']
            if pd.isna(cat_acc):
                continue

            lat_norm, lng_norm = normalizar_lat_lng(lat, lng)
            zona = asignar_zona(lat, lng)
            zona_cod = zona_mapping.get(zona, -1)
            densidad_zona = 0.0  # Inicialmente 0.0, será actualizado posteriormente con las zonas, de momento entreno a la IA en una zona muy pequeñita, cais todas tendrán 0.0, Lejos de puerta zamora la IA no puede predecir nada
            dist_min_poi = calcular_distancia_pois(lat, lng, POIs)

            data.append([
                lat,
                lng,
                lat_norm,
                lng_norm,
                cat_acc,
                month,
                weekday,
                zona,
                zona_cod,
                dist_min_poi,
                peligro,
                densidad_zona
            ])

    # convertir a df
    df_pos = pd.DataFrame(data, columns=[
        'lat','lng','lat_norm','lng_norm','cat_acc','month','weekday','zona','zona_cod','dist_min_poi','peligro','densidad_zona'
    ])

    if df_pos.empty:
        raise ValueError("No se encontraron incidencias válidas en Firestore.")
    
    print(f"Total incidencias (pos) = {len(df_pos)}")

    # Genero algunos 'negativos' artificiales alejados >=300m (en este caso algunos podrian caer dentro de edificios o cosas así, pero no importa para el prototipo. El entrenamiento se debe re-hacer en producción exclusivamente con datos reales)
    df_neg = generar_negativos(df_pos[df_pos['peligro']==1], zona_mapping, num_neg_por_pos=5, radius_m=300)
    print(f"Negativos generados: {len(df_neg)}")

    df_final = pd.concat([df_pos, df_neg], ignore_index=True)
    # Eliminamos duplicados
    before = len(df_final)
    df_final.drop_duplicates(inplace=True)
    after = len(df_final)
    if (before - after) > 0:
        print(f"Se han eliminado {before - after} duplicados.")

    # Guardar CSV
    csv_path = "datos_incidencias.csv"
    df_final.to_csv(csv_path, index=False)
    print(f"'{csv_path}' generado con {len(df_final)} filas totales.")

if __name__=="__main__":
    main()
