# Calibration sample for nodelete-rules.yml. DATA ONLY, NEVER RUN (not executable).
# Contains 2 real delete commands the structural check must find.
never_called() {
  rm -f /nonexistent/sample-target
  find /nonexistent -name x && rmdir /nonexistent/sample-dir
}
