import json
import pandas as pd
import os

# Parámetros de la región geográfica (coherentes con entrenar_modelo.py)
lat_min, lat_max = 40.9, 41.0
lng_min, lng_max = -5.7, -5.6

# Tamaños de cuadrícula en grados para ~300m por lado
tamano_cuadricula_lat = 0.0027
tamano_cuadricula_lng = 0.0035

# Cálculo aproximado de área de cada "zona"
# 111 * 85 ~9,435 => solo aproximado, suficiente para densidades
area_zona_km2 = tamano_cuadricula_lat * tamano_cuadricula_lng * 111 * 85

def main():
    """
    Lee datos_incidencias.csv, calcula densidad por zona y genera
    zona_density.json en comunidad_en_movimiento/assets.
    """
    current_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path = os.path.join(current_dir, "datos_incidencias.csv")

    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"No se encontró el archivo {csv_path}.")

    # Cargo CSV
    df = pd.read_csv(csv_path)

    # Verifico columnas
    required_columns = [
        "zona", "peligro", "zona_cod", "densidad_zona"
    ]
    if not all(col in df.columns for col in required_columns):
        raise KeyError(f"El CSV debe contener columnas {required_columns}.")

    # Filtroincidencias positivas
    df_pos = df[df["peligro"] == 1].copy()

    # Las cuento por zona
    zona_counts = df_pos["zona"].value_counts()

    #  densidad por zona
    zona_density = {}
    for z, count in zona_counts.items():
        densidad = count / area_zona_km2
        zona_density[z] = densidad

    # Genero TODAS las zonas posibles en Salamanca
    num_zonas_x = int((lng_max - lng_min) / tamano_cuadricula_lng)
    num_zonas_y = int((lat_max - lat_min) / tamano_cuadricula_lat)
    for y in range(num_zonas_y):
        for x in range(num_zonas_x):
            zona_nom = f"zona_{x}_{y}"
            if zona_nom not in zona_density:
                zona_density[zona_nom] = 0.0

    # Guardo ruta
    assets_dir = os.path.normpath(
        os.path.join(current_dir, "..", "assets")
    )
    if not os.path.exists(assets_dir):
        os.makedirs(assets_dir)

    output_path = os.path.join(assets_dir, "zona_density.json")
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(zona_density, f, indent=4, ensure_ascii=False)

    print(f"'{output_path}' generado exitosamente.")
    print(f"Total de zonas procesadas: {len(zona_density)}")

    # Actualizo el CSV con 'densidad_zona'
    # Creo un diccionario de densidad para mapear
    densidad_dict = zona_density

    # Asigno 'densidad_zona' en el df
    df['densidad_zona'] = df['zona'].map(densidad_dict).fillna(0.0)

    # Guardo el CSV actualizado
    df.to_csv(csv_path, index=False)
    print(f"'densidad_zona' actualizada en '{csv_path}'.")

if __name__ == "__main__":
    main()
