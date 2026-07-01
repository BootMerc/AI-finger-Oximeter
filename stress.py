USE_REAL_DATA   = True          # True → load your own CSV; False → synthetic
REAL_DATA_CSV   = "my_data.csv"  # path to your CSV (ignored if USE_REAL_DATA=False)

N_SYNTHETIC     = 3000           # synthetic samples to generate
TEST_SPLIT      = 0.20           # 20 % held out for evaluation
EPOCHS          = 120
BATCH_SIZE      = 32
LEARNING_RATE   = 0.001

OUTPUT_DIR      = "output"       # folder for all generated files
import os, sys, textwrap, datetime
import numpy  as np
import tensorflow as tf
from   sklearn.preprocessing    import StandardScaler, LabelEncoder
from   sklearn.model_selection  import train_test_split, StratifiedKFold
from   sklearn.metrics          import (classification_report,
                                        confusion_matrix, accuracy_score)
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot   as plt
import matplotlib.gridspec as gridspec
import seaborn             as sns

os.makedirs(OUTPUT_DIR, exist_ok=True)

print(f"\n{'='*70}")
print("  Stress Classifier — Training Pipeline")
print(f"  TensorFlow {tf.__version__}  |  NumPy {np.__version__}")
print(f"  {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print(f"{'='*70}\n")

# DATA FORMAT (for real CSV)
#
#  Column 0  rmssd       — root mean square successive differences (ms)
#  Column 1  sdnn        — SD of all normal RR intervals (ms)
#  Column 2  pnn50       — % successive diffs > 50 ms  (0–100)
#  Column 3  bpm         — heart rate beats/min
#  Column 4  spo2        — blood oxygen % (90–100)
#  Column 5  activity    — integer  0=Resting  1=Walking  2=Running
#  Column 6  label       — integer  0=Low  1=Moderate  2=High
#

FEATURE_NAMES = ["RMSSD", "SDNN", "pNN50", "BPM", "SpO2", "Activity"]
CLASS_NAMES   = ["Low", "Moderate", "High"]

#DATA GENERATION / LOADING

def generate_synthetic_data(n: int, seed: int = 42) -> tuple:
    """
    Generates physiologically realistic synthetic data based on published norms:
      — Shaffer F & Ginsberg JP (2017) HRV metrics
      — Kim H-G et al. (2018) Stress detection using HRV
      — Taelman J et al. (2011) influence of mental stress on HRV

    Stress classes differ primarily in RMSSD/SDNN (parasympathetic suppression)
    and, secondarily, in BPM elevation and SpO2 stability.

    Returns X (n, 6) float32, y (n,) int32
    """
    rng = np.random.default_rng(seed)

    # ── Per-class distributions ──────────────────────────────────────────────
    # [mean, std] tuples for each feature per class
    # Class 0 = Low stress  (relaxed, high vagal tone → high RMSSD/SDNN)
    # Class 1 = Moderate    (mildly stressed)
    # Class 2 = High stress (strongly stressed, sympathetic dominance)

    params = {
        #            RMSSD         SDNN          pNN50        BPM           SpO2
        0: dict(rmssd=(52, 14), sdnn=(60, 12), pnn50=(30, 12), bpm=(64,  9), spo2=(98.2, 0.6)),
        1: dict(rmssd=(35,  9), sdnn=(42,  9), pnn50=(16,  8), bpm=(78, 10), spo2=(97.5, 0.8)),
        2: dict(rmssd=(21,  7), sdnn=(28,  7), pnn50=( 7,  5), bpm=(92, 12), spo2=(96.8, 1.0)),
    }

    # Activity distribution per class (Resting more likely when stressed)
    act_probs = {
        0: [0.35, 0.45, 0.20],   # Low:  active lifestyle
        1: [0.50, 0.35, 0.15],   # Mod:  moderately active
        2: [0.70, 0.25, 0.05],   # High: mostly resting (stress episode)
    }

    n_per_class = [n // 3, n // 3, n - 2 * (n // 3)]   # balanced classes
    rows, labels = [], []

    for cls in range(3):
        nc   = n_per_class[cls]
        p    = params[cls]
        rmssd = rng.normal(*p["rmssd"], nc).clip(5, 120)
        sdnn  = rng.normal(*p["sdnn"],  nc).clip(5, 120)
        pnn50 = rng.normal(*p["pnn50"], nc).clip(0, 100)
        bpm   = rng.normal(*p["bpm"],   nc).clip(40, 200)
        spo2  = rng.normal(*p["spo2"],  nc).clip(90, 100)
        act   = rng.choice([0, 1, 2], size=nc, p=act_probs[cls])

        # Enforce physiological correlation: high BPM → lower RMSSD
        rmssd *= np.clip(1.0 - (bpm - 70) * 0.004, 0.5, 1.3)

        # Add mild Gaussian noise to everything (sensor variability)
        rmssd += rng.normal(0, 1.5, nc)
        sdnn  += rng.normal(0, 1.2, nc)
        bpm   += rng.normal(0, 1.0, nc)
        spo2  += rng.normal(0, 0.2, nc)

        block = np.column_stack([rmssd.clip(3, 150),
                                 sdnn .clip(3, 150),
                                 pnn50.clip(0, 100),
                                 bpm  .clip(35, 200),
                                 spo2 .clip(90, 100),
                                 act.astype(float)])
        rows.append(block)
        labels.extend([cls] * nc)

    X = np.vstack(rows).astype(np.float32)
    y = np.array(labels, dtype=np.int32)

    # Shuffle
    idx = rng.permutation(len(y))
    return X[idx], y[idx]


if USE_REAL_DATA:
    print(f"[Data] Loading real data from '{REAL_DATA_CSV}' …")
    import pandas as pd
    df = pd.read_csv(REAL_DATA_CSV, header=0)
    df.columns = FEATURE_NAMES + ["label"]
    X = df[FEATURE_NAMES].values.astype(np.float32)
    y = df["label"].values.astype(np.int32)
    print(f"       Loaded {len(y):,} samples  —  "
          f"class distribution: {dict(zip(*np.unique(y, return_counts=True)))}")
else:
    print(f"[Data] Generating {N_SYNTHETIC:,} synthetic samples …")
    X, y = generate_synthetic_data(N_SYNTHETIC)
    print(f"       Class distribution: "
          f"{dict(zip(CLASS_NAMES, np.bincount(y)))}")

# ── Train / validation / test split ──────────────────────────────────────────
X_temp, X_test, y_temp, y_test = train_test_split(
    X, y, test_size=TEST_SPLIT, stratify=y, random_state=42)
X_train, X_val, y_train, y_val = train_test_split(
    X_temp, y_temp, test_size=0.15, stratify=y_temp, random_state=42)

print(f"       Train={len(y_train):,}  Val={len(y_val):,}  Test={len(y_test):,}\n")

# FEATURE SCALING
scaler  = StandardScaler()
X_train_s = scaler.fit_transform(X_train)
X_val_s   = scaler.transform(X_val)
X_test_s  = scaler.transform(X_test)

print("[Scaler] Feature means  :", np.round(scaler.mean_, 3))
print("[Scaler] Feature stds   :", np.round(scaler.scale_, 3))
print()

# MODEL DEFINITION
#
# Architecture: tiny MLP designed for INT8 quantisation on ESP32-S3
#   Input  → Dense(16, ReLU) → Dropout(0.3) → Dense(8, ReLU) → Dense(3, Softmax)
#
# Total params ≈ 259 (16*6+16 + 8*16+8 + 3*8+3 = 112+136+27 = 275)
# INT8 model size: ~3–5 KB on flash

def build_model(input_dim: int = 6, n_classes: int = 3) -> tf.keras.Model:
    inp = tf.keras.Input(shape=(input_dim,), name="features")
    x   = tf.keras.layers.Dense(16, activation="relu",
                                 kernel_regularizer=tf.keras.regularizers.l2(1e-4),
                                 name="dense_1")(inp)
    x   = tf.keras.layers.Dropout(0.30, name="dropout_1")(x)
    x   = tf.keras.layers.Dense(8,  activation="relu",
                                 name="dense_2")(x)
    out = tf.keras.layers.Dense(n_classes, activation="softmax",
                                 name="output")(x)
    return tf.keras.Model(inputs=inp, outputs=out, name="StressClassifier")

model = build_model()
model.compile(
    optimizer = tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE),
    loss      = "sparse_categorical_crossentropy",
    metrics   = ["accuracy"]
)
model.summary()

# TRAINING

callbacks = [
    tf.keras.callbacks.EarlyStopping(
        monitor="val_accuracy", patience=20,
        restore_best_weights=True, verbose=1),
    tf.keras.callbacks.ReduceLROnPlateau(
        monitor="val_loss", factor=0.5, patience=10,
        min_lr=1e-5, verbose=1),
]

print(f"\n[Train] Starting for up to {EPOCHS} epochs …\n")
history = model.fit(
    X_train_s, y_train,
    validation_data = (X_val_s, y_val),
    epochs          = EPOCHS,
    batch_size      = BATCH_SIZE,
    callbacks       = callbacks,
    verbose         = 1,
)

#  EVALUATION

test_loss, test_acc = model.evaluate(X_test_s, y_test, verbose=0)
y_pred = np.argmax(model.predict(X_test_s, verbose=0), axis=1)

print(f"\n{'='*50}")
print(f"  Test accuracy : {test_acc*100:.2f}%")
print(f"  Test loss     : {test_loss:.4f}")
print(f"{'='*50}\n")
print(classification_report(y_test, y_pred, target_names=CLASS_NAMES))

cm = confusion_matrix(y_test, y_pred)

# TFLite INT8 QUANTIZATION
print("[TFLite] Converting to INT8 quantised model …")

def representative_dataset_gen():
    for i in range(min(500, len(X_train_s))):
        yield [X_train_s[i:i+1].astype(np.float32)]

# 1. Trace the model inside a pure TF function to isolate it from Keras tracking
@tf.function
def run_forward(features):
    return model(features)

# 2. Freeze into a concrete function with a fixed shape of [1, 6] 
#    (This perfectly mimics the 1-by-1 sample execution on your ESP32-S3)
concrete_func = run_forward.get_concrete_function(
    tf.TensorSpec(shape=[1, 6], dtype=tf.float32, name="features")
)

# 3. Initialize converter from the frozen graph (bypasses Python 3.12 inspect bugs)
converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func])
converter.optimizations                         = [tf.lite.Optimize.DEFAULT]
converter.representative_dataset               = representative_dataset_gen
converter.target_spec.supported_ops           = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type                = tf.int8
converter.inference_output_type               = tf.int8

tflite_model = converter.convert()

tflite_path = os.path.join(OUTPUT_DIR, "stress_model.tflite")
with open(tflite_path, "wb") as f:
    f.write(tflite_model)

print(f"       Model written to '{tflite_path}'")
print(f"       Model size      : {len(tflite_model):,} bytes "
      f"({len(tflite_model)/1024:.1f} KB)\n")

# ── Verify quantised model accuracy ──────────────────────────────────────────
interp = tf.lite.Interpreter(model_content=tflite_model)
interp.allocate_tensors()
inp_det  = interp.get_input_details()[0]
out_det  = interp.get_output_details()[0]

q_preds = []
for sample in X_test_s:
    q_scale      = inp_det["quantization"][0]
    q_zero_point = inp_det["quantization"][1]
    
    x_q = (sample / q_scale + q_zero_point).astype(np.int8)
    interp.set_tensor(inp_det["index"], x_q.reshape(inp_det["shape"]))
    interp.invoke()
    raw = interp.get_tensor(out_det["index"])[0]
    q_preds.append(int(np.argmax(raw)))

q_acc = accuracy_score(y_test, q_preds)
print(f"[TFLite] Quantised model test accuracy : {q_acc*100:.2f}%")
print(f"         Accuracy drop vs float        : "
      f"{(test_acc - q_acc)*100:+.2f}%\n")

# GENERATE stress_model.h  (C array for Arduino)

def bytes_to_c_array(data: bytes, var_name: str = "stress_model_tflite") -> str:
    """Convert raw bytes → C array literal (same format as xxd -i)."""
    hex_values = ", ".join(f"0x{b:02x}" for b in data)
    # Wrap at 12 bytes per line for readability
    chunks = [hex_values[i:i+60] for i in range(0, len(hex_values), 60)]
    body   = "\n  ".join(chunks)
    return (
        f"// Auto-generated by train_stress_model.py\n"
        f"// Model size: {len(data)} bytes ({len(data)/1024:.1f} KB)\n"
        f"// Do not edit manually.\n\n"
        f"#pragma once\n\n"
        f"alignas(8)\n"
        f"const unsigned char {var_name}[] = {{\n"
        f"  {body}\n"
        f"}};\n\n"
        f"const unsigned int {var_name}_len = {len(data)};\n"
    )

model_h_path = os.path.join(OUTPUT_DIR, "stress_model.h")
with open(model_h_path, "w") as f:
    f.write(bytes_to_c_array(tflite_model))

print(f"[Header] stress_model.h written to '{model_h_path}'")

# GENERATE scaler_constants.h  (Z-score params for Arduino)

def fmt_float_array(arr, name, comment=""):
    vals = ", ".join(f"{v:.6f}f" for v in arr)
    return f"const float {name}[{len(arr)}] = {{ {vals} }};  // {comment}\n"

# Quantization parameters from the TFLite model
q_scale      = inp_det["quantization"][0]
q_zero_point = inp_det["quantization"][1]

scaler_h = textwrap.dedent(f"""\
    // Auto-generated by train_stress_model.py — DO NOT EDIT
    // Z-score normalisation constants for the stress classifier.
    // Copy this file into your Arduino sketch folder.
    //
    // Usage in Arduino:
    //   float normalised = (raw_value - FEAT_MEAN[i]) / FEAT_STD[i];
    //   input->data.int8[i] = (int8_t)(normalised / {q_scale:.6f}f + {q_zero_point});
    //
    // Feature order: RMSSD | SDNN | pNN50 | BPM | SpO2 | Activity

    #pragma once

    """)

scaler_h += fmt_float_array(scaler.mean_,  "FEAT_MEAN",
                             "feature means  (RMSSD, SDNN, pNN50, BPM, SpO2, Activity)")
scaler_h += fmt_float_array(scaler.scale_, "FEAT_STD",
                             "feature std devs")
scaler_h += f"\n"
scaler_h += f"constexpr float TFLITE_INPUT_SCALE      = {q_scale:.8f}f;\n"
scaler_h += f"constexpr int   TFLITE_INPUT_ZERO_POINT = {q_zero_point};\n"
scaler_h += f"\n"
scaler_h += (
    "// Class index → label mapping\n"
    "// 0 = Low stress   1 = Moderate stress   2 = High stress\n"
    'const char* STRESS_LABELS[] = {"Low", "Moderate", "High"};\n'
)

scaler_h_path = os.path.join(OUTPUT_DIR, "scaler_constants.h")

# FIX: Added encoding="utf-8" to prevent Windows CP1252 crash
with open(scaler_h_path, "w", encoding="utf-8") as f:
    f.write(scaler_h)

print(f"[Header] scaler_constants.h written to '{scaler_h_path}'\n")

# TRAINING REPORT PNG

fig = plt.figure(figsize=(16, 10), facecolor="#ffffff")
fig.suptitle("Stress Classifier — Training Report",
             fontsize=16, color="white", fontweight="bold", y=0.98)

gs = gridspec.GridSpec(2, 3, figure=fig, hspace=0.42, wspace=0.35)

# ── (0,0) Accuracy curve ─────────────────────────────────────────────────────
ax1 = fig.add_subplot(gs[0, 0])
ax1.set_facecolor("#ffffff")
ax1.plot(history.history["accuracy"],     color="#58a6ff", lw=2, label="Train")
ax1.plot(history.history["val_accuracy"], color="#3fb950", lw=2, label="Val")
ax1.set_title("Accuracy",  color="white", fontsize=12)
ax1.set_xlabel("Epoch",    color="#000000")
ax1.set_ylabel("Accuracy", color="#000000")
ax1.legend(facecolor="#21262d", labelcolor="white")
ax1.tick_params(colors="#000000")
for sp in ax1.spines.values(): sp.set_color("#30363d")
ax1.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:.0%}"))

# ── (0,1) Loss curve ─────────────────────────────────────────────────────────
ax2 = fig.add_subplot(gs[0, 1])
ax2.set_facecolor("#ffffff")
ax2.plot(history.history["loss"],     color="#58a6ff", lw=2, label="Train")
ax2.plot(history.history["val_loss"], color="#f97316", lw=2, label="Val")
ax2.set_title("Loss",  color="white", fontsize=12)
ax2.set_xlabel("Epoch", color="#000000")
ax2.set_ylabel("Loss",  color="#000000")
ax2.legend(facecolor="#21262d", labelcolor="white")
ax2.tick_params(colors="#000000")
for sp in ax2.spines.values(): sp.set_color("#30363d")

# ── (0,2) Confusion matrix ───────────────────────────────────────────────────
ax3 = fig.add_subplot(gs[0, 2])
ax3.set_facecolor("#ffffff")
sns.heatmap(cm, annot=True, fmt="d", cmap="Blues",
            xticklabels=CLASS_NAMES, yticklabels=CLASS_NAMES,
            ax=ax3, cbar=False,
            annot_kws={"color": "black", "fontsize": 12})
ax3.set_title("Confusion Matrix (Test)", color="white", fontsize=12)
ax3.set_xlabel("Predicted", color="#8b949e")
ax3.set_ylabel("Actual",    color="#8b949e")
ax3.tick_params(colors="#8b949e")

# ── (1,0) Feature distributions by class (RMSSD) ─────────────────────────────
ax4 = fig.add_subplot(gs[1, 0])
ax4.set_facecolor("#ffffff")
colors_cls = ["#3fb950", "#f0e68c", "#f85149"]
for cls_i, (cls_name, col) in enumerate(zip(CLASS_NAMES, colors_cls)):
    mask = (y == cls_i)
    ax4.hist(X[mask, 0], bins=30, alpha=0.65, color=col, label=cls_name,
             edgecolor="none")
ax4.set_title("RMSSD Distribution by Class", color="white", fontsize=11)
ax4.set_xlabel("RMSSD (ms)", color="#8b949e")
ax4.set_ylabel("Count",      color="#8b949e")
ax4.legend(facecolor="#21262d", labelcolor="white")
ax4.tick_params(colors="#8b949e")
for sp in ax4.spines.values(): sp.set_color("#30363d")

# ── (1,1) RMSSD vs BPM scatter ───────────────────────────────────────────────
ax5 = fig.add_subplot(gs[1, 1])
ax5.set_facecolor("#ffffff")
for cls_i, (cls_name, col) in enumerate(zip(CLASS_NAMES, colors_cls)):
    mask = (y == cls_i)
    ax5.scatter(X[mask, 3], X[mask, 0], s=8, alpha=0.4,
                color=col, label=cls_name)
ax5.set_title("BPM vs RMSSD",    color="white", fontsize=11)
ax5.set_xlabel("BPM",            color="#8b949e")
ax5.set_ylabel("RMSSD (ms)",     color="#8b949e")
ax5.legend(facecolor="#21262d",  labelcolor="white", markerscale=2)
ax5.tick_params(colors="#8b949e")
for sp in ax5.spines.values(): sp.set_color("#30363d")

# ── (1,2) Stats summary text block ───────────────────────────────────────────
ax6 = fig.add_subplot(gs[1, 2])
ax6.set_facecolor("#000000")
ax6.axis("off")

best_epoch = int(np.argmax(history.history["val_accuracy"])) + 1
lines = [
    ("Float model accuracy",   f"{test_acc*100:.2f}%"),
    ("INT8 model accuracy",    f"{q_acc*100:.2f}%"),
    ("Accuracy after quant.",  f"{(test_acc-q_acc)*100:+.2f}%"),
    ("Best val epoch",         f"{best_epoch}"),
    ("Model size",             f"{len(tflite_model)/1024:.1f} KB"),
    ("Total parameters",       f"{model.count_params():,}"),
    ("Train samples",          f"{len(y_train):,}"),
    ("Test samples",           f"{len(y_test):,}"),
]
table_y = 0.90
ax6.text(0.05, table_y + 0.06, "Model Stats", transform=ax6.transAxes,
         fontsize=12, color="#58a6ff", fontweight="bold")
for i, (k, v) in enumerate(lines):
    yp = table_y - i * 0.105
    ax6.text(0.05, yp, k, transform=ax6.transAxes, fontsize=10, color="#000000")
    ax6.text(0.72, yp, v, transform=ax6.transAxes, fontsize=10, color="black",
             fontweight="bold")

report_path = os.path.join(OUTPUT_DIR, "training_report.png")
plt.savefig(report_path, dpi=140, bbox_inches="tight", facecolor="#FFF6F6")
plt.close()
print(f"[Report] Training report saved to '{report_path}'")

# MODEL SUMMARY TEXT FILE

summary_lines = []
model.summary(print_fn=lambda s: summary_lines.append(s))

# FIX: Explicitly using utf-8 encoding to bulletproof file writing on Windows
with open(os.path.join(OUTPUT_DIR, "model_summary.txt"), "w", encoding="utf-8") as f:
    f.write("STRESS CLASSIFIER — MODEL SUMMARY\n")
    f.write(f"Generated : {datetime.datetime.now()}\n")
    f.write(f"TensorFlow: {tf.__version__}\n\n")
    f.write("\n".join(summary_lines))
    f.write("\n\n")
    f.write(f"Float32 test accuracy  : {test_acc*100:.2f}%\n")
    f.write(f"INT8    test accuracy  : {q_acc*100:.2f}%\n")
    f.write(f"TFLite model size      : {len(tflite_model)} bytes "
            f"({len(tflite_model)/1024:.1f} KB)\n")
    f.write(f"\nScaler means  : {scaler.mean_.tolist()}\n")
    f.write(f"Scaler scales : {scaler.scale_.tolist()}\n")
    f.write(f"\nTFLite input  scale      : {q_scale}\n")
    f.write(f"TFLite input  zero_point : {q_zero_point}\n")

# FINAL CONSOLE SUMMARY

print(f"""
{'='*70}
  DONE — OUTPUT FILES
{'='*70}
  output/stress_model.tflite   → drop into sketch folder
  output/stress_model.h        → drop into sketch folder
  output/scaler_constants.h    → drop into sketch folder
  output/training_report.png   → accuracy / confusion matrix chart
  output/model_summary.txt     → layer shapes & quantization log
{'='*70}

  ARDUINO QUICK-REFERENCE
  ─────────────────────────────────────────────────────────────────────
  Add to your includes:
    #include "stress_model.h"
    #include "scaler_constants.h"

  Inference call (already written in Step 5 of the guide):
    float normalised = (raw_value - FEAT_MEAN[i]) / FEAT_STD[i];
    input->data.int8[i] = (int8_t)(normalised / TFLITE_INPUT_SCALE
                                   + TFLITE_INPUT_ZERO_POINT);

  Output classes:
    0 → STRESS_LABELS[0]  = "Low"
    1 → STRESS_LABELS[1]  = "Moderate"
    2 → STRESS_LABELS[2]  = "High"

  Estimated flash usage : {len(tflite_model)/1024:.1f} KB  (model)
                        + ~8 KB  (tensor arena in PSRAM)
  Inference time on LX7 @ 240 MHz: < 1 ms

  REPLACE SYNTHETIC DATA
  ─────────────────────────────────────────────────────────────────────
  1. Log BLE output from your device for 30+ minutes across activities.
  2. Manually label windows as 0/1/2 (Low/Moderate/High stress).
  3. Save as CSV: rmssd,sdnn,pnn50,bpm,spo2,activity_int,label_int
  4. Set  USE_REAL_DATA = True  and  REAL_DATA_CSV = "your_file.csv"
  5. Re-run this script — all headers are regenerated automatically.
{'='*70}
""")