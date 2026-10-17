# Calibration sample for nodelete-rules.yml. DATA ONLY, NEVER RUN.
# The same words as text only: the structural check must find 0 here.
# os.remove("in a comment")
edits = [("os.remove(os.path.join(FRAG_DIR, fn))", "")]
message = "never call shutil.rmtree(path) here"
