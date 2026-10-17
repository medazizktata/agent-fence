# Calibration sample for nodelete-rules.yml. DATA ONLY, NEVER RUN.
# Contains 3 real delete/move calls the structural check must find.
import os
import shutil


def never_called():
    os.remove("/nonexistent/sample-target")
    shutil.rmtree("/nonexistent/sample-dir")
    os.replace("/nonexistent/a", "/nonexistent/b")
