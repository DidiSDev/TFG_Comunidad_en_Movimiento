import os
import json
import warnings
import numpy as np
import pandas as pd
import tensorflow as tf
import joblib

from datetime import datetime
from geopy.distance import geodesic

from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import StratifiedKFold
from sklearn.utils.class_weight import compute_class_weight
from sklearn.metrics import (
    classification_report, roc_auc_score,
    precision_score, recall_score, f1_score
)
from sklearn.exceptions import UndefinedMetricWarning
from imblearn.over_sampling import SMOTE

warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UndefinedMetricWarning)

#########################
# PARÁMETROS DE LÍMITES #
#########################
lat_min, lat_max = 40.9, 41.0
lng_min, lng_max = -5.7, -5.6

# Tamaños de cuadrícula ~300m
tamano_cuadricula_lat = 0.0027
tamano_cuadricula_lng = 0.0035

# POIs (si se usan en dist_min_poi, ya está calculado en el CSV)
POIs = [
    {"nombre": "Estación de Policía", "lat": 40.9680, "lng": -5.6630},
    {"nombre": "Hospital",            "lat": 40.9740, "lng": -5.6550},
]

def main():
    current_dir = os.path.dirname(os.path.abspath(__file__))

    # 1) Cargo CSV
    csv_path = os.path.join(current_dir, "datos_incidencias.csv")
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"No se encontró el archivo {csv_path}. Ejecuta antes generar_csv_incidencias.py")

    df = pd.read_csv(csv_path)
    if df.empty:
        raise ValueError("El CSV 'datos_incidencias.csv' está vacío.")

    # 2) llamo zona_mapping.json
    zona_mapping_path = os.path.normpath(
        os.path.join(current_dir, "..", "assets", "zona_mapping.json")
    )
    if not os.path.exists(zona_mapping_path):
        raise FileNotFoundError(f"No se encontró zona_mapping.json en {zona_mapping_path}.")

    with open(zona_mapping_path, "r", encoding="utf-8") as f:
        zona_mapping = json.load(f)

    # 3) zona_density.json
    zona_density_path = os.path.normpath(
        os.path.join(current_dir, "..", "assets", "zona_density.json")
    )
    if not os.path.exists(zona_density_path):
        raise FileNotFoundError(f"No se encontró zona_density.json en {zona_density_path}.")

    with open(zona_density_path, "r", encoding="utf-8") as f:
        zona_density = json.load(f)

    # Añadir 'zona_cod' y 'densidad_zona' al datafframe (si no existen)
    if "zona_cod" not in df.columns:
        # Asignamos con el zona_mapping
        def asignar_zona_cod(zona):
            return zona_mapping.get(zona, -1)
        df["zona_cod"] = df["zona"].apply(asignar_zona_cod)

    if "densidad_zona" not in df.columns:
        # Asigna densidad_zona basada en zona_density.json
        def obtener_densidad(zona):
            return zona_density.get(zona, 0.0)
        df["densidad_zona"] = df["zona"].apply(obtener_densidad)

    # Elimina duplicados
    num_dupl = df.duplicated().sum()
    if num_dupl > 0:
        print(f"Se detectaron {num_dupl} duplicados. Se eliminan.")
        df.drop_duplicates(inplace=True)

    # Filtra filas incompletas
    df.dropna(subset=[
        "lat_norm", "lng_norm", "cat_acc",
        "month", "weekday", "zona_cod",
        "dist_min_poi", "peligro", "densidad_zona"
    ], inplace=True)

    if df.empty:
        raise ValueError("Tras limpieza, no quedan filas en df.")

    # X e y
    X = df[[
        "lat_norm", "lng_norm", "cat_acc",
        "month", "weekday", "zona_cod",
        "dist_min_poi", "densidad_zona"
    ]].values
    y = df["peligro"].values

    print(f"Shape X: {X.shape}, Shape y: {y.shape}")

    # SMOTE
    sm = SMOTE(random_state=42)
    X_sm, y_sm = sm.fit_resample(X, y)

    # Ver distribución
    from collections import Counter
    print("Distribución original:", Counter(y))
    print("Distribución tras SMOTE:", Counter(y_sm))

    # Class weights
    # Los pesos de clase se calculan en función de la distribución de clases del df
    class_weights = compute_class_weight(
        class_weight="balanced",
        classes=np.unique(y_sm),
        y=y_sm
    )
    class_weight_dict = {i: w for i, w in enumerate(class_weights)}
    print("Pesos de clase:", class_weight_dict)

    # Cross-validation
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

    acc_list, auc_list = [], []
    precision_list, recall_list = [], []
    f1_list, roc_auc_list = [], []

    fold_num = 1
    for train_index, test_index in skf.split(X_sm, y_sm):
        print(f"\n=== FOLD {fold_num} ===")

        X_train, X_test = X_sm[train_index], X_sm[test_index]
        y_train, y_test = y_sm[train_index], y_sm[test_index]

        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)

        # Red neuronal con tensorflow
        model = tf.keras.Sequential([
            tf.keras.layers.Input(shape=(8,)),
            tf.keras.layers.Dense(64, activation='relu'),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Dropout(0.2),

            tf.keras.layers.Dense(32, activation='relu'),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Dropout(0.2),

            tf.keras.layers.Dense(16, activation='relu'),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Dropout(0.2),

            tf.keras.layers.Dense(1, activation='sigmoid')
        ])

        model.compile(
            optimizer="adam",
            loss="binary_crossentropy",
            metrics=["accuracy", tf.keras.metrics.AUC(name="auc")]
        )

        early_stop = tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=7,
            restore_best_weights=True
        )
        reduce_lr = tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=3,
            min_lr=1e-6,
            verbose=1
        )

        history = model.fit(
            X_train_scaled, y_train,
            validation_data=(X_test_scaled, y_test),
            epochs=100,
            batch_size=32,
            callbacks=[early_stop, reduce_lr],
            class_weight=class_weight_dict,
            verbose=1
        )
        

        # No debería no haber pérdida, pero al tener tan pocos datos tiene demasiado peso en la predicción, lo elimino de su entrenamiento (no lo uso pero lo dejo aqui)
        loss, acc, aucv = model.evaluate(X_test_scaled, y_test, verbose=0)
        print(f"[Fold {fold_num}] accuracy={acc:.4f}, auc={aucv:.4f}")

        y_pred_prob = model.predict(X_test_scaled).ravel()
        y_pred = (y_pred_prob > 0.5).astype(int)

        prec = precision_score(y_test, y_pred, zero_division=0)
        rec = recall_score(y_test, y_pred, zero_division=0)
        f1 = f1_score(y_test, y_pred, zero_division=0)
        roc = roc_auc_score(y_test, y_pred_prob)

        print("classification_report:\n", classification_report(y_test, y_pred, zero_division=0))
        print(f"AUC (prob): {roc:.4f}")

        acc_list.append(acc)
        auc_list.append(aucv)
        precision_list.append(prec)
        recall_list.append(rec)
        f1_list.append(f1)
        roc_auc_list.append(roc)

        fold_num += 1

    # Resultados CV
    print("\n=== RESULTADOS CV ===")
    print(f"Accuracy Medio: {np.mean(acc_list):.4f} ± {np.std(acc_list):.4f}")
    print(f"AUC Medio:      {np.mean(auc_list):.4f} ± {np.std(auc_list):.4f}")
    print(f"Precision:      {np.mean(precision_list):.4f} ± {np.std(precision_list):.4f}")
    print(f"Recall:         {np.mean(recall_list):.4f} ± {np.std(recall_list):.4f}")
    print(f"F1-score:       {np.mean(f1_list):.4f} ± {np.std(f1_list):.4f}")
    print(f"ROC-AUC:        {np.mean(roc_auc_list):.4f} ± {np.std(roc_auc_list):.4f}")

    # ENTRENAMIENTO FINAL con TODO X_sm
    scaler_final = StandardScaler()
    X_sm_scaled = scaler_final.fit_transform(X_sm)

    model_final = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(8,)),
        tf.keras.layers.Dense(64, activation='relu'),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Dropout(0.2),

        tf.keras.layers.Dense(32, activation='relu'),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Dropout(0.2),

        tf.keras.layers.Dense(16, activation='relu'),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Dropout(0.2),

        tf.keras.layers.Dense(1, activation='sigmoid')
    ])
    model_final.compile(
        optimizer="adam",
        loss="binary_crossentropy",
        metrics=["accuracy", tf.keras.metrics.AUC(name="auc")]
    )

    early_stop_final = tf.keras.callbacks.EarlyStopping(monitor="loss", patience=7, restore_best_weights=True)
    reduce_lr_final = tf.keras.callbacks.ReduceLROnPlateau(
        monitor="loss",
        factor=0.5,
        patience=3,
        min_lr=1e-6,
        verbose=1
    )

    print("\nEntrenando modelo final con todos los datos oversampled (SMOTE)...")
    model_final.fit(
        X_sm_scaled, y_sm,
        epochs=100,
        batch_size=32,
        callbacks=[early_stop_final, reduce_lr_final],
        class_weight=class_weight_dict,
        verbose=1
    )

    # Guardar el modelo en keras normal
    model_path = os.path.join(current_dir, "modelo_ia.keras")
    model_final.save(model_path)
    print(f"Modelo final guardado como: {model_path}")

    # Convertir a TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model_final)
    tflite_model = converter.convert()
    # Guardo en .tflite en lib/assets/modelos
    tflite_output_dir = os.path.normpath(
        os.path.join(current_dir, "..", "lib", "assets", "modelos")
    )
    if not os.path.exists(tflite_output_dir):
        os.makedirs(tflite_output_dir)

    tflite_path = os.path.join(tflite_output_dir, "modelo_ia.tflite")
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    print(f"Modelo TFLite guardado en: {tflite_path}")

    # guardo scaler_params en comunidad_en_movimiento/assets
    assets_dir = os.path.normpath(
        os.path.join(current_dir, "..", "assets")
    )
    if not os.path.exists(assets_dir):
        os.makedirs(assets_dir)

    scaler_params_path = os.path.join(assets_dir, "scaler_params.json")
    with open(scaler_params_path, "w", encoding="utf-8") as f:
        json.dump(
            {"mean": scaler_final.mean_.tolist(), "scale": scaler_final.scale_.tolist()},
            f,
            indent=4,
            ensure_ascii=False
        )
    print(f"Parámetros del scaler guardados en: {scaler_params_path}")

    print("\nEntrenamiento COMPLETADO.")

if __name__ == "__main__":
    main()
