import tensorflow as tf


SOURCE_MODEL = "eggplant_model.h5"
TARGET_MODEL = "model.tflite"


def main() -> None:
    model = tf.keras.models.load_model(SOURCE_MODEL)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    with open(TARGET_MODEL, "wb") as target:
        target.write(tflite_model)

    print(f"Saved {TARGET_MODEL}")


if __name__ == "__main__":
    main()
