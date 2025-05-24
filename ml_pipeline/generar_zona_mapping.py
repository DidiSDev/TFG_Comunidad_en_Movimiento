import json
import os

def generar_zona_mapping(
    lat_min=40.9,
    lat_max=41.0,
    lng_min=-5.7,
    lng_max=-5.6,
    tamano_cuadricula_lat=0.0027,
    tamano_cuadricula_lng=0.0035
):
    """
    Genera un mapeo de zonas (zona_XX_YY) a códigos enteros y lo guarda en
    'comunidad_en_movimiento/assets/zona_mapping.json'.
    """
    zona_mapping = {}

    num_zonas_x = int((lng_max - lng_min) / tamano_cuadricula_lng)
    num_zonas_y = int((lat_max - lat_min) / tamano_cuadricula_lat)

    codigo = 0
    for y in range(num_zonas_y):
        for x in range(num_zonas_x):
            zona_nombre = f"zona_{x}_{y}"
            zona_mapping[zona_nombre] = codigo
            codigo += 1

    # VVoy a construir la ruta del archivo zona_mapping.json
    current_dir = os.path.dirname(os.path.abspath(__file__))
    assets_dir = os.path.normpath(
        os.path.join(current_dir, "..","assets")
    )

    if not os.path.exists(assets_dir):
        os.makedirs(assets_dir)
        print(f"Directorio 'assets' creado en: {assets_dir}")

    output_path = os.path.join(assets_dir, "zona_mapping.json")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(zona_mapping, f, indent=4, ensure_ascii=False)

    print(f"zona_mapping.json generado con {len(zona_mapping)} zonas en {output_path}.")

if __name__ == "__main__":
    generar_zona_mapping()
